import Foundation
import Testing
@testable import CryptaCore

@Suite(.serialized)
struct CryptoTests {
    @Test func upstreamKnownAnswers() throws {
        struct Vectors: Decodable {
            struct Argon: Decodable { let password, salt, expected: String; let passes: UInt32; let memoryBytes, outputBytes: Int }
            struct AEAD: Decodable { let key, nonce, aad, message, expected: String }
            let argon2id: Argon
            let xchacha: AEAD
        }
        let vectors = try JSONDecoder().decode(Vectors.self, from: fixture("upstream-vectors.json"))
        let a = vectors.argon2id
        let password = try hex(a.password)
        let input = try SecretBuffer(password)
        let key = try Crypto.deriveRaw(input, length: password.count, salt: hex(a.salt), passes: a.passes,
                                       memoryBytes: a.memoryBytes, outputBytes: a.outputBytes)
        #expect(key.copyData() == (try hex(a.expected)))
        let x = vectors.xchacha
        let cipherKey = try SecretBuffer(hex(x.key))
        let sealed = try Crypto.seal(Data(x.message.utf8), key: cipherKey, nonce: hex(x.nonce), aad: hex(x.aad))
        #expect(sealed == (try hex(x.expected)))
        let (plain, length) = try Crypto.open(sealed, key: cipherKey, nonce: hex(x.nonce), aad: hex(x.aad))
        #expect(plain.copyData(count: length) == Data(x.message.utf8))
        #expect(throws: VaultError.authenticationFailed) {
            try Crypto.open(sealed, key: cipherKey, nonce: hex(x.nonce), aad: Data("wrong domain".utf8))
        }
    }

    @Test func derivationAndBytePolicy() throws {
        let salt = Data(repeating: 7, count: 16)
        let first = try Crypto.derive("a\0é 🗝️ ", salt: salt, parameters: testParameters)
        let same = try Crypto.derive("a\0é 🗝️ ", salt: salt, parameters: testParameters)
        #expect(Crypto.equal(first, same))
        let differentSalt = try Crypto.derive("a\0é 🗝️ ", salt: Data(repeating: 8, count: 16), parameters: testParameters)
        let differentInput = try Crypto.derive("a", salt: salt, parameters: testParameters)
        #expect(!Crypto.equal(first, differentSalt))
        #expect(!Crypto.equal(first, differentInput))
        #expect(!VaultEngine.passphrasesMatch("é", "e\u{301}"))
        #expect(VaultEngine.passphrasesMatch("hello 🗝️ ", "hello 🗝️ "))
        let nfc = try Crypto.derive("é", salt: salt, parameters: testParameters)
        let nfd = try Crypto.derive("e\u{301}", salt: salt, parameters: testParameters)
        #expect(!Crypto.equal(nfc, nfd))
        _ = try Crypto.derive(String(repeating: "abc 🗝️", count: 3000), salt: salt, parameters: testParameters)
        #expect(throws: VaultError.invalidPassphrase) { try Crypto.derive("", salt: salt, parameters: testParameters, creating: true) }
        #expect(throws: VaultError.resourceLimit) { try Crypto.passphrase(String(repeating: "x", count: 1_048_577), creating: false) }
        #expect(throws: VaultError.resourceLimit) { try Crypto.derive("x", salt: salt, parameters: .init(passes: 1, memoryKiB: 8)) }
        first.wipe()
        #expect(first.copyData() == Data(count: 32))
    }

    @Test func nativeFailureAndBufferLifetime() throws {
        let password = try SecretBuffer(Data("public".utf8))
        // Invalid native memory cost exercises the error/cleanup path without exhausting this machine.
        #expect(throws: VaultError.allocationFailed) {
            try Crypto.deriveRaw(password, length: 6, salt: Data(count: 16), passes: 3, memoryBytes: 1)
        }
        weak var released: SecretBuffer?
        do { let owned = try Crypto.randomKey(); released = owned; #expect(released != nil) }
        #expect(released == nil)
        #expect(VaultEngine.cryptoVersion == "1.0.22")
    }
}
