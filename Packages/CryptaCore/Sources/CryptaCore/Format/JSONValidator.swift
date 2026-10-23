import Foundation

/// Structural validation with optional schema-aware bounds before typed decoding.
/// Bounds nesting/collections while scanning, before Foundation constructs a model.
enum JSONValidator {
    static func validate(_ data: Data, payloadSchema: Bool = false) throws {
        guard !data.isEmpty, data.count <= VaultFormat.maxPayloadBytes else { throw VaultError.resourceLimit }
        guard String(data: data, encoding: .utf8) != nil else { throw VaultError.invalidPayload }
        var scanner = Scanner(bytes: Array(data), payloadSchema: payloadSchema)
        scanner.whitespace()
        guard scanner.peek == 123 else { throw VaultError.invalidPayload }
        try scanner.value(depth: 0, path: [])
        scanner.whitespace()
        guard scanner.index == scanner.bytes.count else { throw VaultError.invalidPayload }
    }

    private struct Scanner {
        let bytes: [UInt8]
        let payloadSchema: Bool
        var index = 0
        var peek: UInt8? { index < bytes.count ? bytes[index] : nil }
        mutating func whitespace() {
            while let byte = peek, [9, 10, 13, 32].contains(byte) { index += 1 }
        }
        mutating func expect(_ byte: UInt8) throws {
            guard peek == byte else { throw VaultError.invalidPayload }
            index += 1
        }
        mutating func value(depth: Int, path: [String]) throws {
            whitespace()
            guard let byte = peek else { throw VaultError.invalidPayload }
            switch byte {
            case 123: try object(depth: depth + 1, path: path)
            case 91: try array(depth: depth + 1, path: path)
            case 34: _ = try string(limit: stringLimit(path))
            case 116: try literal("true")
            case 102: try literal("false")
            case 110: try literal("null")
            case 45, 48...57: try number(integerOnly: payloadSchema)
            default: throw VaultError.invalidPayload
            }
        }
        mutating func object(depth: Int, path: [String]) throws {
            guard depth <= 16 else { throw VaultError.resourceLimit }
            try expect(123)
            whitespace()
            if peek == 125 { index += 1; return }
            var keys = Set<Data>()
            repeat {
                guard keys.count < 10_000 else { throw VaultError.resourceLimit }
                whitespace()
                let key = try string(limit: payloadSchema ? 4096 : 1_048_576)
                guard keys.insert(Data(key.utf8)).inserted else { throw VaultError.invalidPayload }
                whitespace()
                try expect(58)
                try value(depth: depth, path: path + [key])
                whitespace()
                if peek == 125 { index += 1; return }
                try expect(44)
            } while true
        }
        mutating func array(depth: Int, path: [String]) throws {
            guard depth <= 16 else { throw VaultError.resourceLimit }
            try expect(91)
            whitespace()
            if peek == 93 { index += 1; return }
            var count = 0
            repeat {
                guard count < arrayLimit(path) else { throw VaultError.resourceLimit }
                try value(depth: depth, path: path + ["*"])
                count += 1
                whitespace()
                if peek == 93 { index += 1; return }
                try expect(44)
            } while true
        }
        mutating func string(limit: Int) throws -> String {
            let start = index
            try expect(34)
            while let byte = peek {
                guard index - start <= 6 * limit + 2 else { throw VaultError.resourceLimit }
                index += 1
                if byte == 34 {
                    let encoded = Data(bytes[start..<index])
                    guard let decoded = try? JSONSerialization.jsonObject(with: encoded, options: .fragmentsAllowed) as? String else {
                        throw VaultError.invalidPayload
                    }
                    guard decoded.utf8.count <= limit else { throw VaultError.resourceLimit }
                    return decoded
                }
                guard byte >= 32 else { throw VaultError.invalidPayload }
                if byte == 92 {
                    guard let escape = peek else { throw VaultError.invalidPayload }
                    index += 1
                    if escape == 117 {
                        for _ in 0..<4 {
                            guard let digit = peek, (48...57).contains(digit) || (65...70).contains(digit) || (97...102).contains(digit) else {
                                throw VaultError.invalidPayload
                            }
                            index += 1
                        }
                    } else if ![34, 92, 47, 98, 102, 110, 114, 116].contains(escape) {
                        throw VaultError.invalidPayload
                    }
                }
            }
            throw VaultError.invalidPayload
        }
        mutating func literal(_ text: String) throws {
            for byte in text.utf8 { try expect(byte) }
        }
        mutating func digits() throws {
            let start = index
            while let byte = peek, (48...57).contains(byte) { index += 1 }
            guard index > start else { throw VaultError.invalidPayload }
        }
        private func arrayLimit(_ path: [String]) -> Int {
            guard payloadSchema else { return 10_000 }
            if path == ["entries", "*", "tags"] { return VaultTags.maximumCount }
            if path == ["entries", "*", "fields", "customFields"] { return 100 }
            return 10_000
        }
        private func stringLimit(_ path: [String]) -> Int {
            guard payloadSchema else { return 1_048_576 }
            if path.count == 4, Array(path.prefix(3)) == ["entries", "*", "fields"],
               let field = path.last, ["password", "token", "content", "notes"].contains(field) { return 1_048_576 }
            if path == ["entries", "*", "fields", "customFields", "*", "value"] { return 1_048_576 }
            return 4096
        }
        mutating func number(integerOnly: Bool) throws {
            let start = index
            if peek == 45 { index += 1 }
            if peek == 48 { index += 1 } else { try digits() }
            if peek == 46 {
                guard !integerOnly else { throw VaultError.invalidPayload }
                index += 1; try digits()
            }
            if peek == 101 || peek == 69 {
                guard !integerOnly else { throw VaultError.invalidPayload }
                index += 1
                if peek == 43 || peek == 45 { index += 1 }
                try digits()
            }
            guard index - start <= 128,
                  let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)), value.isFinite else {
                throw VaultError.invalidPayload
            }
        }
    }
}
