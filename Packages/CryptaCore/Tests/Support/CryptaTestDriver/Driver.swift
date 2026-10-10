// Test harness only. Fixed PUBLIC fixture credentials; not a user-facing vault CLI.
import Foundation
#if DEBUG
@testable import CryptaCore
#else
import CryptaCore
#endif
import Darwin

@main struct Driver {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count == 3 else { exit(2) }
        let url = URL(fileURLWithPath: args[2])
        let passphrase = "public fixture passphrase 🗝️ with spaces"
        let name = "SYNTHETIC-SECRET-4ea9d5"
        let engine = VaultEngine()
        do {
            switch args[1] {
            case "create":
                try await engine.create(at: url, passphrase: passphrase, name: name,
                                        parameters: .init(passes: 3, memoryKiB: 65_536))
            case "open":
                try await engine.open(at: url, passphrase: passphrase)
                _ = try await engine.readVault()
            case "stale-writer":
                try await engine.open(at: url, passphrase: passphrase)
                FileHandle.standardOutput.write(Data("ready\n".utf8))
                _ = FileHandle.standardInput.readData(ofLength: 1)
                var edited = try await engine.readVault()
                edited.name = name
                try await engine.save(vault: edited)
            #if DEBUG
            case "crash-before-rename", "crash-after-rename":
                let crashAfterRename = args[1] == "crash-after-rename"
                let crashing = VaultEngine(store: .init(checkpoint: {
                    if $0 == (crashAfterRename ? .renamed : .beforeRename) { _exit(77) }
                }))
                try await crashing.open(at: url, passphrase: passphrase)
                var edited = try await crashing.readVault()
                edited.name = "New recovered name"
                try await crashing.save(vault: edited)
#endif
            case "benchmark":
                let start = ContinuousClock.now
                try await engine.create(at: url, passphrase: passphrase, name: name)
                let created = start.duration(to: .now)
                await engine.lock()
                let unlockStart = ContinuousClock.now
                try await engine.open(at: url, passphrase: passphrase)
                print("Default-profile create: \(created); unlock: \(unlockStart.duration(to: .now)); native: \(VaultEngine.cryptoVersion)")
            default: exit(2)
            }
            await engine.lock()
        } catch VaultError.conflict { exit(3) }
        catch let error as VaultError {
            FileHandle.standardError.write(Data("Test driver error: \(error)\n".utf8))
            exit(4)
        } catch { exit(4) }
    }
}
