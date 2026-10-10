import AppKit
import SwiftUI

/// AppKit inputs avoid a plaintext undo history and system writing/spelling services.
struct PrivateTextInput: NSViewRepresentable {
    @Binding var text: String
    var prompt: String = ""
    var secret = false
    var focusRequest: UUID?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField = secret ? FocusSecureField() : FocusTextField()
        field.placeholderString = prompt
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = context.coordinator
        field.setAccessibilityLabel(prompt)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        let wasEnabled = field.isEnabled
        field.isEnabled = context.environment.isEnabled
        if let request = focusRequest,
           context.coordinator.lastFocusRequest != request || (!wasEnabled && field.isEnabled) {
            context.coordinator.lastFocusRequest = request
            (field as? any FocusRequestingField)?.requestFocus()
        }
    }
    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        field.delegate = nil
        if let editor = field.currentEditor() as? NSTextView {
            editor.undoManager?.removeAllActions()
            editor.string = ""
        }
        field.stringValue = ""
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var lastFocusRequest: UUID?
        var parent: PrivateTextInput
        init(_ parent: PrivateTextInput) { self.parent = parent }
        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let editor = field.currentEditor() as? NSTextView else { return }
            configurePrivateEditor(editor)
        }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
    }
}

struct PrivateTextArea: NSViewRepresentable {
    @Binding var text: String
    var label: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        let editor = NSTextView()
        configurePrivateEditor(editor)
        editor.isRichText = false
        editor.importsGraphics = false
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.autoresizingMask = [.width]
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel(label)
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text { editor.string = text }
        editor.isEditable = context.environment.isEnabled
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if let editor = scroll.documentView as? NSTextView {
            editor.delegate = nil; editor.undoManager?.removeAllActions(); editor.string = ""
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PrivateTextArea
        init(_ parent: PrivateTextArea) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { parent.text = editor.string }
        }
    }
}

@MainActor private func configurePrivateEditor(_ editor: NSTextView) {
    editor.allowsUndo = false
    editor.undoManager?.removeAllActions()
    editor.isAutomaticSpellingCorrectionEnabled = false
    editor.isContinuousSpellCheckingEnabled = false
    editor.isGrammarCheckingEnabled = false
    editor.isAutomaticTextReplacementEnabled = false
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.isAutomaticLinkDetectionEnabled = false
    editor.isAutomaticDataDetectionEnabled = false
    editor.isAutomaticTextCompletionEnabled = false
    if #available(macOS 15.0, *) { editor.writingToolsBehavior = .none }
}

@MainActor private protocol FocusRequestingField: AnyObject {
    func requestFocus()
}

@MainActor private final class FocusTextField: NSTextField, FocusRequestingField {
    private var pendingFocus = false
    func requestFocus() { pendingFocus = true; applyFocus() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); applyFocus() }
    private func applyFocus() {
        guard pendingFocus, window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pendingFocus, self.isEnabled, let window = self.window else { return }
            if window.makeFirstResponder(self) { self.pendingFocus = false }
        }
    }
}

@MainActor private final class FocusSecureField: NSSecureTextField, FocusRequestingField {
    private var pendingFocus = false
    func requestFocus() { pendingFocus = true; applyFocus() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); applyFocus() }
    private func applyFocus() {
        guard pendingFocus, window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pendingFocus, self.isEnabled, let window = self.window else { return }
            if window.makeFirstResponder(self) { self.pendingFocus = false }
        }
    }
}
