import Foundation
import Darwin

/// macOS local-filesystem implementation. It never accepts plaintext.
struct EncryptedFileStore: Sendable {
    struct Version: Equatable, Sendable {
        let digest: Data
        let device: Int32
        let inode: UInt64
    }
    struct Snapshot: Sendable { let bytes: Data; let version: Version }
    enum Checkpoint: Sendable { case staged, written, fileSynced, beforeRename, renamed, directorySynced }
    // Internal failure injection only; no app preference or public weakening switch.
    var checkpoint: @Sendable (Checkpoint) throws -> Void = { _ in }
    var writeChunkSize = 64 * 1024
    var writeOperation: @Sendable (Int32, UnsafeRawPointer, Int) -> Int = { Darwin.write($0, $1, $2) }

    func read(_ url: URL) throws -> Snapshot {
        try directory(url) { directoryFD, name in try read(directoryFD, name) }
    }

    func commit(_ bytes: Data, to url: URL, expecting baseline: Version?) throws -> Snapshot {
        _ = try VaultFormat.parse(bytes)
        return try directory(url) { directoryFD, name in
            let lockName = "." + name + ".crypta-lock"
            let lockFD = openat(directoryFD, lockName, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard lockFD >= 0 else { throw VaultError.fileAccess }
            defer { close(lockFD) }
            try regular(lockFD)
            guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { throw VaultError.conflict }
            defer { _ = flock(lockFD, LOCK_UN) }
            if let baseline {
                let current: Snapshot
                do { current = try read(directoryFD, name) } catch { throw VaultError.conflict }
                guard current.version == baseline else { throw VaultError.conflict }
            } else {
                var status = stat()
                if fstatat(directoryFD, name, &status, AT_SYMLINK_NOFOLLOW) == 0 { throw VaultError.conflict }
                guard errno == ENOENT else { throw VaultError.fileAccess }
            }

            let staging = "." + name + "." + UUID().uuidString + ".crypta-stage"
            let fd = openat(directoryFD, staging, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw VaultError.fileAccess }
            var descriptorOpen = true
            var renamed = false
            defer {
                if descriptorOpen { close(fd) }
                if !renamed { _ = unlinkat(directoryFD, staging, 0) }
            }
            do {
                try checkpoint(.staged)
                try bytes.withUnsafeBytes { buffer in
                    guard let base = buffer.baseAddress else { throw VaultError.invalidFormat }
                    var position = 0
                    while position < bytes.count {
                        let count = writeOperation(fd, base.advanced(by: position), min(max(1, writeChunkSize), bytes.count - position))
                        if count < 0 && errno == EINTR { continue }
                        guard count > 0 else { throw VaultError.fileAccess }
                        position += count
                    }
                }
                try checkpoint(.written)
                guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0 else { throw VaultError.fileAccess }
                try checkpoint(.fileSynced)
                let closeResult = close(fd)
                descriptorOpen = false
                guard closeResult == 0 else { throw VaultError.fileAccess }
                // Check again to catch a noncooperating writer during the staging write.
                if let baseline {
                    guard try read(directoryFD, name).version == baseline else { throw VaultError.conflict }
                }
                try checkpoint(.beforeRename)
                let result = baseline == nil
                    ? renameatx_np(directoryFD, staging, directoryFD, name, UInt32(RENAME_EXCL))
                    : renameat(directoryFD, staging, directoryFD, name)
                guard result == 0 else { throw errno == EEXIST ? VaultError.conflict : VaultError.fileAccess }
                renamed = true
                try checkpoint(.renamed)
                guard fsync(directoryFD) == 0 else { throw VaultError.durabilityUncertain }
                try checkpoint(.directorySynced)
                let saved = try read(directoryFD, name)
                guard saved.version.digest == Crypto.fingerprint(bytes) else { throw VaultError.durabilityUncertain }
                return saved
            } catch {
                // Never claim rollback after rename. The caller must lock and explicitly reopen.
                if renamed { throw VaultError.durabilityUncertain }
                throw error
            }
        }
    }

    private func directory<T>(_ url: URL, _ operation: (Int32, String) throws -> T) throws -> T {
        guard url.isFileURL, !url.path.utf8.contains(0) else { throw VaultError.unsafeFile }
        let name = url.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !name.utf8.contains(0) else { throw VaultError.unsafeFile }
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let fd = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw VaultError.fileAccess }
        defer { close(fd) }
        return try operation(fd, name)
    }

    private func regular(_ fd: Int32) throws {
        var status = stat()
        guard fstat(fd, &status) == 0 else { throw VaultError.fileAccess }
        guard (status.st_mode & S_IFMT) == S_IFREG, status.st_nlink == 1 else { throw VaultError.unsafeFile }
    }

    private func read(_ directoryFD: Int32, _ name: String) throws -> Snapshot {
        let fd = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw VaultError.fileAccess }
        defer { close(fd) }
        try regular(fd)
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_size >= 208, before.st_size <= VaultFormat.maxFileBytes else {
            throw VaultError.invalidFormat
        }
        var result = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw VaultError.fileAccess }
            if count == 0 { break }
            guard result.count <= VaultFormat.maxFileBytes - count else { throw VaultError.resourceLimit }
            result.append(contentsOf: chunk.prefix(count))
        }
        var after = stat()
        guard fstat(fd, &after) == 0 else { throw VaultError.fileAccess }
        guard before.st_size == after.st_size, before.st_mtimespec == after.st_mtimespec,
              before.st_ctimespec == after.st_ctimespec, result.count == after.st_size else { throw VaultError.conflict }
        return Snapshot(bytes: result, version: Version(digest: Crypto.fingerprint(result), device: after.st_dev, inode: after.st_ino))
    }
}

private func == (lhs: timespec, rhs: timespec) -> Bool {
    lhs.tv_sec == rhs.tv_sec && lhs.tv_nsec == rhs.tv_nsec
}
