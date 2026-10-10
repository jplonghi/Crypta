import AppKit
import UniformTypeIdentifiers

@MainActor public extension VaultViewModel {
    func chooseCreationFolder() async {
        guard canNavigate, screen == .create else { return }
        let panel = Self.folderPanel()
        panel.message = "Choose where to keep the encrypted vault. Crypta also needs this folder for encrypted saves and file locks."
        panel.prompt = "Choose Folder"
        if await Self.present(panel) == .OK, let url = panel.url { setCreationFolder(url) }
    }

    func chooseOpenVault() async {
        guard canNavigate, vault == nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "crypta") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a portable .crypta vault."
        if await Self.present(panel) == .OK, let url = panel.url { await openVaultURL(url) }
    }

    func openVaultURL(_ url: URL) async {
        guard canNavigate, vault == nil else {
            errorMessage = "Finish the current edit and close this vault before opening another file."
            return
        }
        let panel = Self.folderPanel()
        panel.directoryURL = url.deletingLastPathComponent()
        panel.message = "Grant access to the folder containing \(url.lastPathComponent). Crypta creates only encrypted save files and writer locks there. Select this containing folder to continue."
        panel.prompt = "Grant Folder Access"
        if await Self.present(panel) == .OK, let folder = panel.url { prepareOpen(url, folder: folder) }
    }

    private static func folderPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel
    }
    private static func present(_ panel: NSOpenPanel) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            } else { panel.begin { continuation.resume(returning: $0) } }
        }
    }
}
