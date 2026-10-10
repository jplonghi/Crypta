import AppKit
import SwiftUI

@MainActor public extension VaultViewModel {
    func requestLock() {
        if hasDraft {
            let alert = NSAlert()
            alert.messageText = "Discard unsaved edits and lock?"
            alert.informativeText = "Your last encrypted save is safe. The current draft will be discarded."
            alert.addButton(withTitle: "Discard and Lock")
            alert.addButton(withTitle: "Keep Editing")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        lockImmediately()
    }
}

/// One window, one vault. Closing the window uses the same draft checks as Quit.
@MainActor public final class CryptaLifecycle: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public let model = VaultViewModel()
    // Objective-C forwarding is nonisolated. Reads below require the main thread; writes are MainActor-only.
    nonisolated(unsafe) private weak var originalWindowDelegate: (any NSWindowDelegate)?
    private weak var mainWindow: NSWindow?
    private var pendingDocument: URL?
    private var openingDocument = false
    private var terminationPending = false
    private var readyToTerminate = false
    private var securityMonitor: AppSecurityMonitor?

    public override init() { super.init() }
    public func attach(_ window: NSWindow) {
        guard window.delegate !== self else { return }
        originalWindowDelegate = window.delegate
        window.delegate = self
        window.isRestorable = false
        window.acceptsMouseMovedEvents = true
        window.identifier = NSUserInterfaceItemIdentifier("CryptaMainWindow")
        mainWindow = window
        if securityMonitor == nil {
            let monitor = AppSecurityMonitor(security: model.security)
            securityMonitor = monitor; monitor.start()
        }
        if let url = pendingDocument {
            pendingDocument = nil
            Task { @MainActor in openDocument(url) }
        }
    }
    public override func forwardingTarget(for selector: Selector!) -> Any? {
        guard Thread.isMainThread else { return super.forwardingTarget(for: selector) }
        if let originalWindowDelegate, originalWindowDelegate.responds(to: selector) { return originalWindowDelegate }
        return super.forwardingTarget(for: selector)
    }
    public override func responds(to selector: Selector!) -> Bool {
        if super.responds(to: selector) { return true }
        guard Thread.isMainThread else { return false }
        return originalWindowDelegate?.responds(to: selector) ?? false
    }
    public func windowShouldClose(_ sender: NSWindow) -> Bool { requestQuit(); return false }
    public func requestQuit() {
        if applicationShouldTerminate(NSApp) == .terminateNow { NSApp.terminate(nil) }
    }
    public func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.count == 1, let url = urls.first else {
            model.errorMessage = "Open one vault at a time."
            return
        }
        openDocument(url)
    }
    public func openDocument(_ url: URL) {
        guard let mainWindow else { pendingDocument = url; return }
        mainWindow.makeKeyAndOrderFront(nil)
        guard !openingDocument else { return }
        openingDocument = true
        Task { @MainActor in
            await model.openVaultURL(url)
            openingDocument = false
        }
    }
    public func applicationWillTerminate(_ notification: Notification) { securityMonitor?.stop() }
    public func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool { false }
    public func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool { false }
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if readyToTerminate { return .terminateNow }
        guard !terminationPending else { return .terminateCancel }
        if model.isBusy {
            terminationPending = true
            Task { @MainActor in
                await model.waitForOperation()
                terminationPending = false
                requestQuit()
            }
            return .terminateCancel
        }
        if model.hasDraft {
            let alert = NSAlert()
            alert.messageText = "Save your changes before quitting?"
            alert.informativeText = "Save encrypts the draft into your vault. Discard keeps the last saved version."
            alert.addButton(withTitle: "Save and Quit")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Discard and Quit")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                guard model.canSave else { return .terminateCancel }
                terminationPending = true
                model.saveDraft()
                Task { @MainActor in
                    await model.waitForOperation()
                    terminationPending = false
                    guard !model.hasDraft, model.errorMessage == nil else { return }
                    requestQuit()
                }
                return .terminateCancel
            case .alertThirdButtonReturn: model.discardDraft()
            default: return .terminateCancel
            }
        }
        // Keep the ordinary event loop alive while the actor releases key memory.
        // Return cancel while saving/locking, then request termination after completion.
        terminationPending = true
        model.lockImmediately(close: true)
        Task { @MainActor in
            await model.waitForOperation()
            readyToTerminate = true
            NSApp.terminate(nil)
        }
        return .terminateCancel
    }
}

public struct CryptaWindowAttachment: NSViewRepresentable {
    let lifecycle: CryptaLifecycle
    public init(lifecycle: CryptaLifecycle) { self.lifecycle = lifecycle }
    public func makeNSView(context: Context) -> NSView { Hook(lifecycle: lifecycle) }
    public func updateNSView(_ nsView: NSView, context: Context) {}
    private final class Hook: NSView {
        let lifecycle: CryptaLifecycle
        init(lifecycle: CryptaLifecycle) { self.lifecycle = lifecycle; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { lifecycle.attach(window) }
        }
    }
}
