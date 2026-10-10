import Foundation
import Darwin
import Testing
@testable import CryptaCore

@Suite(.serialized)
struct PersistenceTests {
    @Test func failureBoundariesAndEncryptedStaging() async throws {
        let directory = try TestDirectory(); defer { directory.remove() }
        let engine = VaultEngine()
        try await engine.create(at: directory.vault, passphrase: testPassphrase, name: testName, parameters: testParameters)
        await engine.lock()
        let ordinary = EncryptedFileStore()
        let original = try ordinary.read(directory.vault)
        for point: EncryptedFileStore.Checkpoint in [.staged, .written, .fileSynced, .beforeRename] {
            let store = EncryptedFileStore(checkpoint: { at in
                if at == .written {
                    let stages = try FileManager.default.contentsOfDirectory(at: directory.url, includingPropertiesForKeys: nil)
                        .filter { $0.lastPathComponent.hasSuffix(".crypta-stage") }
                    let file = try #require(stages.first)
                    let contents = try Data(contentsOf: file)
                    #expect(contents == original.bytes)
                    #expect(contents.range(of: Data("SYNTHETIC-SECRET".utf8)) == nil)
                    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
                }
                if at == point { throw VaultError.fileAccess }
            }, writeChunkSize: 7)
            #expect(throws: VaultError.fileAccess) { try store.commit(original.bytes, to: directory.vault, expecting: original.version) }
            #expect(try ordinary.read(directory.vault).version == original.version)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path).allSatisfy { !$0.hasSuffix(".crypta-stage") })
        }
        let partialWrites = EncryptedFileStore(writeChunkSize: 1)
        let updated = try partialWrites.commit(original.bytes, to: directory.vault, expecting: original.version)
        #expect(updated.bytes == original.bytes)
        #expect(updated.version.inode != original.version.inode)
        for point: EncryptedFileStore.Checkpoint in [.renamed, .directorySynced] {
            let baseline = try ordinary.read(directory.vault)
            let uncertain = EncryptedFileStore(checkpoint: { if $0 == point { throw VaultError.fileAccess } })
            #expect(throws: VaultError.durabilityUncertain) { try uncertain.commit(original.bytes, to: directory.vault, expecting: baseline.version) }
            let next = VaultEngine()
            try await next.open(at: directory.vault, passphrase: testPassphrase)
            #expect(try await next.readVault().name == testName)
        }
    }

    @Test func uncertainPassphraseChangeLocksSession() async throws {
        let directory = try TestDirectory(); defer { directory.remove() }
        let initial = VaultEngine()
        try await initial.create(at: directory.vault, passphrase: testPassphrase, name: testName, parameters: testParameters)
        await initial.lock()
        let engine = VaultEngine(store: .init(checkpoint: { if $0 == .renamed { throw VaultError.fileAccess } }))
        try await engine.open(at: directory.vault, passphrase: testPassphrase)
        await #expect(throws: VaultError.durabilityUncertain) {
            try await engine.changePassphrase(current: testPassphrase, new: "changed", parameters: testParameters)
        }
        #expect(await !engine.isUnlocked)
        let reopened = VaultEngine()
        try await reopened.open(at: directory.vault, passphrase: "changed")
        #expect(try await reopened.readVault().name == testName)
    }

    @Test func inaccessibleSymlinksHardlinksAndNoClobber() async throws {
        let directory = try TestDirectory(); defer { directory.remove() }
        let engine = VaultEngine()
        try await engine.create(at: directory.vault, passphrase: testPassphrase, name: testName, parameters: testParameters)
        let store = EncryptedFileStore()
        let snapshot = try store.read(directory.vault)
        #expect(throws: VaultError.conflict) { try store.commit(snapshot.bytes, to: directory.vault, expecting: nil) }
        let symlink = directory.url.appendingPathComponent("Link.crypta")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: directory.vault)
        #expect(throws: VaultError.fileAccess) { try store.read(symlink) }
        #expect(throws: VaultError.conflict) { try store.commit(snapshot.bytes, to: symlink, expecting: nil) }
        let hardlink = directory.url.appendingPathComponent("Hard.crypta")
        try FileManager.default.linkItem(at: directory.vault, to: hardlink)
        #expect(throws: VaultError.unsafeFile) { try store.read(hardlink) }
        try FileManager.default.removeItem(at: hardlink)
        #expect(chmod(directory.vault.path, 0) == 0)
        defer { _ = chmod(directory.vault.path, 0o600) }
        #expect(throws: VaultError.fileAccess) { try store.read(directory.vault) }
        #expect(throws: VaultError.fileAccess) { try store.read(directory.url.appendingPathComponent("Missing.crypta")) }
        let fifo = directory.url.appendingPathComponent("Pipe.crypta")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(throws: VaultError.unsafeFile) { try store.read(fifo) }
    }

    @Test func crossProcessLock() async throws {
        let directory = try TestDirectory(); defer { directory.remove() }
        let engine = VaultEngine()
        try await engine.create(at: directory.vault, passphrase: testPassphrase, name: testName, parameters: testParameters)
        let store = EncryptedFileStore(), baseline = try store.read(directory.vault)
        let child = Process(), output = Pipe(), input = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        child.arguments = ["-c", "import fcntl,sys; f=open(sys.argv[1], 'r+'); fcntl.flock(f,fcntl.LOCK_EX); print('ready',flush=True); sys.stdin.readline()",
                           directory.url.appendingPathComponent(".Test.crypta.crypta-lock").path]
        child.standardOutput = output; child.standardInput = input
        try child.run()
        defer { try? input.fileHandleForWriting.close(); child.waitUntilExit() }
        #expect(output.fileHandleForReading.readData(ofLength: 6) == Data("ready\n".utf8))
        #expect(throws: VaultError.conflict) { try store.commit(baseline.bytes, to: directory.vault, expecting: baseline.version) }
    }
    @Test func interruptedShortWritesAndDiskFull() async throws {
        let directory = try TestDirectory(); defer { directory.remove() }
        let engine = VaultEngine()
        try await engine.create(at: directory.vault, passphrase: testPassphrase, name: testName, parameters: testParameters)
        let original = try EncryptedFileStore().read(directory.vault)
        // Per-call state is protected because the syscall boundary is Sendable.
        final class Counter: @unchecked Sendable {
            let lock = NSLock()
            var value = 0
            func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
        }
        let counter = Counter()
        let failed = EncryptedFileStore(writeOperation: { fd, pointer, count in
            switch counter.next() {
            case 1: errno = EINTR; return -1
            case 2: return Darwin.write(fd, pointer, min(3, count))
            default: errno = ENOSPC; return -1
            }
        })
        #expect(throws: VaultError.fileAccess) { try failed.commit(original.bytes, to: directory.vault, expecting: original.version) }
        #expect(try EncryptedFileStore().read(directory.vault).version == original.version)
        let retried = Counter()
        let successful = EncryptedFileStore(writeOperation: { fd, pointer, count in
            if retried.next() == 1 { errno = EINTR; return -1 }
            return Darwin.write(fd, pointer, min(3, count))
        })
        #expect(try successful.commit(original.bytes, to: directory.vault, expecting: original.version).bytes == original.bytes)
    }

}
