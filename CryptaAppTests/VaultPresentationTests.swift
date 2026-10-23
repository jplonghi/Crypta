import Foundation
import XCTest
import Darwin
import CryptaCore
@testable import CryptaDesktop

@MainActor
final class VaultPresentationTests: XCTestCase {
    private func check(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(value, file: file, line: line)
    }
    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("crypta-ui-tests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func testCompleteEncryptedWorkflowAcrossSessions() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = VaultViewModel()
        model.beginCreation(); model.setCreationFolder(directory); model.creationName = "Synthetic"
        model.create(passphrase: "public UI test 🗝️ passphrase", confirmation: "public UI test 🗝️ passphrase", acknowledged: true)
        await model.waitForOperation()
        check(model.screen == .unlocked)
        check(model.errorMessage == nil)
        for kind in EntryKind.allCases {
            model.addEntry()
            let draft = try XCTUnwrap(model.editor)
            check(draft.kind == .credential)
            draft.selectKind(kind)
            draft.title = "Synthetic \(kind.rawValue)"; draft.tags = ["Testing"]; draft.isFavorite = kind == .secureNote
            draft.pendingTag = "public-tag"
            switch kind {
            case .credential: draft.username = "public-user"; draft.password = "SECRET-SENTINEL-PASSWORD"; draft.notes = "SECRET-SENTINEL-NOTES"
            case .apiToken: draft.service = "example"; draft.token = "SECRET-SENTINEL-TOKEN"; draft.environment = .production; draft.expires = true
            case .secureNote: draft.content = "SECRET-SENTINEL-NOTE\n第二行"
            case .customSecret: draft.customFields = [.init(name: "Private", value: "SECRET-SENTINEL-CUSTOM"), .init(name: "Public", value: "visible", isSecret: false)]
            }
            model.saveDraft(); await model.waitForOperation()
            check(model.errorMessage == nil)
            check(model.editor == nil)
            check(draft.title.isEmpty && draft.password.isEmpty && draft.content.isEmpty && draft.customFields.isEmpty)
        }
        check(model.vault?.entries.count == 4)
        check(model.vault?.entries.map(\.type) == EntryKind.allCases.map(\.rawValue))
        check(model.vault?.entries.allSatisfy { $0.tags == ["Testing", "public-tag"] } == true)
        model.search = "SECRET-SENTINEL"; check(model.entries.isEmpty)
        model.search = "public-user"; check(model.entries.count == 1)
        model.search = "Testing"; check(model.entries.count == 4)
        model.search = ""; model.filter = .favorites; check(model.entries.count == 1)
        model.selectedID = model.entries.first?.id; model.editSelected()
        let discardedDraft = try XCTUnwrap(model.editor)
        discardedDraft.content = "UNSAVED-SENTINEL"
        model.discardDraft()
        check(discardedDraft.content.isEmpty)
        let original = try XCTUnwrap(model.vault)
        let location = try XCTUnwrap(model.fileURL)
        model.lockImmediately()
        check(model.vault == nil && model.editor == nil && model.search.isEmpty && model.selectedID == nil)
        await model.waitForOperation()
        model.unlock(passphrase: "wrong"); await model.waitForOperation()
        check(model.vault == nil && model.screen == .locked && model.errorMessage != nil)
        let fresh = VaultViewModel()
        fresh.prepareOpen(location, folder: directory)
        fresh.unlock(passphrase: "public UI test 🗝️ passphrase"); await fresh.waitForOperation()
        check(fresh.vault == original)
        fresh.selectedID = original.entries.first?.id
        fresh.deleteSelected(); await fresh.waitForOperation()
        check(fresh.vault?.entries.count == 3)
        fresh.lockImmediately(close: true); await fresh.waitForOperation()
        check(fresh.fileURL == nil && fresh.screen == .welcome)
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let bytes = try Data(contentsOf: file)
            for sentinel in ["SECRET-SENTINEL", "UNSAVED-SENTINEL", "public-tag", "public-user", "public UI test"] {
                check(bytes.range(of: Data(sentinel.utf8)) == nil)
            }
        }
    }

    func testNewItemTypeSelectionPreservesInputAndExistingItemsKeepTheirType() {
        let draft = EntryDraft(kind: .credential)
        draft.title = "Synthetic item"; draft.tags = ["Work"]; draft.pendingTag = "Personal"; draft.isFavorite = true
        draft.username = "public user"; draft.password = "public test secret"
        draft.selectKind(.apiToken)
        draft.service = "example"; draft.token = "public token"
        draft.selectKind(.secureNote); draft.content = "public note"
        draft.selectKind(.customSecret); draft.customFields = [.init(name: "Field", value: "public value")]
        draft.selectKind(.credential)
        check(draft.username == "public user" && draft.password == "public test secret")
        for kind in EntryKind.allCases {
            draft.selectKind(kind)
            let entry = draft.entry()
            check(entry.type == kind.rawValue && entry.title == "Synthetic item")
            check(entry.tags == ["Work", "Personal"] && entry.isFavorite)
            let existing = EntryDraft(entry: entry)
            existing.selectKind(kind == .credential ? .secureNote : .credential)
            check(existing.kind == kind && existing.entry().fields == entry.fields)
        }
        draft.clear()
        check(draft.password.isEmpty && draft.token.isEmpty && draft.content.isEmpty && draft.customFields.isEmpty)
    }

    func testTagsFavoritesAndBulkEditsPersist() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let model = VaultViewModel()
        model.beginCreation(); model.setCreationFolder(directory)
        model.create(passphrase: "public organization test", confirmation: "public organization test", acknowledged: true)
        await model.waitForOperation()
        model.addEntry(.secureNote)
        let first = try XCTUnwrap(model.editor)
        check(first.tags.isEmpty && !first.isFavorite)
        check(Set(model.tagSuggestions(for: first)) == ["Work", "Personal"])
        first.title = "Both"; first.addTag(" Work "); first.addTag("work"); first.pendingTag = "Production"; first.isFavorite = true
        model.saveDraft(); await model.waitForOperation()
        let firstID = try XCTUnwrap(model.selectedID)
        model.addEntry(.secureNote); model.editor?.title = "Work only"; model.editor?.tags = ["WORK"]
        model.saveDraft(); await model.waitForOperation()
        let secondID = try XCTUnwrap(model.selectedID)
        check(model.usedTags.count == 2 && model.usedTags.first(where: { VaultTags.key($0.name) == "work" })?.count == 2)
        model.toggleTagFilter("work"); model.toggleTagFilter("PRODUCTION")
        check(model.entries.map(\.id) == [firstID])
        model.search = "only"; check(model.entries.isEmpty); model.search = ""
        model.navigate(to: .favorites); check(model.entries.map(\.id) == [firstID])
        model.toggleFavorite(secondID); await model.waitForOperation(); check(model.favoriteCount == 2)
        model.selectedID = secondID; model.editSelected(); model.editor?.title = "Edited favorite"
        model.saveDraft(); await model.waitForOperation(); check(model.selectedEntry?.isFavorite == true)
        model.addEntry(.credential)
        let draft = try XCTUnwrap(model.editor); draft.pendingTag = "wo"
        check(model.tagSuggestions(for: draft).count == 1)
        model.discardDraft()
        model.toggleTagFilter("Production")
        model.beginTagRename("Production"); model.replacementTag = "work"; model.saveDraft(); await model.waitForOperation()
        check(model.usedTags.count == 1 && model.usedTags[0].count == 2)
        check(model.vault?.entries.allSatisfy { $0.tags.count == 1 } == true)
        check(model.selectedTags == ["work"])
        model.beginTagRename("work"); model.replacementTag = "Business"; model.saveDraft(); await model.waitForOperation()
        check(model.vault?.entries.allSatisfy { $0.tags == ["Business"] } == true)
        model.removeTag("BUSINESS"); await model.waitForOperation()
        check(model.usedTags.isEmpty && model.selectedTags.isEmpty && model.vault?.entries.count == 2)
        let saved = try XCTUnwrap(model.vault)
        let url = try XCTUnwrap(model.fileURL)
        model.lockImmediately(); await model.waitForOperation()
        check(model.usedTags.isEmpty && model.favoriteCount == 0)
        model.unlock(passphrase: "public organization test"); await model.waitForOperation()
        check(model.vault == saved)
        let bytes = try Data(contentsOf: url)
        for text in ["Business", "Work only", "isFavorite"] { check(bytes.range(of: Data(text.utf8)) == nil) }
    }

    func testOrganizationFailureAndLockPreserveCommittedState() async throws {
        let service = try ControlledService(); let model = VaultViewModel(service: service)
        model.prepareOpen(URL(fileURLWithPath: "/tmp/test.crypta"), folder: URL(fileURLWithPath: "/tmp"))
        model.unlock(passphrase: "public"); await model.waitForOperation()
        model.addEntry(.secureNote); model.editor?.title = "Test"; model.editor?.tags = ["Work"]
        model.saveDraft(); await model.waitForOperation()
        let saved = model.vault; let id = try XCTUnwrap(model.selectedID)
        await service.failSave(.fileAccess)
        model.toggleFavorite(id); await model.waitForOperation()
        check(model.vault == saved && model.errorMessage != nil)
        model.removeTag("Work"); await model.waitForOperation(); check(model.vault == saved)
        model.beginTagRename("Work"); model.replacementTag = "Personal"; model.saveDraft(); await model.waitForOperation()
        check(model.vault == saved && model.tagToRename == "Work" && model.replacementTag == "Personal")
        model.lockImmediately(); await model.waitForOperation()
        check(model.tagToRename == nil && model.replacementTag.isEmpty && model.selectedTags.isEmpty)
    }

    func testFailuresPreserveDraftAndCommittedSnapshot() async throws {
        let service = try ControlledService()
        let model = VaultViewModel(service: service)
        model.prepareOpen(URL(fileURLWithPath: "/tmp/test.crypta"), folder: URL(fileURLWithPath: "/tmp"))
        model.unlock(passphrase: "public"); await model.waitForOperation()
        let original = model.vault
        model.addEntry(.credential)
        let draft = try XCTUnwrap(model.editor)
        draft.title = "Draft"; draft.password = "public test secret"
        await service.failSave(.conflict)
        model.saveDraft(); await model.waitForOperation()
        check(model.editor === draft)
        check(draft.password == "public test secret")
        check(model.vault == original && model.errorMessage != nil)
        await service.failSave(nil)
        model.saveDraft(); await model.waitForOperation()
        check(model.editor == nil && model.vault?.entries.count == 1)
        check(draft.password.isEmpty)
    }

    func testFailedReadAfterOpenReleasesSessionAndAllowsRetry() async throws {
        let service = try ControlledService()
        await service.failRead(.allocationFailed)
        let model = VaultViewModel(service: service)
        model.prepareOpen(URL(fileURLWithPath: "/tmp/test.crypta"), folder: URL(fileURLWithPath: "/tmp"))
        model.unlock(passphrase: "public"); await model.waitForOperation()
        check(await service.locked)
        check(model.screen == .locked && model.vault == nil && !model.isBusy)
        check(model.errorMessage != nil && model.isKeyMemoryLocked == nil)
        check(!model.security.sessionActive)
        await service.failRead(nil)
        model.unlock(passphrase: "public"); await model.waitForOperation()
        check(model.screen == .unlocked && model.errorMessage == nil)
    }

    func testKeyMemoryCapabilityIsReportedAndClearedOnLock() async throws {
        let service = try ControlledService()
        await service.setMemoryLocked(false)
        let model = VaultViewModel(service: service)
        model.prepareOpen(URL(fileURLWithPath: "/tmp/test.crypta"), folder: URL(fileURLWithPath: "/tmp"))
        model.unlock(passphrase: "public"); await model.waitForOperation()
        check(model.screen == .unlocked && model.isKeyMemoryLocked == false)
        model.lockImmediately(); await model.waitForOperation()
        check(model.isKeyMemoryLocked == nil)
        await service.setMemoryLocked(true)
        model.unlock(passphrase: "public"); await model.waitForOperation()
        check(model.isKeyMemoryLocked == true)
    }

    func testCoreDumpLimitIsDisabledWithoutChangingHardLimit() throws {
        var original = rlimit()
        XCTAssertEqual(getrlimit(RLIMIT_CORE, &original), 0)
        defer { XCTAssertEqual(setrlimit(RLIMIT_CORE, &original), 0) }
        var enabled = original
        enabled.rlim_cur = min(original.rlim_max, 1024)
        XCTAssertEqual(setrlimit(RLIMIT_CORE, &enabled), 0)
        check(CryptaLifecycle.disableCoreDumps())
        var result = rlimit()
        XCTAssertEqual(getrlimit(RLIMIT_CORE, &result), 0)
        XCTAssertEqual(result.rlim_cur, 0)
        XCTAssertEqual(result.rlim_max, original.rlim_max)
    }

    func testLockSuppressesLateUnlockAndClearsRetainedDraft() async throws {
        let service = try ControlledService()
        await service.pauseRead()
        let model = VaultViewModel(service: service)
        model.prepareOpen(URL(fileURLWithPath: "/tmp/test.crypta"), folder: URL(fileURLWithPath: "/tmp"))
        model.unlock(passphrase: "public")
        await service.waitUntilRead()
        model.lockImmediately()
        check(model.vault == nil && model.screen == .locked)
        await service.resumeRead()
        await model.waitForOperation()
        check(model.vault == nil && !model.isBusy)
        check(await service.locked)
        model.unlock(passphrase: "public"); await model.waitForOperation()
        model.addEntry(.secureNote)
        let draft = try XCTUnwrap(model.editor)
        draft.title = "Unsaved"; draft.content = "public secret"; model.search = "private search"
        model.lockImmediately()
        check(draft.content.isEmpty && draft.title.isEmpty)
        check(model.vault == nil && model.editor == nil && model.search.isEmpty)
        await model.waitForOperation()
    }

    func testAmbiguousStorageResultLocksAndShowsActionableError() async throws {
        let service = try ControlledService()
        let model = VaultViewModel(service: service)
        model.prepareOpen(URL(fileURLWithPath: "/tmp/test.crypta"), folder: URL(fileURLWithPath: "/tmp"))
        model.unlock(passphrase: "public"); await model.waitForOperation()
        model.addEntry(.secureNote); model.editor?.title = "Test"
        await service.failSave(.durabilityUncertain)
        model.saveDraft(); await model.waitForOperation(); await model.waitForOperation()
        check(model.vault == nil && model.editor == nil && model.screen == .locked)
        check(model.errorMessage?.contains("Reopen and inspect") == true)
    }

    func testConfirmationIsByteExactAndOpenRequiresContainingFolder() async throws {
        let service = try ControlledService()
        let model = VaultViewModel(service: service)
        model.beginCreation(); model.setCreationFolder(URL(fileURLWithPath: "/tmp"))
        model.create(passphrase: "café", confirmation: "cafe\u{301}", acknowledged: true)
        check(model.errorMessage != nil && !model.isBusy)
        check(await service.createCalls == 0)
        model.prepareOpen(URL(fileURLWithPath: "/tmp/file.crypta"), folder: URL(fileURLWithPath: "/var"))
        check(model.fileURL == nil)
    }
}

