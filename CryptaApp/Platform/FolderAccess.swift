import Foundation

/// A selected directory authorizes encrypted staging/lock siblings, not just the vault file.
/// Access lasts through in-flight operations; no bookmark, key, or path is persisted.
@MainActor
final class FolderAccess {
    let url: URL
    private let scoped: Bool
    init(_ url: URL) {
        self.url = url
        scoped = url.startAccessingSecurityScopedResource()
    }
    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}
