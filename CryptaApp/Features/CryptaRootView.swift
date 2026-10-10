import SwiftUI

public struct CryptaRootView: View {
    @Bindable var model: VaultViewModel
    public init(model: VaultViewModel) { self.model = model }
    public var body: some View {
        Group {
            switch model.screen {
            case .welcome: welcome
            case .create: CreationView(model: model).id(model.contentGeneration)
            case .locked: UnlockView(model: model).id(model.contentGeneration)
            case .unlocked: VaultBrowserView(model: model)
            }
        }
        .frame(
            minWidth: model.screen == .unlocked ? 880 : 640,
            maxWidth: model.screen == .unlocked ? .infinity : 640,
            minHeight: model.screen == .unlocked ? 600 : 480,
            maxHeight: model.screen == .unlocked ? .infinity : 480
        )
        .foregroundStyle(VaultStyle.ink)
        .tint(VaultStyle.copper)
        .background(VaultStyle.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let notice = model.noticeMessage {
                    HStack {
                        Text(notice).font(.callout)
                        Spacer()
                        Button { model.noticeMessage = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("Dismiss status")
                    }.padding(12).background(.tint.opacity(0.08))
                }
                if let error = model.errorMessage {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(error).font(.callout).textSelection(.disabled)
                        Spacer()
                        Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("Dismiss error")
                    }.padding(12).background(.orange.opacity(0.09))
                }
                if model.isBusy {
                    HStack { ProgressView().controlSize(.small); Text(model.activity).font(.callout); Spacer() }
                        .padding(10).background(.bar)
                }
            }
        }
        .sheet(item: $model.passphraseDraft) { draft in
            PassphraseChangeView(model: model, draft: draft).interactiveDismissDisabled()
                .foregroundStyle(VaultStyle.ink).tint(VaultStyle.copper)
                .presentationBackground(VaultStyle.background)
        }
        .sheet(isPresented: $model.isShowingSettings) {
            SecuritySettingsView(model: model, security: model.security)
                .foregroundStyle(VaultStyle.ink).tint(VaultStyle.copper)
                .presentationBackground(VaultStyle.background)
        }
        .sheet(isPresented: Binding(get: { model.tagToRename != nil }, set: { if !$0 { model.discardDraft() } })) {
            TagRenameView(model: model).interactiveDismissDisabled()
                .foregroundStyle(VaultStyle.ink).tint(VaultStyle.copper)
                .presentationBackground(VaultStyle.background)
        }
    }
    private var welcome: some View {
        VStack(spacing: 24) {
            VaultEmblem()
            VStack(spacing: 8) {
                Text("Your secrets. Your file.").font(.system(size: 30, weight: .semibold))
                Text("A private, portable vault that stays with you.").foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                Button("Create New Vault", systemImage: "plus") { model.beginCreation() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button("Open Existing Vault", systemImage: "folder") { Task { await model.chooseOpenVault() } }
                    .controlSize(.large)
            }.disabled(!model.canNavigate)
            Label("Encrypted on your Mac. No account or connection required.", systemImage: "lock.shield")
                .font(.callout).foregroundStyle(.secondary).padding(.top, 16)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }
}

struct VaultEmblem: View {
    var body: some View {
        Image("VaultEmblem", bundle: .main)
            .resizable()
            .scaledToFit()
            .frame(width: 92, height: 92)
            .accessibilityHidden(true)
    }
}

struct CreationView: View {
    @Bindable var model: VaultViewModel
    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var acknowledged = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Create a vault").font(.largeTitle.bold())
            Text("Choose a long, unique passphrase. Spaces and Unicode are supported exactly as you enter them.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("File name") { PrivateTextInput(text: $model.creationName, prompt: "Vault file name").frame(height: 24) }
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Location").font(.subheadline.weight(.medium))
                        Text(model.creationFolder?.path ?? "Choose a folder for the encrypted file")
                            .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Button("Choose Folder…") { Task { await model.chooseCreationFolder() } }
                }
                Divider()
                LabeledContent("Passphrase") { PrivateTextInput(text: $passphrase, prompt: "Master passphrase", secret: true).frame(height: 24) }
                LabeledContent("Confirm") { PrivateTextInput(text: $confirmation, prompt: "Confirm master passphrase", secret: true).frame(height: 24) }
            }
            Toggle("I understand that losing this passphrase means losing access to my vault. There is no recovery or reset.", isOn: $acknowledged)
                .toggleStyle(.checkbox).font(.callout)
            HStack {
                Button("Cancel") { clear(); model.cancelCreation() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Vault") {
                    model.create(passphrase: passphrase, confirmation: confirmation, acknowledged: acknowledged)
                    clear()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!acknowledged || passphrase.isEmpty || confirmation.isEmpty || model.creationFolder == nil)
            }
        }.padding(36).frame(maxWidth: 610).frame(maxWidth: .infinity, maxHeight: .infinity)
            .disabled(model.isBusy).onDisappear { clear() }
    }
    private func clear() { passphrase = ""; confirmation = "" }
}

struct UnlockView: View {
    @Bindable var model: VaultViewModel
    @State private var passphrase = ""
    @State private var focus = UUID()
    var body: some View {
        VStack(spacing: 22) {
            VaultEmblem()
            VStack(spacing: 8) {
                Text("Unlock your vault").font(.largeTitle.bold())
                Text(model.fileURL?.lastPathComponent ?? "Vault").foregroundStyle(.secondary)
            }
            PrivateTextInput(text: $passphrase, prompt: "Master passphrase", secret: true, focusRequest: focus).frame(width: 340, height: 28)
            Button("Unlock Vault") { model.unlock(passphrase: passphrase); passphrase = "" }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                .disabled(passphrase.isEmpty)
            Button("Close Vault") { passphrase = ""; model.lockImmediately(close: true) }.buttonStyle(.link)
            Text("The file and your passphrase are all you need.").font(.callout).foregroundStyle(.secondary)
        }.disabled(model.isBusy).frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { focus = UUID() }
            .onChange(of: model.isBusy) { _, busy in
                if !busy { focus = UUID() }
            }
            .onDisappear { passphrase = "" }
    }
}
