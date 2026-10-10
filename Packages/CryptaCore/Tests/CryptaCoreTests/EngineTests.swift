import Foundation
import Testing
@testable import CryptaCore

@Suite(.serialized)
struct EngineTests {
    @Test func lifecycleAndPassphraseChange() async throws {
        let directory = try TestDirectory(); defer { directory.remove() }
        let engine = VaultEngine()
        try await engine.create(at: directory.vault, passphrase: testPassphrase, name: testName, parameters: testParameters)
        #expect(try await engine.readVault().name == testName)
        let original = try Data(contentsOf: directory.vault)
        #expect(original.range(of: Data("SYNTHETIC-SECRET".utf8)) == nil)
        let replacement = "Changed name"
        try await saveName(engine, replacement)
        let saved = try Data(contentsOf: directory.vault)
        #expect(original.prefix(160) == saved.prefix(160))
        #expect(original[160..<184] != saved[160..<184])
        await #expect(throws: VaultError.authenticationFailed) {
            try await engine.changePassphrase(current: "wrong", new: "new", parameters: testParameters)
        }
        #expect(try Data(contentsOf: directory.vault) == saved)
        try await engine.changePassphrase(current: testPassphrase, new: "new passphrase", parameters: testParameters)
        let rewrapped = try Data(contentsOf: directory.vault)
        #expect(saved[160...] == rewrapped[160...])
        #expect(saved[64..<80] != rewrapped[64..<80])
        #expect(saved[80..<104] != rewrapped[80..<104])
        await engine.lock()
        #expect(await !engine.isUnlocked)
        await #expect(throws: VaultError.locked) { try await engine.readVault().name }
        await #expect(throws: VaultError.authenticationFailed) { try await engine.open(at: directory.vault, passphrase: testPassphrase) }
        #expect(await !engine.isUnlocked)
        let next = VaultEngine()
        try await next.open(at: directory.vault, passphrase: "new passphrase")
        #expect(try await next.readVault().name == replacement)
        let backup = directory.url.appendingPathComponent("Backup.crypta")
        try original.write(to: backup)
        let oldSession = VaultEngine()
        try await oldSession.open(at: backup, passphrase: testPassphrase)
        #expect(try await oldSession.readVault().name == testName)
    }

    @Test func tamperingAndTruncation() async throws {
        let directory = try TestDirectory(); defer { directory.remove() }
        let engine = VaultEngine()
        try await engine.create(at: directory.vault, passphrase: testPassphrase, name: testName, parameters: testParameters)
        await engine.lock()
        let original = try Data(contentsOf: directory.vault)
        // Every fixed-prefix byte is checked, including reserved bytes and integer endianness.
        for offset in 0..<192 {
            var modified = original
            modified[offset] ^= 1
            try modified.write(to: directory.vault)
            await #expect(throws: (any Error).self) { try await engine.open(at: directory.vault, passphrase: testPassphrase) }
            #expect(await !engine.isUnlocked)
        }
        for offset in [192, original.count - 17, original.count - 1] {
            var modified = original; modified[offset] ^= 0x40
            try modified.write(to: directory.vault)
            await #expect(throws: VaultError.authenticationFailed) { try await engine.open(at: directory.vault, passphrase: testPassphrase) }
        }
        for length in 0..<original.count {
            #expect(throws: (any Error).self) { try VaultFormat.parse(Data(original.prefix(length))) }
        }
        var extra = original; extra.append(0)
        #expect(throws: VaultError.invalidFormat) { try VaultFormat.parse(extra) }
        var unsafe = original; unsafe.replaceSubrange(184..<192, with: Data(repeating: 255, count: 8))
        #expect(throws: VaultError.invalidFormat) { try VaultFormat.parse(unsafe) }
    }

    @Test func freshRandomnessAndConflict() async throws {
        let directory = try TestDirectory(); defer { directory.remove() }
        let first = VaultEngine(), second = VaultEngine()
        try await first.create(at: directory.vault, passphrase: testPassphrase, name: testName, parameters: testParameters)
        let old = try Data(contentsOf: directory.vault)
        try await second.open(at: directory.vault, passphrase: testPassphrase)
        try await saveName(first, "Winner")
        await #expect(throws: VaultError.conflict) { try await saveName(second, testName) }
        await #expect(throws: VaultError.conflict) { try await second.changePassphrase(current: testPassphrase, new: "new") }
        let otherURL = directory.url.appendingPathComponent("Other.crypta")
        let third = VaultEngine()
        try await third.create(at: otherURL, passphrase: testPassphrase, name: testName, parameters: testParameters)
        let other = try Data(contentsOf: otherURL)
        for range in [16..<32, 64..<80, 80..<104, 112..<160, 160..<184] { #expect(old[range] != other[range]) }
        try FileManager.default.removeItem(at: directory.vault)
        await #expect(throws: VaultError.conflict) { try await saveName(first, testName) }
    }

    @Test func cancelledCreateDoesNotWrite() async throws {
        let directory = try TestDirectory(); defer { directory.remove() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await VaultEngine().create(at: directory.vault, passphrase: testPassphrase, name: testName, parameters: testParameters)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: directory.vault.path))
    }
    @Test func validKDFMutationAndFailedRewrap() async throws {
        let directory = try TestDirectory(); defer { directory.remove() }
        let initial = VaultEngine()
        try await initial.create(at: directory.vault, passphrase: testPassphrase, name: testName, parameters: testParameters)
        await initial.lock()
        let original = try Data(contentsOf: directory.vault)
        for (offset, value): (Int, UInt8) in [(52, 4), (57, 4)] {
            var changed = original
            changed[offset] = value // t=4 or m=66560 KiB; both pass resource-policy checks.
            _ = try VaultFormat.parse(changed)
            try changed.write(to: directory.vault)
            await #expect(throws: VaultError.authenticationFailed) { try await initial.open(at: directory.vault, passphrase: testPassphrase) }
        }
        try original.write(to: directory.vault)
        let failing = VaultEngine(store: .init(checkpoint: { if $0 == .beforeRename { throw VaultError.fileAccess } }))
        try await failing.open(at: directory.vault, passphrase: testPassphrase)
        await #expect(throws: VaultError.fileAccess) {
            try await failing.changePassphrase(current: testPassphrase, new: "not committed", parameters: testParameters)
        }
        #expect(try Data(contentsOf: directory.vault) == original)
        #expect(try await failing.readVault().name == testName)
        try await initial.open(at: directory.vault, passphrase: testPassphrase)
    }

}
