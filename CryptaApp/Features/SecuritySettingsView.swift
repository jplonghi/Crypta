import SwiftUI

struct SecuritySettingsView: View {
    @Bindable var model: VaultViewModel
    @Bindable var security: SessionSecurity
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("Security settings", systemImage: "lock.shield").font(.title2.bold())
            Picker("Lock after inactivity", selection: $security.inactivitySeconds) {
                Text("Never").tag(0)
                Text("1 minute").tag(60)
                Text("5 minutes").tag(300)
                Text("15 minutes").tag(900)
                Text("30 minutes").tag(1800)
            }
            Text("Only activity in Crypta resets the timer. Sleep and switching away from your macOS session always lock the vault, even with Never selected. Unsaved drafts are discarded on automatic lock.")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            Picker("Clear copied secrets after", selection: $security.clipboardSeconds) {
                Text("Only when locking").tag(0)
                Text("15 seconds").tag(15)
                Text("30 seconds").tag(30)
                Text("1 minute").tag(60)
                Text("2 minutes").tag(120)
            }
            Text("Copy buttons clear only the clipboard write made by Crypta. Lock and Quit also clear that write. Clipboard history tools or other apps may retain a copy. Text copied manually from an editor is not managed by Crypta.")
                .font(.callout).foregroundStyle(.secondary)
            Text("These preferences are saved on this Mac. Your vault remains portable.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { model.isShowingSettings = false }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 520)
    }
}

struct PassphraseChangeView: View {
    @Bindable var model: VaultViewModel
    @Bindable var draft: PassphraseDraft
    @State private var focus = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Change master passphrase").font(.title2.bold())
            Text("Enter your current passphrase to protect this vault with a new one. Spaces and Unicode are used exactly as entered.")
                .foregroundStyle(.secondary)
            input("Current passphrase", text: $draft.current, focus: focus)
            input("New passphrase", text: $draft.replacement)
            input("Confirm new passphrase", text: $draft.confirmation)
            Toggle("I understand there is no recovery if I lose the new passphrase.", isOn: $draft.acknowledged).toggleStyle(.checkbox)
            Text("Older backups keep their old passphrase. Changing it does not revoke old copies. Automatic lock discards this form; if a change is interrupted, reopen the vault to check which passphrase works.")
                .font(.callout).foregroundStyle(.secondary)
            if let error = model.errorMessage { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout) }
            HStack {
                Button("Cancel") { model.discardDraft() }.keyboardShortcut(.cancelAction)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
                Button("Change Passphrase") { model.changePassphrase() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!model.canSave)
            }
        }.padding(28).frame(width: 540).disabled(model.isBusy)
    }
    private func input(_ label: String, text: Binding<String>, focus: UUID? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.callout.weight(.medium))
            PrivateTextInput(text: text, prompt: label, secret: true, focusRequest: focus).frame(height: 24)
        }
    }
}
