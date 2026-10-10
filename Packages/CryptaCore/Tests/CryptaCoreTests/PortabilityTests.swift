import Foundation
import Testing
@testable import CryptaCore

@Suite(.serialized)
struct PortabilityTests {
    private func driver() throws -> URL {
        // SwiftPM builds executable targets beside the .xctest bundle.
        let bundle = Bundle.allBundles.first { $0.bundleURL.pathExtension == "xctest" }?.bundleURL ?? Bundle.module.bundleURL
        let directory = bundle.deletingLastPathComponent()
        let executable = directory.appendingPathComponent("CryptaTestDriver")
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
        return executable
    }
    @Test func independentFixtureAndFreshProcess() async throws {
        let directory = try TestDirectory(); defer { directory.remove() }
        let reference = try fixture("reference-v1.crypta")
        try reference.write(to: directory.vault)
        let engine = VaultEngine()
        try await engine.open(at: directory.vault, passphrase: testPassphrase)
        let decoded = try await engine.readVault()
        #expect(decoded == (try VaultCodec.decode(fixture("reference-payload.json"), expectedID: decoded.vaultID)))
        #expect(try Data(contentsOf: directory.vault) == reference)
        await engine.lock()
        let process = Process(), output = Pipe()
        process.executableURL = try driver()
        process.arguments = ["open", directory.vault.path]
        process.standardOutput = output; process.standardError = output
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(output.fileHandleForReading.readDataToEndOfFile().isEmpty)
    }

    @Test func separateProcessesCannotOverwrite() async throws {
        let directory = try TestDirectory(); defer { directory.remove() }
        let engine = VaultEngine()
        try await engine.create(at: directory.vault, passphrase: testPassphrase, name: testName, parameters: testParameters)
        let process = Process(), output = Pipe(), input = Pipe()
        process.executableURL = try driver()
        process.arguments = ["stale-writer", directory.vault.path]
        process.standardOutput = output; process.standardInput = input
        try process.run()
        defer { try? input.fileHandleForWriting.close(); if process.isRunning { process.terminate() }; process.waitUntilExit() }
        #expect(output.fileHandleForReading.readData(ofLength: 6) == Data("ready\n".utf8))
        let newer = "New revision"
        try await saveName(engine, newer)
        input.fileHandleForWriting.write(Data([1]))
        process.waitUntilExit()
        #expect(process.terminationStatus == 3)
        await engine.lock()
        try await engine.open(at: directory.vault, passphrase: testPassphrase)
        #expect(try await engine.readVault().name == newer)
    }
    #if DEBUG
    @Test func processDeathLeavesOnlyAuthenticatedContainers() async throws {
        let directory = try TestDirectory(); defer { directory.remove() }
        let creator = VaultEngine()
        try await creator.create(at: directory.vault, passphrase: testPassphrase, name: testName, parameters: testParameters)
        await creator.lock()
        let original = try Data(contentsOf: directory.vault)
        for mode in ["crash-before-rename", "crash-after-rename"] {
            let process = Process()
            process.executableURL = try driver()
            process.arguments = [mode, directory.vault.path]
            try process.run(); process.waitUntilExit()
            #expect(process.terminationStatus == 77)
            let recovered = VaultEngine()
            try await recovered.open(at: directory.vault, passphrase: testPassphrase)
            let newPayload = "New recovered name"
            #expect(try await recovered.readVault().name == (mode == "crash-before-rename" ? testName : newPayload))
            if mode == "crash-before-rename" {
                #expect(try Data(contentsOf: directory.vault) == original)
                let stages = try FileManager.default.contentsOfDirectory(at: directory.url, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent.hasSuffix(".crypta-stage") }
                let stage = try #require(stages.first)
                let stagedSession = VaultEngine()
                try await stagedSession.open(at: stage, passphrase: testPassphrase)
                #expect(try await stagedSession.readVault().name == newPayload)
                try FileManager.default.removeItem(at: stage)
            }
        }
    }

    #endif
}
