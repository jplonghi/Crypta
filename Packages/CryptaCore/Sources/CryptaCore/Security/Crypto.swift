import Foundation
import Clibsodium

/// A single owner; never Sendable and never exposed outside the session's executor.
final class SecretBuffer {
    let count: Int
    let pointer: UnsafeMutableRawPointer
    let isMemoryLocked: Bool

    init(count: Int) throws {
        guard count > 0, count <= VaultFormat.maxPayloadBytes, Crypto.initialized else {
            throw VaultError.allocationFailed
        }
        guard let allocation = sodium_malloc(count) else { throw VaultError.allocationFailed }
        self.count = count
        pointer = allocation
        isMemoryLocked = sodium_mlock(allocation, count) == 0
    }

    convenience init(_ bytes: Data) throws {
        try self.init(count: max(1, bytes.count))
        bytes.withUnsafeBytes { source in
            if let base = source.baseAddress { pointer.copyMemory(from: base, byteCount: bytes.count) }
        }
    }

    var bytes: UnsafeMutablePointer<UInt8> { pointer.assumingMemoryBound(to: UInt8.self) }
    func copyData(count length: Int? = nil) -> Data { Data(bytes: pointer, count: length ?? count) }
    func wipe() { sodium_memzero(pointer, count) }
    deinit { sodium_free(pointer) } // libsodium clears before freeing, including if mlock failed.
}

public struct KDFParameters: Equatable, Sendable {
    public let passes: UInt32
    public let memoryKiB: UInt32
    public static let standard = KDFParameters(passes: 3, memoryKiB: 262_144)

    public init(passes: UInt32, memoryKiB: UInt32) {
        self.passes = passes
        self.memoryKiB = memoryKiB
    }

    func validate() throws {
        guard (3...6).contains(passes), (65_536...524_288).contains(memoryKiB), memoryKiB % 1024 == 0 else {
            throw VaultError.resourceLimit
        }
    }
}

// Force-unwrapped C buffer bases below are justified by validated nonzero salt/nonce/ciphertext
// lengths and freshly allocated nonempty output Data. Empty message/AAD bases remain optional.
enum Crypto {
    static let initialized = sodium_init() >= 0
    // Serializes native memory-hard work across ALL session actors, not just a single vault.
    private static let derivationLock = NSLock()
    static var version: String { String(cString: sodium_version_string()) }
    static let maxPassphraseBytes = 1_048_576

    static func passphrase(_ string: String, creating: Bool) throws -> SecretBuffer {
        let size = string.utf8.count
        guard size <= maxPassphraseBytes else { throw VaultError.resourceLimit }
        guard !creating || size > 0 else { throw VaultError.invalidPassphrase }
        // Swift/UI may retain other string copies; only this owned UTF-8 buffer can be wiped.
        let result = try SecretBuffer(count: max(1, size))
        for (index, byte) in string.utf8.enumerated() { result.bytes[index] = byte }
        return result
    }

    static func random(_ count: Int) throws -> Data {
        guard initialized, count > 0, count <= VaultFormat.maxPayloadBytes else { throw VaultError.cryptoUnavailable }
        var data = Data(count: count)
        data.withUnsafeMutableBytes { buffer in
            if let address = buffer.baseAddress { randombytes_buf(address, count) }
        }
        return data
    }

    static func randomKey() throws -> SecretBuffer {
        let key = try SecretBuffer(count: 32)
        randombytes_buf(key.pointer, key.count)
        return key
    }

    static func derive(_ passphrase: String, salt: Data, parameters: KDFParameters, creating: Bool = false) throws -> SecretBuffer {
        try parameters.validate()
        let input = try self.passphrase(passphrase, creating: creating)
        defer { input.wipe() }
        return try deriveRaw(input, length: passphrase.utf8.count, salt: salt, passes: parameters.passes,
                             memoryBytes: Int(parameters.memoryKiB) * 1024)
    }

    // Internal entry point also permits upstream known-answer vectors; public APIs always validate policy.
    static func deriveRaw(_ input: SecretBuffer, length: Int, salt: Data, passes: UInt32, memoryBytes: Int, outputBytes: Int = 32) throws -> SecretBuffer {
        guard initialized, salt.count == 16, length >= 0, length <= input.count else { throw VaultError.invalidFormat }
        guard (16...1024).contains(outputBytes) else { throw VaultError.resourceLimit }
        let key = try SecretBuffer(count: outputBytes)
        derivationLock.lock()
        defer { derivationLock.unlock() }
        let code = salt.withUnsafeBytes { saltBytes in
            crypto_pwhash(key.bytes, UInt64(outputBytes), input.pointer.assumingMemoryBound(to: CChar.self), UInt64(length),
                          saltBytes.bindMemory(to: UInt8.self).baseAddress!, UInt64(passes), memoryBytes,
                          crypto_pwhash_ALG_ARGON2ID13)
        }
        guard code == 0 else { throw VaultError.allocationFailed }
        return key
    }

