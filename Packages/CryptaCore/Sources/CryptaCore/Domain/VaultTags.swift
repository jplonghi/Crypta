import Foundation

/// Tag identity is locale-independent and case-insensitive; display spelling stays user-controlled.
public enum VaultTags {
    // Schema 1 allowed 100 tags plus a category. Migration must preserve all 101 labels.
    public static let maximumCount = 101

    public static func key(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }

    public static func unique(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            let name = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(key(name)).inserted else { return nil }
            return name
        }
    }
}
