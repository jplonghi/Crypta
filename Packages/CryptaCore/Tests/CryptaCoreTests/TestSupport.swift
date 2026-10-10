import Foundation
import Testing
@testable import CryptaCore

let testParameters = KDFParameters(passes: 3, memoryKiB: 65_536)
let testPassphrase = "public fixture passphrase 🗝️ with spaces"
let testName = "SYNTHETIC-SECRET-4ea9d5"

struct TestDirectory {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("crypta-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }
    var vault: URL { url.appendingPathComponent("Test.crypta") }
    func remove() { try? FileManager.default.removeItem(at: url) }
}

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func hex(_ string: String) throws -> Data {
    let chars = Array(string.utf8)
    #expect(chars.count % 2 == 0)
    var data = Data()
    for index in stride(from: 0, to: chars.count, by: 2) {
        let byte = try #require(UInt8(String(decoding: chars[index..<index+2], as: UTF8.self), radix: 16))
        data.append(byte)
    }
    return data
}

@discardableResult
func saveName(_ engine: VaultEngine, _ name: String) async throws -> Vault {
    var vault = try await engine.readVault()
    vault.name = name
    return try await engine.save(vault: vault)
}