    static func seal(_ plaintext: Data, key: SecretBuffer, nonce: Data, aad: Data) throws -> Data {
        guard initialized, key.count == 32, nonce.count == 24, plaintext.count <= VaultFormat.maxPayloadBytes else {
            throw VaultError.resourceLimit
        }
        var result = Data(count: plaintext.count + 16)
        var length: UInt64 = 0
        let code = result.withUnsafeMutableBytes { output in
            plaintext.withUnsafeBytes { input in
                aad.withUnsafeBytes { associated in
                    nonce.withUnsafeBytes { iv in
                        crypto_aead_xchacha20poly1305_ietf_encrypt(output.bindMemory(to: UInt8.self).baseAddress!,
                            &length, input.bindMemory(to: UInt8.self).baseAddress, UInt64(plaintext.count),
                            associated.bindMemory(to: UInt8.self).baseAddress, UInt64(aad.count), nil,
                            iv.bindMemory(to: UInt8.self).baseAddress!, key.bytes)
                    }
                }
            }
        }
        guard code == 0, length == result.count else { throw VaultError.cryptoUnavailable }
        return result
    }

    static func sealKey(_ plaintext: SecretBuffer, key: SecretBuffer, nonce: Data, aad: Data) throws -> Data {
        guard initialized, key.count == 32, plaintext.count == 32, nonce.count == 24 else {
            throw VaultError.invalidFormat
        }
        var result = Data(count: 48)
        var length: UInt64 = 0
        let code = result.withUnsafeMutableBytes { output in
            aad.withUnsafeBytes { associated in
                nonce.withUnsafeBytes { iv in
                    crypto_aead_xchacha20poly1305_ietf_encrypt(output.bindMemory(to: UInt8.self).baseAddress!,
                        &length, plaintext.bytes, 32, associated.bindMemory(to: UInt8.self).baseAddress,
                        UInt64(aad.count), nil, iv.bindMemory(to: UInt8.self).baseAddress!, key.bytes)
                }
            }
        }
        guard code == 0, length == 48 else { throw VaultError.cryptoUnavailable }
        return result
    }

    static func open(_ ciphertext: Data, key: SecretBuffer, nonce: Data, aad: Data) throws -> (SecretBuffer, Int) {
        guard initialized, key.count == 32, nonce.count == 24, ciphertext.count >= 16,
              ciphertext.count <= VaultFormat.maxPayloadBytes + 16 else { throw VaultError.invalidFormat }
        let result = try SecretBuffer(count: max(1, ciphertext.count - 16))
        var length: UInt64 = 0
        let code = ciphertext.withUnsafeBytes { input in
            aad.withUnsafeBytes { associated in
                nonce.withUnsafeBytes { iv in
                    crypto_aead_xchacha20poly1305_ietf_decrypt(result.bytes, &length, nil,
                        input.bindMemory(to: UInt8.self).baseAddress!, UInt64(ciphertext.count),
                        associated.bindMemory(to: UInt8.self).baseAddress, UInt64(aad.count),
                        iv.bindMemory(to: UInt8.self).baseAddress!, key.bytes)
                }
            }
        }
        guard code == 0, length == ciphertext.count - 16 else {
            result.wipe()
            throw VaultError.authenticationFailed
        }
        return (result, Int(length))
    }

    static func equal(_ lhs: SecretBuffer, _ rhs: SecretBuffer) -> Bool {
        lhs.count == rhs.count && sodium_memcmp(lhs.pointer, rhs.pointer, lhs.count) == 0
    }

    static func fingerprint(_ data: Data) -> Data {
        var hash = Data(count: 32)
        hash.withUnsafeMutableBytes { output in
            data.withUnsafeBytes { input in
                _ = crypto_hash_sha256(output.bindMemory(to: UInt8.self).baseAddress!,
                    input.bindMemory(to: UInt8.self).baseAddress, UInt64(data.count))
            }
        }
        return hash
    }
}
