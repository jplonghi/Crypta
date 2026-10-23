import SwiftUI
import CryptaDesktop

@main
struct CryptaApp: App {
    @NSApplicationDelegateAdaptor(CryptaLifecycle.self) private var lifecycle
    var body: some Scene {
        WindowGroup("Crypta", id: "main") {
            CryptaRootView(model: lifecycle.model)
                .background(CryptaWindowAttachment(lifecycle: lifecycle))
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .onOpenURL { lifecycle.openDocument($0) }
        }
        .handlesExternalEvents(matching: ["*"])
        .defaultSize(width: 640, height: 480)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Security Settings…") { lifecycle.model.isShowingSettings = true }
                    .keyboardShortcut(",").disabled(lifecycle.model.hasDraft || lifecycle.model.isBusy)
            }
            CommandGroup(after: .textEditing) {
                Button("Find Entries") { lifecycle.model.searchFocusRequest = UUID() }
                    .keyboardShortcut("f").disabled(lifecycle.model.screen != .unlocked || !lifecycle.model.canNavigate)
            }
            CommandGroup(replacing: .appTermination) {
                Button("Quit Crypta") { lifecycle.requestQuit() }.keyboardShortcut("q")
            }
            CommandGroup(replacing: .newItem) {
                Button("New Item") { lifecycle.model.addEntry() }
                    .keyboardShortcut("n").disabled(lifecycle.model.screen != .unlocked || !lifecycle.model.canNavigate)
                Button("New Vault…") { lifecycle.model.beginCreation() }
                    .keyboardShortcut("n", modifiers: [.command, .shift]).disabled(!lifecycle.model.canNavigate || lifecycle.model.vault != nil)
                Button("Open Vault…") { Task { await lifecycle.model.chooseOpenVault() } }
                    .keyboardShortcut("o").disabled(!lifecycle.model.canNavigate || lifecycle.model.vault != nil)
                Button("Close Vault") { lifecycle.model.lockImmediately(close: true) }
                    .disabled(!lifecycle.model.canNavigate || lifecycle.model.fileURL == nil)
            }
            CommandMenu("Vault") {
                Button("Lock Vault") { lifecycle.model.requestLock() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(lifecycle.model.screen != .unlocked)
                Button("Change Master Passphrase…") { lifecycle.model.beginPassphraseChange() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(lifecycle.model.screen != .unlocked || !lifecycle.model.canNavigate)
                Button("Edit Selected Entry") { lifecycle.model.editSelected() }
                    .keyboardShortcut("e").disabled(lifecycle.model.selectedEntry == nil || !lifecycle.model.canNavigate)
                Divider()
                Button("Save Changes") { lifecycle.model.saveDraft() }
                    .keyboardShortcut("s").disabled(!lifecycle.model.canSave)
            }
            CommandGroup(replacing: .undoRedo) {}
        }
    }
}
