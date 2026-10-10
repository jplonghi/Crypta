import AppKit
import XCTest
import CryptaCore
@testable import CryptaDesktop

@MainActor final class SessionSecurityTests: XCTestCase {
    func testInactivityUsesOnlyUserActivityAndRejectsLateEvent() {
        let clock = TestSecurityClock(); let board = TestPasteboard()
        let security = SessionSecurity(clock: clock, pasteboard: board)
        security.inactivitySeconds = 60
        var locks = 0
        security.onAutomaticLock = { _ in locks += 1 }
        security.beginSession()
        clock.now = 59; XCTAssertTrue(security.recordActivity())
        clock.now = 118; security.tick(); XCTAssertEqual(locks, 0)
        clock.now = 119; XCTAssertFalse(security.recordActivity())
        XCTAssertEqual(locks, 1); XCTAssertFalse(security.sessionActive)
        security.tick(); XCTAssertEqual(locks, 1)
    }

    func testClipboardExpiresOnlyOwnedWriteIncludingIdenticalExternalValue() {
        let clock = TestSecurityClock(); let board = TestPasteboard()
        let security = SessionSecurity(clock: clock, pasteboard: board)
        security.beginSession(); XCTAssertTrue(security.copy("public first"))
        clock.now = 29; security.tick(); XCTAssertEqual(board.value, "public first")
        clock.now = 30; security.tick(); XCTAssertNil(board.value)
        security.copy("public same"); board.externalWrite("public same")
        clock.now = 60; security.tick(); XCTAssertEqual(board.value, "public same")
        security.copy("public Crypta"); board.externalWrite("other app")
        security.endSession(); XCTAssertEqual(board.value, "other app")
    }

    func testNewCopyReplacesOldDeadlineAndLockClearsEvenWithoutExpiration() {
        let clock = TestSecurityClock(); let board = TestPasteboard()
        let security = SessionSecurity(clock: clock, pasteboard: board)
        security.inactivitySeconds = 0
        security.beginSession(); security.copy("first")
        clock.now = 20; security.copy("second")
        clock.now = 30; security.tick(); XCTAssertEqual(board.value, "second")
        clock.now = 50; security.tick(); XCTAssertNil(board.value)
        security.clipboardSeconds = 0; security.copy("no timer")
        clock.now = 10000; security.tick(); XCTAssertEqual(board.value, "no timer")
        security.systemWillSleep(); XCTAssertNil(board.value)
        XCTAssertFalse(security.copy("late callback")); XCTAssertNil(board.value)
    }

    func testRealPasteboardAdapterUsesOwnershipAndConcealedHints() throws {
        let board = NSPasteboard(name: .init("app.crypta.tests.\(UUID())"))
        defer { board.releaseGlobally() }
        let adapter = SystemSecretPasteboard(board)
        let count = try XCTUnwrap(adapter.write("public synthetic secret"))
        XCTAssertTrue(board.types?.contains(.init("org.nspasteboard.ConcealedType")) == true)
        board.clearContents(); board.setString("public synthetic secret", forType: .string)
        adapter.clear(ifOwnedBy: count)
        XCTAssertEqual(board.string(forType: .string), "public synthetic secret")
        let next = try XCTUnwrap(adapter.write("second"))
        adapter.clear(ifOwnedBy: next)
        XCTAssertNil(board.string(forType: .string))
    }

    func testPreferenceValidationAndPersistenceContainOnlyDurations() {
        let suite = "app.crypta.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(-1, forKey: "inactivitySeconds")
        defaults.set(999, forKey: "clipboardSeconds")
        let security = SessionSecurity(clock: TestSecurityClock(), pasteboard: TestPasteboard(), defaults: defaults)
        XCTAssertEqual(security.inactivitySeconds, 300); XCTAssertEqual(security.clipboardSeconds, 30)
        security.inactivitySeconds = 900; security.clipboardSeconds = 60
        let reopened = SessionSecurity(clock: TestSecurityClock(), pasteboard: TestPasteboard(), defaults: defaults)
        XCTAssertEqual(reopened.inactivitySeconds, 900); XCTAssertEqual(reopened.clipboardSeconds, 60)
        XCTAssertEqual(defaults.persistentDomain(forName: suite)?.count, 2)
    }

