import SwiftUI
import CryptaCore

struct VaultBrowserView: View {
    @Bindable var model: VaultViewModel
    @State private var confirmingDelete = false
    @State private var tagsExpanded = true
    @State private var tagToRemove: String?
    var body: some View {
        NavigationSplitView {
            List {
                Button { model.navigate(to: .all) } label: {
                    sidebarLabel("All Items", symbol: "square.stack.3d.up", count: model.vault?.entries.count ?? 0)
                }.buttonStyle(.plain)
                    .listRowBackground(model.filter == .all && model.selectedTags.isEmpty ? VaultStyle.selection : Color.clear)
                Button { model.navigate(to: .favorites) } label: {
                    sidebarLabel("Favorites", symbol: "star", count: model.favoriteCount)
                }.buttonStyle(.plain)
                    .listRowBackground(model.filter == .favorites ? VaultStyle.selection : Color.clear)
                Section(isExpanded: $tagsExpanded) {
                    ForEach(model.usedTags, id: \.name) { tag in
                        Button { model.toggleTagFilter(tag.name) } label: {
                            sidebarLabel(tag.name, symbol: "number", count: tag.count)
                        }.buttonStyle(.plain)
                            .listRowBackground(model.selectedTags.contains(VaultTags.key(tag.name)) ? VaultStyle.selection : Color.clear)
                            .accessibilityAddTraits(model.selectedTags.contains(VaultTags.key(tag.name)) ? .isSelected : [])
                            .contextMenu {
                                Button("Rename Tag…") { model.beginTagRename(tag.name) }
                                Button("Remove Tag from All Items…", role: .destructive) { tagToRemove = tag.name }
                            }
                    }
                } header: { Text("Tags") }
            }
            .listStyle(.sidebar)
            .disabled(!model.canNavigate)
            .accessibilityLabel("Items, Favorites, and tags")
            .scrollContentBackground(.hidden)
            .background(VaultStyle.sidebar)
            .navigationSplitViewColumnWidth(min: 175, ideal: 200)
            .safeAreaInset(edge: .top, spacing: 0) {
                Text("CRYPTA").font(.headline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
        } content: {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    PrivateTextInput(text: $model.search, prompt: "Search entries", focusRequest: model.searchFocusRequest).frame(height: 24)
                    if !model.search.isEmpty {
                        Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Clear search")
                    }
                }.padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 12)
                HStack {
                    Text(model.filter == .favorites ? "Favorites" : "Items")
                    Spacer()
                    Label("Name", systemImage: "arrow.up").labelStyle(.titleAndIcon)
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.bottom, 8)
                if !model.selectedTags.isEmpty {
                    HStack {
                        Text("Matching all \(model.selectedTags.count) selected tags").font(.caption)
                        Spacer()
                        Button("Clear") { model.selectedTags = [] }.buttonStyle(.borderless)
                    }.padding(.horizontal, 14).padding(.bottom, 8)
                }
                if model.entries.isEmpty {
                    ContentUnavailableView(model.vault?.entries.isEmpty == true ? "No items yet" : "No matching items",
                                           systemImage: "tray", description: Text(model.vault?.entries.isEmpty == true ? "Add an item to this vault." : "Try different tags or search terms."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { scroll in
                        List(model.entries, id: \.id, selection: $model.selectedID) { entry in
                            HStack(spacing: 10) {
                                EntryEmblem(symbol: EntryKind(rawValue: entry.type)?.symbol ?? "key")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title).font(.body.weight(.medium)).lineLimit(1)
                                    Text(EntryKind(rawValue: entry.type)?.title ?? "Entry").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Button { model.toggleFavorite(entry.id) } label: {
                                    Image(systemName: entry.isFavorite ? "star.fill" : "star")
                                }.buttonStyle(.borderless).foregroundStyle(VaultStyle.copper)
                                    .accessibilityLabel(entry.isFavorite ? "Remove \(entry.title) from Favorites" : "Add \(entry.title) to Favorites")
                                    .disabled(!model.canNavigate)
                            }.accessibilityElement(children: .contain)
                                .padding(.vertical, 7).tag(entry.id).id(entry.id)
                                .listRowSeparator(.hidden)
                                .listRowBackground(model.selectedID == entry.id ? VaultStyle.selection : Color.clear)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .onAppear {
                            DispatchQueue.main.async {
                                if let selectedID = model.selectedID { scroll.scrollTo(selectedID, anchor: .center) }
                            }
                        }
                    }
                    // Native List caches clipped insertion heights; rebuilding its reader also refreshes scroll targets.
                    .id(model.entries.map(\.id))
                }
                HStack { Text(model.entries.count == 1 ? "1 entry" : "\(model.entries.count) entries"); Spacer(); Text(model.editor == nil ? "Saved encrypted" : "Unsaved draft") }
                    .font(.caption).foregroundStyle(.secondary).padding(14)
            }.disabled(!model.canNavigate)
                .background(VaultStyle.library).navigationSplitViewColumnWidth(min: 250, ideal: 280)
        } detail: {
            if let draft = model.editor {
                EntryEditorView(model: model, draft: draft).id(draft.id)
            } else if let entry = model.selectedEntry {
                EntryDetailView(model: model, entry: entry)
                    .id("\(model.contentGeneration)-\(entry.id)")
            } else {
                ContentUnavailableView("Your private space", systemImage: "lock.shield", description: Text("Select an entry to view its details."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(VaultStyle.background)
            }
        }
        .navigationTitle(model.vault?.name ?? "Crypta")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("New Item", systemImage: "plus") { model.addEntry() }
                    .labelStyle(.titleAndIcon).disabled(!model.canNavigate).help("New Item (⌘N)")
                Button("Edit", systemImage: "square.and.pencil") { model.editSelected() }
                    .labelStyle(.titleAndIcon).disabled(!model.canNavigate || model.selectedEntry == nil)
                    .help("Edit Selected Item (⌘E)")
                Button("Delete", systemImage: "trash") { confirmingDelete = true }
                    .labelStyle(.titleAndIcon).disabled(!model.canNavigate || model.selectedEntry == nil)
                    .help("Delete Selected Item")
                Button { model.requestLock() } label: {
                    Label("Lock Vault", systemImage: "lock").labelStyle(.titleAndIcon)
                }.help("Lock Vault (⇧⌘L)")
            }
        }
        .confirmationDialog("Delete this entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Entry", role: .destructive) { model.deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This saves the deletion to the encrypted vault. It cannot be undone.") }
        .confirmationDialog("Remove this tag from every item?", isPresented: Binding(get: { tagToRemove != nil }, set: { if !$0 { tagToRemove = nil } }), titleVisibility: .visible) {
            Button("Remove Tag", role: .destructive) {
                if let tagToRemove { model.removeTag(tagToRemove) }
                tagToRemove = nil
            }
            Button("Cancel", role: .cancel) { tagToRemove = nil }
        } message: { Text("Items are kept. The tag is removed from all affected items in one encrypted save.") }
        .onChange(of: model.selectedTags) { _, _ in
            if !model.entries.contains(where: { $0.id == model.selectedID }) { model.selectedID = nil }
        }
        .onChange(of: model.filter) { _, _ in
            if !model.entries.contains(where: { $0.id == model.selectedID }) { model.selectedID = nil }
        }
        .onChange(of: model.search) { _, _ in
            if !model.entries.contains(where: { $0.id == model.selectedID }) { model.selectedID = nil }
        }
    }
    private func sidebarLabel(_ title: String, symbol: String, count: Int) -> some View {
        HStack {
            Label(title, systemImage: symbol).lineLimit(1)
            Spacer()
            Text(count.formatted()).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }.contentShape(Rectangle())
    }
}

struct EntryDetailView: View {
    let model: VaultViewModel
    let entry: VaultEntry
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    EntryEmblem(symbol: EntryKind(rawValue: entry.type)?.symbol ?? "key", size: 50)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(EntryKind(rawValue: entry.type)?.title ?? "Entry").font(.caption).foregroundStyle(.secondary)
                        Text(entry.title).font(.system(size: 24, weight: .semibold)).textSelection(.disabled)
                    }
                }
                VStack(spacing: 0) {
                switch entry.fields {
                case .credential(let value):
                    DetailValue(model: model, label: "Username", value: value.username)
                    SecretValue(model: model, label: "Password", value: value.password)
                    DetailValue(model: model, label: "Website", value: value.websiteURL)
                    if !value.notes.isEmpty { SecretValue(model: model, label: "Notes", value: value.notes) }
                case .apiToken(let value):
                    DetailValue(model: model, label: "Service", value: value.service)
                    SecretValue(model: model, label: "Key / token", value: value.token)
                    DetailValue(model: model, label: "Environment", value: value.environment.rawValue.capitalized)
                    if let expires = value.expiresAt { DetailValue(model: model, label: "Expires", value: date(expires)) }
                    if !value.notes.isEmpty { SecretValue(model: model, label: "Notes", value: value.notes) }
                case .secureNote(let value): SecretValue(model: model, label: "Content", value: value.content)
                case .customSecret(let value):
                    ForEach(value.customFields, id: \.id) { field in
                        if field.isSecret { SecretValue(model: model, label: field.name, value: field.value) }
                        else { DetailValue(model: model, label: field.name, value: field.value) }
                    }
                }
                }
                .background(VaultStyle.field, in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(VaultStyle.line))
                if !entry.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags").font(.caption).foregroundStyle(.secondary)
                        TagFlowLayout {
                            ForEach(Array(entry.tags.enumerated()), id: \.offset) { _, tag in
                                Text(tag).font(.caption).foregroundStyle(.secondary)
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(VaultStyle.background, in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(VaultStyle.line))
                            }
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("Created \(date(entry.createdAt))")
                    Text("Modified \(date(entry.modifiedAt))")
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
        }.background(VaultStyle.background)
    }
    private func date(_ ms: Int64) -> String {
        Date(timeIntervalSince1970: Double(ms) / 1000).formatted(date: .abbreviated, time: .shortened)
    }
}

struct DetailValue: View {
    let model: VaultViewModel
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") { model.copySecret(value) }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(VaultStyle.copper)
                    .accessibilityLabel("Copy \(label)").disabled(model.isBusy || value.isEmpty)
            }
            Text(value.isEmpty ? "—" : value).textSelection(.disabled)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(VaultStyle.line).frame(height: 1) }
    }
}

struct SecretValue: View {
    let model: VaultViewModel
    let label: String
    let value: String
    @State private var revealed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") { model.copySecret(value) }
                    .buttonStyle(.borderless).accessibilityLabel("Copy \(label)").disabled(model.isBusy)
                Button(revealed ? "Hide" : "Reveal", systemImage: revealed ? "eye.slash" : "eye") { revealed.toggle() }
                    .buttonStyle(.borderless).accessibilityLabel("\(revealed ? "Hide" : "Reveal") \(label)")
            }
            .font(.caption).foregroundStyle(VaultStyle.copper)
            if revealed {
                Text(value.isEmpty ? "—" : value).font(.system(.body, design: .monospaced)).textSelection(.disabled)
            } else {
                Text("••••••••••••").font(.system(.body, design: .monospaced)).accessibilityLabel("Hidden value")
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(VaultStyle.line).frame(height: 1) }
    }
}
