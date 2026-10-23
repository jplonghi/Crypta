import Foundation

enum VaultValidation {
    static let maxTimestamp: Int64 = 253_402_300_799_999
    static let maxRevision: UInt64 = 9_007_199_254_740_991

    static func timestamp(_ date: Date) throws -> Int64 {
        let milliseconds = date.timeIntervalSince1970 * 1000
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds <= Double(maxTimestamp) else {
            throw VaultError.invalidPayload
        }
        return Int64(milliseconds.rounded(.down))
    }

    static func validate(_ vault: Vault, expectedID: VaultID) throws {
        guard vault.vaultID == expectedID else { throw VaultError.invalidPayload }
        try date(vault.createdAt); try date(vault.modifiedAt)
        guard vault.createdAt <= vault.modifiedAt else { throw VaultError.invalidPayload }
        guard vault.revision <= maxRevision, vault.entries.count <= 10_000 else {
            throw VaultError.resourceLimit
        }
        var budget = StringBudget()
        try budget.check(vault.name)
        var entryIDs = Set<UUID>()
        for entry in vault.entries {
            guard entryIDs.insert(entry.id).inserted else { throw VaultError.invalidPayload }
            try date(entry.createdAt); try date(entry.modifiedAt)
            guard entry.createdAt <= entry.modifiedAt,
                  !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VaultError.invalidPayload }
            guard entry.tags.count <= VaultTags.maximumCount else { throw VaultError.resourceLimit }
            try budget.check(entry.title)
            var tagKeys = Set<String>()
            for tag in entry.tags {
                try budget.check(tag)
                guard !VaultTags.key(tag).isEmpty, tag == tag.trimmingCharacters(in: .whitespacesAndNewlines),
                      tagKeys.insert(VaultTags.key(tag)).inserted else { throw VaultError.invalidPayload }
            }
            switch entry.fields {
            case .credential(let value):
                try budget.check(value.username); try budget.check(value.websiteURL)
                try budget.check(value.password, large: true); try budget.check(value.notes, large: true)
            case .apiToken(let value):
                try budget.check(value.service); try budget.check(value.token, large: true); try budget.check(value.notes, large: true)
                if let expiration = value.expiresAt { try date(expiration) }
            case .secureNote(let value): try budget.check(value.content, large: true)
            case .customSecret(let value):
                guard value.customFields.count <= 100 else { throw VaultError.resourceLimit }
                var fieldIDs = Set<UUID>()
                for field in value.customFields {
                    guard fieldIDs.insert(field.id).inserted else { throw VaultError.invalidPayload }
                    try budget.check(field.name); try budget.check(field.value, large: true)
                }
            }
        }
    }

    private static func date(_ value: Int64) throws {
        guard (0...maxTimestamp).contains(value) else { throw VaultError.invalidPayload }
    }
    private struct StringBudget {
        var bytes = 0
        mutating func check(_ value: String, large: Bool = false) throws {
            let count = value.utf8.count
            guard count <= (large ? 1_048_576 : 4096), count <= VaultFormat.maxPayloadBytes - bytes else {
                throw VaultError.resourceLimit
            }
            bytes += count
        }
    }
}