    func testSleepDiscardsDraftAndPassphraseFieldsWithInactivityDisabled() async throws {
        let (model, security, _, board, _) = try await openedModel()
        security.inactivitySeconds = 0
        model.addEntry(.secureNote)
        let draft = try XCTUnwrap(model.editor)
        draft.title = "private title"; draft.content = "private note"
        model.copySecret("private note")
        security.systemWillSleep()
        XCTAssertNil(model.vault); XCTAssertNil(model.editor); XCTAssertNil(board.value)
        XCTAssertEqual(draft.content, ""); XCTAssertTrue(model.noticeMessage?.contains("discarded") == true)
        await model.waitForOperation()
        model.unlock(passphrase: "public"); await model.waitForOperation()
        model.beginPassphraseChange()
        let passphrase = try XCTUnwrap(model.passphraseDraft)
        passphrase.current = "old"; passphrase.replacement = "new"; passphrase.confirmation = "new"
        security.sessionDidResignActive()
        XCTAssertNil(model.passphraseDraft); XCTAssertEqual(passphrase.current, ""); XCTAssertEqual(passphrase.replacement, "")
        await model.waitForOperation()
    }

    func testSleepDuringUnlockAndSaveSuppressesLateResults() async throws {
        for operation in [DelayedSecurityService.Operation.open, .save, .rewrap] {
            let (model, security, _, _, service) = try await openedModel()
            if operation == .open {
                model.lockImmediately(); await model.waitForOperation()
            }
            await service.pause(operation)
            switch operation {
            case .open: model.unlock(passphrase: "public")
            case .save: model.addEntry(.secureNote); model.editor?.title = "Delayed"; model.saveDraft()
            case .rewrap:
                model.beginPassphraseChange()
                model.passphraseDraft?.current = "public"; model.passphraseDraft?.replacement = "new"
                model.passphraseDraft?.confirmation = "new"; model.passphraseDraft?.acknowledged = true
                model.changePassphrase()
            }
            await service.waitUntilPaused()
            security.systemWillSleep()
            XCTAssertNil(model.vault); XCTAssertNil(model.editor); XCTAssertNil(model.passphraseDraft)
            XCTAssertTrue(model.noticeMessage?.contains("interrupted") == true)
            await service.resume()
            await model.waitForOperation()
            XCTAssertEqual(model.screen, .locked); XCTAssertNil(model.vault); XCTAssertFalse(model.isBusy)
            let locked = await service.locked; XCTAssertTrue(locked)
        }
    }

    func testBackgroundSaveCompletionDoesNotResetInactivity() async throws {
        let (model, security, clock, _, _) = try await openedModel()
        security.inactivitySeconds = 60
        clock.now = 59
        model.addEntry(.secureNote); model.editor?.title = "Saved"; model.saveDraft()
        await model.waitForOperation()
        clock.now = 60; security.tick()
        XCTAssertNil(model.vault); XCTAssertEqual(model.screen, .locked)
        await model.waitForOperation()
    }

    func testFailedPassphraseChangeClearsInputsAndKeepsForm() async throws {
        let (model, _, _, _, service) = try await openedModel()
        model.beginPassphraseChange()
        let draft = try XCTUnwrap(model.passphraseDraft)
        draft.current = "wrong"; draft.replacement = "café"; draft.confirmation = "cafe\u{301}"; draft.acknowledged = true
        model.changePassphrase()
        XCTAssertFalse(model.isBusy); XCTAssertNotNil(model.errorMessage)
        let calls = await service.rewrapCalls; XCTAssertEqual(calls, 0)
        draft.confirmation = "café"
        await service.failRewrap()
        model.changePassphrase(); await model.waitForOperation()
        XCTAssertNotNil(model.errorMessage); XCTAssertTrue(model.passphraseDraft === draft)
        XCTAssertEqual(draft.current, ""); XCTAssertEqual(draft.replacement, ""); XCTAssertEqual(draft.confirmation, "")
        XCTAssertEqual(model.screen, .unlocked)
    }

