import Foundation

/// Opaque 128-bit vault identity; independent of account, computer or UUID representation.
public struct VaultID: Codable, Hashable, Sendable {
    public let hex: String
    public init(hex: String) throws {
        guard hex.utf8.count == 32, hex.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw VaultError.invalidPayload
        }
        self.hex = hex
    }
    init(bytes: Data) throws {
        guard bytes.count == 16 else { throw VaultError.invalidFormat }
        try self.init(hex: bytes.map { String(format: "%02x", $0) }.joined())
    }
    public init(from decoder: Decoder) throws { try self.init(hex: decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(hex)
    }
}

public struct VaultEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public let createdAt: Int64
    public var modifiedAt: Int64
    public var tags: [String]
    public var isFavorite: Bool
    public var fields: EntryFields
    public var type: String { fields.type }

    /// Dates are UTC Unix milliseconds. The engine validates every model before committing it.
    public init(id: UUID = UUID(), title: String, createdAt: Int64, modifiedAt: Int64? = nil,
                tags: [String] = [], isFavorite: Bool = false, fields: EntryFields) {
        self.id = id; self.title = title; self.createdAt = createdAt; self.modifiedAt = modifiedAt ?? createdAt
        self.tags = tags; self.isFavorite = isFavorite; self.fields = fields
    }
    public init(from decoder: Decoder) throws {
        let f = try strictFields(decoder, "id", "type", "typeVersion", "title", "createdAt", "modifiedAt", "tags", "isFavorite", "fields")
        try self.init(fields: f, isFavorite: f.value("isFavorite"))
    }
    init(fields f: Fields, isFavorite: Bool) throws {
        guard try f.value("typeVersion", as: Int.self) == 1 else { throw VaultError.unsupportedPayload }
        id = try f.uuid("id"); title = try f.value("title"); createdAt = try f.value("createdAt")
        modifiedAt = try f.value("modifiedAt"); tags = try f.value("tags"); self.isFavorite = isFavorite
        switch try f.value("type", as: String.self) {
        case "credential": fields = .credential(try f.value("fields"))
        case "apiToken": fields = .apiToken(try f.value("fields"))
        case "secureNote": fields = .secureNote(try f.value("fields"))
        case "customSecret": fields = .customSecret(try f.value("fields"))
        default: throw VaultError.unsupportedPayload
        }
    }
    public func encode(to encoder: Encoder) throws {
        var f = encoder.container(keyedBy: FieldKey.self)
        try f.putUUID("id", id); try f.put("type", type); try f.put("typeVersion", 1); try f.put("title", title)
        try f.put("createdAt", createdAt); try f.put("modifiedAt", modifiedAt); try f.put("tags", tags)
        try f.put("isFavorite", isFavorite)
        switch fields {
        case .credential(let value): try f.put("fields", value)
        case .apiToken(let value): try f.put("fields", value)
        case .secureNote(let value): try f.put("fields", value)
        case .customSecret(let value): try f.put("fields", value)
        }
    }
}

/// Value snapshot. The engine owns revisions; save returns the newly committed snapshot.
/// Callers must discard their copies when the vault locks.
public struct Vault: Codable, Equatable, Sendable {
    public let vaultID: VaultID
    public var name: String
    public let createdAt: Int64
    public private(set) var modifiedAt: Int64
    public private(set) var revision: UInt64
    public var entries: [VaultEntry]

    init(vaultID: VaultID, name: String, createdAt: Int64) {
        self.vaultID = vaultID; self.name = name; self.createdAt = createdAt
        modifiedAt = createdAt; revision = 0; entries = []
    }
    mutating func advance(modifiedAt: Int64) throws {
        guard revision < VaultValidation.maxRevision else { throw VaultError.resourceLimit }
        self.modifiedAt = modifiedAt; revision += 1
    }
    public init(from decoder: Decoder) throws {
        let version = try decoder.container(keyedBy: FieldKey.self).value("schemaVersion", as: Int.self)
        let f: Fields
        switch version {
        case 1: f = try strictFields(decoder, "schemaVersion", "vaultID", "name", "createdAt", "modifiedAt", "revision", "categories", "entries")
        case 2: f = try strictFields(decoder, "schemaVersion", "vaultID", "name", "createdAt", "modifiedAt", "revision", "entries")
        default: throw VaultError.unsupportedPayload
        }
        vaultID = try f.value("vaultID"); name = try f.value("name"); createdAt = try f.value("createdAt")
        modifiedAt = try f.value("modifiedAt"); revision = try f.value("revision")
        if version == 1 {
            let legacy: [LegacyEntry] = try f.value("entries")
            let categories: [LegacyCategory] = try f.value("categories")
            guard categories.count <= 1000 else { throw VaultError.resourceLimit }
            var names: [UUID: String] = [:]
            for category in categories {
                guard names[category.id] == nil else { throw VaultError.invalidPayload }
                guard category.name.utf8.count <= 4096 else { throw VaultError.resourceLimit }
                names[category.id] = category.name
            }
            entries = legacy.map(\.entry)
            // Validate before expansion so large legacy categories remain readable even above the new save-size limit.
            try VaultValidation.validate(self, expectedID: vaultID, legacy: true)
            for index in entries.indices {
                if let id = legacy[index].categoryID {
                    guard let name = names[id] else { throw VaultError.invalidPayload }
                    entries[index].tags.append(name)
                }
                entries[index].tags = VaultTags.unique(entries[index].tags)
            }
        } else {
            entries = try f.value("entries")
            try VaultValidation.validate(self, expectedID: vaultID)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var f = encoder.container(keyedBy: FieldKey.self)
        try f.put("schemaVersion", 2); try f.put("vaultID", vaultID); try f.put("name", name)
        try f.put("createdAt", createdAt); try f.put("modifiedAt", modifiedAt); try f.put("revision", revision)
        try f.put("entries", entries)
    }
}

// Read-only schema-1 adapters. Categories never enter the current model or encoded payload.
private struct LegacyCategory: Decodable {
    let id: UUID
    let name: String
    init(from decoder: Decoder) throws {
        let f = try strictFields(decoder, "id", "name")
        id = try f.uuid("id"); name = try f.value("name")
    }
}

private struct LegacyEntry: Decodable {
    let entry: VaultEntry
    let categoryID: UUID?
    init(from decoder: Decoder) throws {
        let f = try strictFields(decoder, "id", "type", "typeVersion", "title", "createdAt", "modifiedAt", "tags", "categoryID", "fields")
        entry = try VaultEntry(fields: f, isFavorite: false)
        categoryID = try f.optionalUUID("categoryID")
    }
}
