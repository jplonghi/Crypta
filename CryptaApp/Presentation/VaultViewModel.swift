import Foundation
import Observation
import CryptaCore

@MainActor @Observable
public final class VaultViewModel {
    public private(set) var screen: VaultScreen = .welcome
    public private(set) var vault: Vault?
    public private(set) var fileURL: URL?
    public private(set) var isBusy = false
    public private(set) var activity = ""
    public let security: SessionSecurity
    public var noticeMessage: String?
    public var isShowingSettings = false
    public var passphraseDraft: PassphraseDraft?
    public var searchFocusRequest = UUID()
    public var errorMessage: String?
    public var selectedID: UUID?
    public var filter: VaultFilter = .all
    public var search = ""
    public var editor: EntryDraft?
    public var selectedTags = Set<String>()
    public var tagToRename: String?
    public var replacementTag = ""
    public var creationName = "Personal"
    public private(set) var creationFolder: URL?
    public private(set) var contentGeneration = UUID()

    @ObservationIgnored private let service: any VaultService
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var folderAccess: FolderAccess?
    @ObservationIgnored private var creationAccess: FolderAccess?

    public init(service: any VaultService = VaultEngine(), security: SessionSecurity? = nil) {
        self.service = service
        self.security = security ?? SessionSecurity()
        self.security.onAutomaticLock = { [weak self] reason in self?.automaticLock(reason) }
    }
    public var hasDraft: Bool { editor != nil || tagToRename != nil || passphraseDraft != nil }
    public var canNavigate: Bool { !isBusy && !hasDraft && !isShowingSettings }
    public var canSave: Bool {
        if let draft = passphraseDraft {
            return !isBusy && !draft.current.isEmpty && !draft.replacement.isEmpty && !draft.confirmation.isEmpty && draft.acknowledged
        }
        if tagToRename != nil { return !isBusy && !VaultTags.key(replacementTag).isEmpty }
        return !isBusy && (editor.map { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false)
    }
    public var selectedEntry: VaultEntry? { vault?.entries.first { $0.id == selectedID } }
    public var entries: [VaultEntry] {
        guard let vault else { return [] }
        return vault.entries.filter { entry in
            let included: Bool
            switch filter {
            case .all: included = true
            case .favorites: included = entry.isFavorite
            }
            guard included, selectedTags.isSubset(of: Set(entry.tags.map(VaultTags.key))) else { return false }
            guard !search.isEmpty else { return true }
            var terms = [entry.title] + entry.tags
            switch entry.fields {
            case .credential(let fields): terms += [fields.username, fields.websiteURL]
            case .apiToken(let fields): terms.append(fields.service)
            default: break
            }
            return terms.contains { $0.localizedStandardContains(search) }
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public var usedTags: [(name: String, count: Int)] {
        var counts: [String: (name: String, count: Int)] = [:]
        for entry in vault?.entries ?? [] {
            for tag in entry.tags {
                let key = VaultTags.key(tag)
                let previous = counts[key]
                counts[key] = (previous?.name ?? tag, (previous?.count ?? 0) + 1)
            }
        }
        return counts.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public var favoriteCount: Int { vault?.entries.filter(\.isFavorite).count ?? 0 }
    public func tagSuggestions(for draft: EntryDraft) -> [String] {
        let assigned = Set(draft.tags.map(VaultTags.key))
        let query = VaultTags.key(draft.pendingTag)
        return VaultTags.unique(usedTags.map(\.name) + ["Work", "Personal"])
            .filter { !assigned.contains(VaultTags.key($0)) && (query.isEmpty || VaultTags.key($0).contains(query)) }
    }
    public func navigate(to filter: VaultFilter) {
        self.filter = filter; selectedTags = []; selectedID = nil
    }
    public func toggleTagFilter(_ name: String) {
        let key = VaultTags.key(name)
        if !selectedTags.insert(key).inserted { selectedTags.remove(key) }
        selectedID = nil
    }
    private func pruneTagFilters() {
        selectedTags.formIntersection(Set(usedTags.map { VaultTags.key($0.name) }))
        if !entries.contains(where: { $0.id == selectedID }) { selectedID = nil }
    }
    public func beginTagRename(_ name: String) {
        guard canNavigate else { return }
        errorMessage = nil; tagToRename = name; replacementTag = name
    }
    public func renameTag(_ name: String, to replacement: String) {
        guard !isBusy, editor == nil, passphraseDraft == nil, !isShowingSettings, var snapshot = vault else { return }
        let replacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replacement.isEmpty, replacement.utf8.count <= 4096 else {
            errorMessage = "Enter a tag name of 1–4096 UTF-8 bytes."; return
        }
        let key = VaultTags.key(name)
        for index in snapshot.entries.indices where snapshot.entries[index].tags.contains(where: { VaultTags.key($0) == key }) {
            snapshot.entries[index].tags = VaultTags.unique(snapshot.entries[index].tags.map { VaultTags.key($0) == key ? replacement : $0 })
            snapshot.entries[index].modifiedAt = max(snapshot.entries[index].modifiedAt, EntryDraft.milliseconds(Date()))
        }
        saveOrganization(snapshot) { model in
            if model.selectedTags.remove(key) != nil { model.selectedTags.insert(VaultTags.key(replacement)) }
            model.discardDraft()
        }
    }
    public func removeTag(_ name: String) {
        guard canNavigate, var snapshot = vault else { return }
        let key = VaultTags.key(name)
        for index in snapshot.entries.indices where snapshot.entries[index].tags.contains(where: { VaultTags.key($0) == key }) {
            snapshot.entries[index].tags.removeAll { VaultTags.key($0) == key }
            snapshot.entries[index].modifiedAt = max(snapshot.entries[index].modifiedAt, EntryDraft.milliseconds(Date()))
        }
        saveOrganization(snapshot)
    }
    public func toggleFavorite(_ id: UUID) {
        guard canNavigate, var snapshot = vault, let index = snapshot.entries.firstIndex(where: { $0.id == id }) else { return }
        snapshot.entries[index].isFavorite.toggle()
        snapshot.entries[index].modifiedAt = max(snapshot.entries[index].modifiedAt, EntryDraft.milliseconds(Date()))
        saveOrganization(snapshot)
    }
    private func saveOrganization(_ snapshot: Vault, afterSave: @escaping @MainActor (VaultViewModel) -> Void = { _ in }) {
        let service = self.service
        run("Saving encrypted changes…", operation: { try await service.save(vault: snapshot, modifiedAt: Date()) }, success: { model, saved in
            model.vault = saved; afterSave(model); model.pruneTagFilters(); model.contentGeneration = UUID()
        })
    }

    public func beginCreation() {
        guard canNavigate, vault == nil else { return }
        creationName = "Personal"; creationFolder = nil; creationAccess = nil
        errorMessage = nil; screen = .create
    }
    public func setCreationFolder(_ url: URL) {
        guard screen == .create, !isBusy else { return }
        creationAccess = FolderAccess(url); creationFolder = url
    }
    public func cancelCreation() {
        guard !isBusy else { return }
        creationAccess = nil; creationFolder = nil; creationName = "Personal"; screen = .welcome; errorMessage = nil
    }

    public func create(passphrase: String, confirmation: String, acknowledged: Bool) {
        guard !isBusy, screen == .create, let folder = creationFolder else { return }
        guard acknowledged else { errorMessage = "Confirm that you understand a lost passphrase cannot be recovered."; return }
        guard !passphrase.isEmpty, VaultEngine.passphrasesMatch(passphrase, confirmation) else {
            errorMessage = "Enter a nonempty passphrase and an exact matching confirmation."; return
        }
        let name = creationName
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 230,
              !name.contains("/"), !name.contains(":"), !name.utf8.contains(0), name != ".", name != ".." else {
            errorMessage = "Choose a file name of at most 230 UTF-8 bytes without slashes, colons, or null characters."; return
        }
        let filename = name.hasSuffix(".crypta") ? name : name + ".crypta"
        let url = folder.appendingPathComponent(filename)
        let service = self.service
        security.beginSession()
        run("Creating encrypted vault…", operation: {
            try await service.create(at: url, passphrase: passphrase, name: name, createdAt: Date(), parameters: .standard)
        }, success: { model, value in
            model.fileURL = url; model.folderAccess = model.creationAccess; model.creationAccess = nil
            model.creationFolder = nil; model.vault = value; model.screen = .unlocked
        })
    }

    public func prepareOpen(_ url: URL, folder: URL) {
        guard canNavigate, vault == nil else { return }
        guard url.isFileURL, folder.isFileURL,
              url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == folder.resolvingSymlinksInPath().standardizedFileURL.path else {
            errorMessage = "Select the folder containing this vault."; return
        }
        folderAccess = FolderAccess(folder); fileURL = url
        creationAccess = nil; creationFolder = nil; screen = .locked; errorMessage = nil
    }

    public func unlock(passphrase: String) {
        guard !isBusy, screen == .locked, let url = fileURL else { return }
        let service = self.service
        security.beginSession()
        run("Unlocking vault…", operation: {
            try await service.open(at: url, passphrase: passphrase)
            return try await service.readVault()
        }, success: { model, value in model.vault = value; model.screen = .unlocked })
    }

    public func addEntry(_ kind: EntryKind) {
        guard vault != nil, canNavigate else { return }
        errorMessage = nil; editor = EntryDraft(kind: kind)
    }
    public func editSelected() {
        guard canNavigate, let entry = selectedEntry else { return }
        errorMessage = nil; editor = EntryDraft(entry: entry)
    }
    public func discardDraft() {
        guard !isBusy else { return }
        editor?.clear(); editor = nil; tagToRename = nil; replacementTag = ""; errorMessage = nil
        passphraseDraft?.clear(); passphraseDraft = nil
    }
    public func saveDraft() {
        if passphraseDraft != nil { changePassphrase(); return }
        if let tagToRename { renameTag(tagToRename, to: replacementTag); return }
        guard canSave, var snapshot = vault else { return }
        var selected: UUID?
        if let editor {
            let entry = editor.entry()
            selected = entry.id
            if let index = snapshot.entries.firstIndex(where: { $0.id == entry.id }) { snapshot.entries[index] = entry }
            else { snapshot.entries.append(entry) }
        }
        let service = self.service
        let edited = snapshot
        let savedSelection = selected
        run("Saving encrypted changes…", operation: { try await service.save(vault: edited, modifiedAt: Date()) }, success: { model, saved in
            model.vault = saved; model.discardDraft(); model.filter = .all; model.selectedTags = []; model.search = ""
            if let savedSelection { model.selectedID = savedSelection }
            model.contentGeneration = UUID()
        })
    }
    public func deleteSelected() {
        guard canNavigate, var snapshot = vault, let selectedID else { return }
        snapshot.entries.removeAll { $0.id == selectedID }
        let service = self.service
        let edited = snapshot
        run("Deleting entry…", operation: { try await service.save(vault: edited, modifiedAt: Date()) }, success: { model, saved in
            model.vault = saved; model.selectedID = nil; model.pruneTagFilters(); model.contentGeneration = UUID()
        })
    }

    /// Obscures immediately. Generation checks suppress every late async result, including unlocks.
    public func lockImmediately(close: Bool = false) {
        security.endSession()
        noticeMessage = nil
        passphraseDraft?.clear(); passphraseDraft = nil
        isShowingSettings = false
        creationName = "Personal"
        generation += 1
        let current = generation
        let previousTask = task
        previousTask?.cancel()
        editor?.clear(); editor = nil; tagToRename = nil; replacementTag = ""
        vault = nil; selectedID = nil; search = ""; filter = .all; selectedTags = []; errorMessage = nil; contentGeneration = UUID()
        screen = fileURL == nil || close ? .welcome : .locked
        isBusy = true; activity = "Locking vault…"
        let service = self.service
        // Retain folder grants until any in-flight file operation and engine lock finish.
        let retainedAccess = folderAccess
        let retainedCreationAccess = creationAccess
        task = Task { [weak self] in
            await previousTask?.value
            await service.lock()
            withExtendedLifetime((retainedAccess, retainedCreationAccess)) {}
            guard let self, self.generation == current else { return }
            self.isBusy = false; self.activity = ""; self.task = nil
            self.creationAccess = nil; self.creationFolder = nil
            if close { self.fileURL = nil; self.folderAccess = nil; self.creationAccess = nil; self.creationFolder = nil }
        }
    }

    public func beginPassphraseChange() {
        guard screen == .unlocked, canNavigate else { return }
        errorMessage = nil; noticeMessage = nil; passphraseDraft = PassphraseDraft()
    }
    public func changePassphrase() {
        guard canSave, screen == .unlocked, let draft = passphraseDraft else { return }
        guard VaultEngine.passphrasesMatch(draft.replacement, draft.confirmation) else {
            errorMessage = "The new passphrase and confirmation must match exactly."
            return
        }
        let current = draft.current
        let replacement = draft.replacement
        draft.clear()
        let service = self.service
        run("Changing master passphrase…", operation: {
            try await service.changePassphrase(current: current, new: replacement, parameters: .standard)
            return try await service.readVault()
        }, success: { model, saved in
            model.vault = saved; model.passphraseDraft?.clear(); model.passphraseDraft = nil
            model.noticeMessage = "Master passphrase changed. Older backups still use their previous passphrase."
        })
    }
    public func copySecret(_ value: String) {
        guard screen == .unlocked, !isBusy else { return }
        guard security.copy(value) else {
            if screen == .unlocked { errorMessage = "The clipboard changed or could not accept this value. Try copying again." }
            return
        }
        noticeMessage = security.clipboardSeconds == 0
            ? "Copied. Crypta clears its clipboard content when the vault locks."
            : "Copied. Clears after \(security.clipboardSeconds) seconds, or when the vault locks."
    }
    func automaticLock(_ reason: AutomaticLockReason) {
        let discarded = hasDraft
        let interrupted = isBusy
        lockImmediately()
        let cause: String
        switch reason {
        case .inactivity: cause = "Locked after inactivity."
        case .sleep: cause = "Locked because the Mac went to sleep."
        case .sessionChange: cause = "Locked because the macOS session became inactive."
        }
        noticeMessage = cause + (interrupted ? " An operation was interrupted; reopen to check the last committed state." : discarded ? " Unsaved drafts were discarded." : "")
    }

    /// Useful for orderly termination and deterministic presentation tests.
    public func waitForOperation() async { await task?.value }

    private func run(_ label: String, operation: @escaping @Sendable () async throws -> Vault,
                     success: @escaping @MainActor (VaultViewModel, Vault) -> Void) {
        guard !isBusy else { return }
        generation += 1
        let current = generation
        isBusy = true; activity = label; errorMessage = nil; noticeMessage = nil
        task = Task { [weak self] in
            guard !Task.isCancelled else { return }
            do {
                let result = try await operation()
                guard let self, self.generation == current, !Task.isCancelled else { return }
                self.isBusy = false; self.activity = ""; self.task = nil
                success(self, result)
            } catch {
                guard let self, self.generation == current else { return }
                self.isBusy = false; self.activity = ""; self.task = nil
                if self.screen != .unlocked { self.security.endSession() }
                if error is CancellationError { return }
                if error as? VaultError == .durabilityUncertain { self.lockImmediately() }
                self.errorMessage = UserFacingError.message(error)
            }
        }
    }
}