    func testRealEnginePassphraseChangePreservesPayloadAndOldBackup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("crypta-rewrap-ui-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let security = SessionSecurity(clock: TestSecurityClock(), pasteboard: TestPasteboard())
        let model = VaultViewModel(security: security)
        model.beginCreation(); model.setCreationFolder(directory)
        model.create(passphrase: "old public passphrase", confirmation: "old public passphrase", acknowledged: true)
        await model.waitForOperation()
        let location = try XCTUnwrap(model.fileURL)
        model.addEntry(.secureNote); model.editor?.title = "Public test"; model.editor?.content = "sentinel"
        model.saveDraft(); await model.waitForOperation()
        let before = try Data(contentsOf: location)
        let snapshot = model.vault
        let backup = directory.appendingPathComponent("Backup.crypta")
        try FileManager.default.copyItem(at: location, to: backup)
        model.beginPassphraseChange()
        model.passphraseDraft?.current = "old public passphrase"
        model.passphraseDraft?.replacement = "new 🗝️ public passphrase"
        model.passphraseDraft?.confirmation = "new 🗝️ public passphrase"
        model.passphraseDraft?.acknowledged = true
        model.changePassphrase(); await model.waitForOperation()
        XCTAssertNil(model.errorMessage); XCTAssertNil(model.passphraseDraft); XCTAssertEqual(model.vault, snapshot)
        let after = try Data(contentsOf: location)
        // Header + wrapped-key size is fixed by the v1 format. Payload must be byte-identical.
        XCTAssertEqual(before.dropFirst(192), after.dropFirst(192))
        XCTAssertNotEqual(before, after)
        model.lockImmediately(); await model.waitForOperation()
        model.unlock(passphrase: "old public passphrase"); await model.waitForOperation(); XCTAssertNil(model.vault)
        model.unlock(passphrase: "new 🗝️ public passphrase"); await model.waitForOperation(); XCTAssertEqual(model.vault, snapshot)
        let recovery = VaultEngine()
        try await recovery.open(at: backup, passphrase: "old public passphrase")
        let oldSnapshot = try await recovery.readVault(); XCTAssertEqual(oldSnapshot, snapshot)
        await recovery.lock(); model.lockImmediately(); await model.waitForOperation()
    }

    private func openedModel() async throws -> (VaultViewModel, SessionSecurity, TestSecurityClock, TestPasteboard, DelayedSecurityService) {
        let clock = TestSecurityClock(); let board = TestPasteboard()
        let security = SessionSecurity(clock: clock, pasteboard: board)
        let service = try DelayedSecurityService()
        let model = VaultViewModel(service: service, security: security)
        model.prepareOpen(URL(fileURLWithPath: "/tmp/test.crypta"), folder: URL(fileURLWithPath: "/tmp"))
        model.unlock(passphrase: "public"); await model.waitForOperation()
        _ = try XCTUnwrap(model.vault)
        return (model, security, clock, board, service)
    }
}

@MainActor private final class TestSecurityClock: SecurityClock { var now: TimeInterval = 0 }
@MainActor private final class TestPasteboard: SecretPasteboard {
    var count = 0
    var value: String?
    func write(_ value: String) -> Int? { count += 1; self.value = value; return count }
    func clear(ifOwnedBy owner: Int) { if owner == count { count += 1; value = nil } }
    func externalWrite(_ value: String) { count += 1; self.value = value }
}

private actor DelayedSecurityService: VaultService {
    enum Operation { case open, save, rewrap }
    var locked = true
    var rewrapCalls = 0
    private var snapshot: Vault
    private var pausedOperation: Operation?
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private var rewrapFails = false
    init() throws {
        snapshot = try JSONDecoder().decode(Vault.self, from: Data("""
        {"schemaVersion":1,"vaultID":"00000000000000000000000000000001","name":"Test","createdAt":0,"modifiedAt":0,"revision":0,"categories":[],"entries":[]}
        """.utf8))
    }
    func create(at url: URL, passphrase: String, name: String, createdAt: Date, parameters: KDFParameters) async throws -> Vault { locked = false; return snapshot }
    func open(at url: URL, passphrase: String) async throws { await gate(.open); locked = false }
    func readVault() async throws -> Vault { snapshot }
    func save(vault: Vault, modifiedAt: Date) async throws -> Vault { await gate(.save); snapshot = vault; return vault }
    func changePassphrase(current: String, new: String, parameters: KDFParameters) async throws {
        rewrapCalls += 1; await gate(.rewrap)
        if rewrapFails { throw VaultError.authenticationFailed }
    }
    func lock() async { locked = true }
    func pause(_ operation: Operation) { pausedOperation = operation }
    func waitUntilPaused() async { if continuation == nil { await withCheckedContinuation { waiter = $0 } } }
    func resume() { pausedOperation = nil; continuation?.resume(); continuation = nil }
    func failRewrap() { rewrapFails = true }
    private func gate(_ operation: Operation) async {
        guard pausedOperation == operation else { return }
        await withCheckedContinuation { continuation = $0; waiter?.resume(); waiter = nil }
    }
}