private actor ControlledService: VaultService {
    var isKeyMemoryLocked = true
    var snapshot: Vault
    var locked = true
    var createCalls = 0
    private var saveError: VaultError?
    private var readError: VaultError?
    private var pause = false
    private var reader: CheckedContinuation<Void, Never>?
    private var readStarted = false
    private var waiter: CheckedContinuation<Void, Never>?
    init() throws {
        snapshot = try JSONDecoder().decode(Vault.self, from: Data("""
        {"vaultID":"00000000000000000000000000000001","name":"Test","createdAt":0,"modifiedAt":0,"revision":0,"entries":[]}
        """.utf8))
    }
    func create(at url: URL, passphrase: String, name: String, createdAt: Date, parameters: KDFParameters) async throws -> Vault { createCalls += 1; locked = false; return snapshot }
    func open(at url: URL, passphrase: String) async throws { locked = false }
    func readVault() async throws -> Vault {
        readStarted = true; waiter?.resume(); waiter = nil
        if pause { await withCheckedContinuation { reader = $0 } }
        if let readError { throw readError }
        return snapshot
    }
    func save(vault: Vault, modifiedAt: Date) async throws -> Vault {
        if let saveError { throw saveError }
        snapshot = vault; return vault
    }
    func changePassphrase(current: String, new: String, parameters: KDFParameters) async throws {}
    func lock() async { locked = true }
    func failSave(_ error: VaultError?) { saveError = error }
    func failRead(_ error: VaultError?) { readError = error }
    func setMemoryLocked(_ locked: Bool) { isKeyMemoryLocked = locked }
    func pauseRead() { pause = true }
    func waitUntilRead() async { if !readStarted { await withCheckedContinuation { waiter = $0 } } }
    func resumeRead() { pause = false; reader?.resume(); reader = nil }
}
