import Foundation

public struct Credential: Codable, Equatable, Sendable {
    public var username: String
    public var password: String
    public var websiteURL: String
    public var notes: String
    public init(username: String = "", password: String = "", websiteURL: String = "", notes: String = "") {
        self.username = username; self.password = password; self.websiteURL = websiteURL; self.notes = notes
    }
    public init(from decoder: Decoder) throws {
        let f = try strictFields(decoder, "username", "password", "websiteURL", "notes")
        username = try f.value("username"); password = try f.value("password")
        websiteURL = try f.value("websiteURL"); notes = try f.value("notes")
    }
    public func encode(to encoder: Encoder) throws {
        var f = encoder.container(keyedBy: FieldKey.self)
        try f.put("username", username); try f.put("password", password)
        try f.put("websiteURL", websiteURL); try f.put("notes", notes)
    }
}

public enum TokenEnvironment: String, Codable, CaseIterable, Sendable {
    case development, testing, production
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = Self(rawValue: raw) else { throw VaultError.unsupportedPayload }
        self = value
    }
}

public struct APIToken: Codable, Equatable, Sendable {
    public var service: String
    public var token: String
    public var environment: TokenEnvironment
    public var expiresAt: Int64?
    public var notes: String
    public init(service: String = "", token: String = "", environment: TokenEnvironment = .development,
                expiresAt: Int64? = nil, notes: String = "") {
        self.service = service; self.token = token; self.environment = environment
        self.expiresAt = expiresAt; self.notes = notes
    }
    public init(from decoder: Decoder) throws {
        let f = try strictFields(decoder, "service", "token", "environment", "expiresAt", "notes")
        service = try f.value("service"); token = try f.value("token")
        environment = try f.value("environment"); expiresAt = try f.optional("expiresAt"); notes = try f.value("notes")
    }
    public func encode(to encoder: Encoder) throws {
        var f = encoder.container(keyedBy: FieldKey.self)
        try f.put("service", service); try f.put("token", token); try f.put("environment", environment)
        try f.putOptional("expiresAt", expiresAt); try f.put("notes", notes)
    }
}

public struct SecureNote: Codable, Equatable, Sendable {
    public var content: String
    public init(content: String = "") { self.content = content }
    public init(from decoder: Decoder) throws { content = try strictFields(decoder, "content").value("content") }
    public func encode(to encoder: Encoder) throws {
        var f = encoder.container(keyedBy: FieldKey.self); try f.put("content", content)
    }
}

public struct CustomField: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var value: String
    /// Controls presentation only. Both plain-display and secret-display fields are encrypted.
    public var isSecret: Bool
    public init(id: UUID = UUID(), name: String, value: String = "", isSecret: Bool = true) {
        self.id = id; self.name = name; self.value = value; self.isSecret = isSecret
    }
    public init(from decoder: Decoder) throws {
        let f = try strictFields(decoder, "id", "name", "value", "isSecret")
        id = try f.uuid("id"); name = try f.value("name"); value = try f.value("value"); isSecret = try f.value("isSecret")
    }
    public func encode(to encoder: Encoder) throws {
        var f = encoder.container(keyedBy: FieldKey.self)
        try f.putUUID("id", id); try f.put("name", name); try f.put("value", value); try f.put("isSecret", isSecret)
    }
}

public struct CustomSecret: Codable, Equatable, Sendable {
    public var customFields: [CustomField]
    public init(customFields: [CustomField] = []) { self.customFields = customFields }
    public init(from decoder: Decoder) throws { customFields = try strictFields(decoder, "customFields").value("customFields") }
    public func encode(to encoder: Encoder) throws {
        var f = encoder.container(keyedBy: FieldKey.self); try f.put("customFields", customFields)
    }
}

public enum EntryFields: Equatable, Sendable {
    case credential(Credential)
    case apiToken(APIToken)
    case secureNote(SecureNote)
    case customSecret(CustomSecret)

    public var type: String {
        switch self {
        case .credential: "credential"
        case .apiToken: "apiToken"
        case .secureNote: "secureNote"
        case .customSecret: "customSecret"
        }
    }
}
