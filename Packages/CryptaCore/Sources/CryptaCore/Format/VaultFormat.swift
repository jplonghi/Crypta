import Foundation

enum VaultFormat {
    static let maxPayloadBytes = 16 * 1024 * 1024
    static let maxFileBytes = 192 + maxPayloadBytes + 16
    static let magic = Data([0x43, 0x52, 0x59, 0x50, 0x54, 0x41, 0x0d, 0x0a])
    static let wrapLabel = Data("Crypta/v1/key-wrap\0".utf8)
    static let payloadLabel = Data("Crypta/v1/payload\0".utf8)

    struct Container {
        let bytes: Data
        let parameters: KDFParameters
        var core: Data { bytes.subdata(in: 0..<48) }
        var salt: Data { bytes.subdata(in: 64..<80) }
        var wrapNonce: Data { bytes.subdata(in: 80..<104) }
        var wrappedKey: Data { bytes.subdata(in: 112..<160) }
        var payloadNonce: Data { bytes.subdata(in: 160..<184) }
        var ciphertext: Data { bytes.subdata(in: 192..<bytes.count) }
        var wrapAAD: Data { wrapLabel + bytes.subdata(in: 0..<112) }
        var payloadAAD: Data { payloadLabel + core + bytes.subdata(in: 160..<192) }
    }

    static func parse(_ input: Data) throws -> Container {
        guard (208...maxFileBytes).contains(input.count) else { throw VaultError.invalidFormat }
        let bytes = Data(input) // rebase potentially sliced Data before integer indexing
        guard bytes.prefix(8) == magic else { throw VaultError.invalidFormat }
        guard integer(bytes, 8, 2) == 1, integer(bytes, 10, 2) == 48,
              integer(bytes, 32, 2) == 1, integer(bytes, 34, 2) == 1,
              integer(bytes, 48, 2) == 1, integer(bytes, 50, 2) == 1 else { throw VaultError.unsupportedFormat }
        guard bytes[12..<16].allSatisfy({ $0 == 0 }), bytes[36..<48].allSatisfy({ $0 == 0 }),
              bytes[104..<112].allSatisfy({ $0 == 0 }) else { throw VaultError.unsupportedFormat }
        guard integer(bytes, 60, 4) == 1 else { throw VaultError.resourceLimit }
        let parameters = KDFParameters(passes: UInt32(integer(bytes, 52, 4)), memoryKiB: UInt32(integer(bytes, 56, 4)))
        try parameters.validate()
        let length = integer(bytes, 184, 8)
        guard length >= 16, length <= UInt64(maxPayloadBytes + 16), length == UInt64(bytes.count - 192) else {
            throw VaultError.invalidFormat
        }
        return Container(bytes: bytes, parameters: parameters)
    }

    static func core() throws -> Data {
        var bytes = magic
        append(1, size: 2, to: &bytes)
        append(48, size: 2, to: &bytes)
        append(0, size: 4, to: &bytes)
        bytes += try Crypto.random(16)
        append(1, size: 2, to: &bytes)
        append(1, size: 2, to: &bytes)
        bytes += Data(count: 12)
        return bytes
    }

    static func slot(parameters: KDFParameters) throws -> Data {
        try parameters.validate()
        var bytes = Data()
        append(1, size: 2, to: &bytes)
        append(1, size: 2, to: &bytes)
        append(UInt64(parameters.passes), size: 4, to: &bytes)
        append(UInt64(parameters.memoryKiB), size: 4, to: &bytes)
        append(1, size: 4, to: &bytes)
        bytes += try Crypto.random(16)
        bytes += try Crypto.random(24)
        bytes += Data(count: 8)
        return bytes
    }

    static func payload(_ plaintext: Data, core: Data, key: SecretBuffer) throws -> Data {
        try JSONValidator.validate(plaintext)
        let nonce = try Crypto.random(24)
        var descriptor = nonce
        append(UInt64(plaintext.count + 16), size: 8, to: &descriptor)
        return descriptor + (try Crypto.seal(plaintext, key: key, nonce: nonce, aad: payloadLabel + core + descriptor))
    }

    private static func integer(_ bytes: Data, _ offset: Int, _ size: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<size { value |= UInt64(bytes[offset + index]) << (index * 8) }
        return value
    }

    static func append(_ value: UInt64, size: Int, to bytes: inout Data) {
        for index in 0..<size { bytes.append(UInt8(truncatingIfNeeded: value >> (index * 8))) }
    }
}
