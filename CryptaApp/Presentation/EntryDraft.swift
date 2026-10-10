import Foundation
import Observation
import CryptaCore

@MainActor @Observable
public final class EntryDraft: Identifiable {
    public let id: UUID
    public let kind: EntryKind
    let createdAt: Int64
    private let previousModifiedAt: Int64
    public var title = ""
    public var tags: [String] = []
    public var pendingTag = ""
    public var isFavorite = false
    public var username = ""
    public var password = ""
    public var websiteURL = ""
    public var notes = ""
    public var service = ""
    public var token = ""
    public var environment: TokenEnvironment = .development
    public var expires = false
    public var expiration = Date()
    public var content = ""
    public var customFields: [CustomField] = []
    public let isNew: Bool

    public init(kind: EntryKind, now: Date = Date()) {
        id = UUID(); self.kind = kind; isNew = true
        createdAt = Self.milliseconds(now); previousModifiedAt = createdAt
    }

    public init(entry: VaultEntry) {
        id = entry.id; kind = EntryKind(rawValue: entry.type) ?? .customSecret; isNew = false
        createdAt = entry.createdAt; previousModifiedAt = entry.modifiedAt
        title = entry.title; tags = entry.tags; isFavorite = entry.isFavorite
        switch entry.fields {
        case .credential(let value):
            username = value.username; password = value.password; websiteURL = value.websiteURL; notes = value.notes
        case .apiToken(let value):
            service = value.service; token = value.token; environment = value.environment; notes = value.notes
            expires = value.expiresAt != nil
            if let instant = value.expiresAt { expiration = Date(timeIntervalSince1970: Double(instant) / 1000) }
        case .secureNote(let value): content = value.content
        case .customSecret(let value): customFields = value.customFields
        }
    }

    public func entry(now: Date = Date()) -> VaultEntry {
        let fields: EntryFields
        switch kind {
        case .credential: fields = .credential(.init(username: username, password: password, websiteURL: websiteURL, notes: notes))
        case .apiToken: fields = .apiToken(.init(service: service, token: token, environment: environment,
                                                expiresAt: expires ? Self.milliseconds(expiration) : nil, notes: notes))
        case .secureNote: fields = .secureNote(.init(content: content))
        case .customSecret: fields = .customSecret(.init(customFields: customFields))
        }
        // Do not lose a tag still in the input when Save is clicked.
        let committedTags = pendingTag.isEmpty ? tags : tags + [pendingTag]
        return VaultEntry(id: id, title: title, createdAt: createdAt,
                          modifiedAt: max(previousModifiedAt, Self.milliseconds(now)),
                          tags: VaultTags.unique(committedTags), isFavorite: isFavorite, fields: fields)
    }

    public func addTag(_ name: String) {
        let updated = VaultTags.unique(tags + [name])
        guard updated.count <= VaultTags.maximumCount else { return }
        tags = updated; pendingTag = ""
    }

    func clear() {
        title = ""; tags = []; pendingTag = ""; isFavorite = false
        username = ""; password = ""; websiteURL = ""; notes = ""
        service = ""; token = ""; content = ""; customFields = []
        expires = false; expiration = Date(timeIntervalSince1970: 0)
    }

    static func milliseconds(_ date: Date) -> Int64 {
        let value = date.timeIntervalSince1970 * 1000
        guard value.isFinite, value >= 0, value <= 253_402_300_799_999 else { return -1 }
        return Int64(value.rounded(.down))
    }
}
