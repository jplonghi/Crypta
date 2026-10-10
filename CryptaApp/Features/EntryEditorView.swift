import SwiftUI
import CryptaCore

struct EntryEditorView: View {
    @Bindable var model: VaultViewModel
    @Bindable var draft: EntryDraft
    @State private var showText = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(draft.isNew ? "New \(draft.kind.title.lowercased())" : "Edit entry").font(.title2.bold())
                    Text("Save to keep changes. Automatic lock discards unsaved drafts.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    line("Title", text: $draft.title)
                    Button { draft.isFavorite.toggle() } label: {
                        Label(draft.isFavorite ? "Favorited" : "Add to Favorites", systemImage: draft.isFavorite ? "star.fill" : "star")
                    }.buttonStyle(.borderless)
                    Divider()
                    fields
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags").font(.callout.weight(.medium))
                        TagFlowLayout {
                            ForEach(Array(draft.tags.enumerated()), id: \.offset) { index, tag in
                                HStack(spacing: 6) {
                                    Text(tag).font(.caption)
                                    Button { draft.tags.remove(at: index) } label: { Image(systemName: "xmark") }
                                        .buttonStyle(.borderless).accessibilityLabel("Remove tag \(tag)")
                                }.padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(VaultStyle.field, in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(VaultStyle.line))
                            }
                        }
                        HStack {
                            PrivateTextInput(text: $draft.pendingTag, prompt: "Add or find a tag").frame(height: 24)
                            Button("Add Tag") { draft.addTag(draft.pendingTag) }
                                .disabled(VaultTags.key(draft.pendingTag).isEmpty || draft.tags.count >= VaultTags.maximumCount)
                        }
                        TagFlowLayout {
                            ForEach(Array(model.tagSuggestions(for: draft).prefix(6)), id: \.self) { tag in
                                Button { draft.addTag(tag) } label: { Label(tag, systemImage: "number") }
                                    .buttonStyle(.borderless).disabled(draft.tags.count >= VaultTags.maximumCount)
                                    .accessibilityLabel("Add tag \(tag)")
                            }
                        }
                    }
                }.padding(24)
            }
            Divider()
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).padding(.horizontal, 24).padding(.top, 12)
            }
            HStack {
                Button("Cancel") { model.discardDraft() }.keyboardShortcut(.cancelAction)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small); Text("Encrypting…").font(.callout) }
                Button("Save Entry") { model.saveDraft() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!model.canSave)
            }.padding(20)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VaultStyle.background).disabled(model.isBusy)
    }
    @ViewBuilder private var fields: some View {
        switch draft.kind {
        case .credential:
            line("Username", text: $draft.username)
            line("Password", text: $draft.password, secret: true)
            line("Website URL", text: $draft.websiteURL)
            privateArea("Notes", text: $draft.notes)
        case .apiToken:
            line("Service", text: $draft.service)
            line("Key / token", text: $draft.token, secret: true)
            Picker("Environment", selection: $draft.environment) {
                Text("Development").tag(TokenEnvironment.development)
                Text("Testing").tag(TokenEnvironment.testing)
                Text("Production").tag(TokenEnvironment.production)
            }
            Toggle("Has an expiration date", isOn: $draft.expires)
            if draft.expires { DatePicker("Expiration", selection: $draft.expiration) }
            privateArea("Notes", text: $draft.notes)
        case .secureNote: privateArea("Content", text: $draft.content)
        case .customSecret:
            ForEach($draft.customFields, id: \.id) { $field in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        PrivateTextInput(text: $field.name, prompt: "Field name").frame(height: 24)
                        Button("Remove field", systemImage: "trash") { draft.customFields.removeAll { $0.id == field.id } }.labelStyle(.iconOnly)
                    }
                    Toggle("Hide value by default", isOn: $field.isSecret).toggleStyle(.checkbox)
                    PrivateTextInput(text: $field.value, prompt: "Field value", secret: field.isSecret)
                        .id(field.isSecret).frame(height: 24)
                }.vaultField()
            }
            Button("Add Field", systemImage: "plus") { draft.customFields.append(CustomField(name: "")) }
                .disabled(draft.customFields.count >= 100)
        }
    }
    private func line(_ label: String, text: Binding<String>, secret: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.callout.weight(.medium))
            PrivateTextInput(text: text, prompt: label, secret: secret).frame(height: 24)
        }
    }
    private func privateArea(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.callout.weight(.medium))
                Spacer()
                if !draft.isNew { Button(showText ? "Hide text" : "Edit text") { showText.toggle() } }
            }
            if showText || draft.isNew { PrivateTextArea(text: text, label: label).frame(height: 150) }
            else { Text("Content hidden. Choose Edit text to view and change it.").font(.callout).foregroundStyle(.secondary) }
        }
    }
}

struct TagRenameView: View {
    @Bindable var model: VaultViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Rename tag").font(.title2.bold())
            Text("Updates every item using this tag. An existing name merges the tags.").font(.callout).foregroundStyle(.secondary)
            PrivateTextInput(text: $model.replacementTag, prompt: "Tag name").frame(height: 24)
            if let error = model.errorMessage { Text(error).font(.callout).foregroundStyle(.orange) }
            HStack {
                Button("Cancel") { model.discardDraft() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Rename Tag") { model.saveDraft() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!model.canSave)
            }
        }.padding(24).frame(width: 430).disabled(model.isBusy)
    }
}
