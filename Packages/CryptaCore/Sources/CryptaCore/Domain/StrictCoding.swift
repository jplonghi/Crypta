import Foundation

/// Dynamic keys are necessary: an enum CodingKey container hides unknown fields.
struct FieldKey: CodingKey, Hashable {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}

typealias Fields = KeyedDecodingContainer<FieldKey>

func strictFields(_ decoder: Decoder, _ names: String...) throws -> Fields {
    let fields = try decoder.container(keyedBy: FieldKey.self)
    let actual = Set(fields.allKeys.map(\.stringValue))
    let expected = Set(names)
    guard actual.isSubset(of: expected) else { throw VaultError.unsupportedPayload }
    guard actual == expected else { throw VaultError.invalidPayload }
    return fields
}

extension KeyedDecodingContainer where Key == FieldKey {
    func value<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        try decode(type, forKey: FieldKey(name))
    }
    func optional<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T? {
        try decodeIfPresent(type, forKey: FieldKey(name))
    }
    func uuid(_ name: String) throws -> UUID {
        let text: String = try value(name)
        guard let id = UUID(uuidString: text), text.utf8.elementsEqual(id.uuidString.lowercased().utf8) else {
            throw VaultError.invalidPayload
        }
        return id
    }
}

extension KeyedEncodingContainer where Key == FieldKey {
    mutating func put<T: Encodable>(_ name: String, _ value: T) throws {
        try encode(value, forKey: FieldKey(name))
    }
    // Nullable fields require explicit null, not an omitted key.
    mutating func putOptional<T: Encodable>(_ name: String, _ value: T?) throws {
        if let value { try put(name, value) } else { try encodeNil(forKey: FieldKey(name)) }
    }
    mutating func putUUID(_ name: String, _ value: UUID) throws { try put(name, value.uuidString.lowercased()) }
}
