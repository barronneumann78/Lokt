import SwiftUI
import UIKit

/// UIKit-backed numeric cell for the logger's set grid — SwiftUI's TextField
/// can't reliably select-on-focus or move first responder field-to-field in
/// one tap, so set cells use a real UITextField:
/// - the padded cell IS the text field (insets, not wrapper padding), so a
///   tap anywhere in the cell lands focus natively — including with the
///   keyboard already up (no double-tap trap);
/// - focusing selects the existing text, so typing replaces it;
/// - carries the Use Last / Next / Done keyboard toolbar (SwiftUI's keyboard
///   toolbar doesn't attach to UIKit first responders).
/// `TrackerTextField` remains the styled field for every non-set input.
struct LoggerNumericField: UIViewRepresentable {
    let text: String
    let placeholder: String
    let keyboard: UIKeyboardType
    let isActiveStyle: Bool
    let showsUseLast: Bool
    let primaryActionTitle: String
    let isFocused: Bool
    let onTextChange: (String) -> Void
    /// true = became first responder, false = resigned.
    let onFocusChange: (Bool) -> Void
    let onUseLast: () -> Void
    /// Moves focus to the next field; returns false when there is none
    /// (the field then dismisses the keyboard itself).
    let onAdvance: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> LoggerInsetTextField {
        let field = LoggerInsetTextField()
        field.delegate = context.coordinator
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.font = UIFont.monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.inputAccessoryView = context.coordinator.makeToolbar()
        context.coordinator.textField = field
        return field
    }

    func updateUIView(_ field: LoggerInsetTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if field.text != text {
            field.text = text
        }
        if field.keyboardType != keyboard {
            field.keyboardType = keyboard
        }

        // Set through the desired-color slot: the UIAppearance text-input
        // proxies (AppChrome) re-apply on window attach and would clobber a
        // plain textColor set before insertion.
        field.desiredTextColor = UIColor(isActiveStyle ? AppTheme.primary : AppTheme.textPrimary)
        field.desiredTintColor = UIColor(AppTheme.primary)
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(AppTheme.textSecondary)]
        )

        coordinator.updateToolbar(showsUseLast: showsUseLast, primaryTitle: primaryActionTitle)

        // Programmatic focus (Next advance, check-tap on an empty set). The
        // tap path never comes through here — UIKit already moved first
        // responder before SwiftUI hears about it.
        if isFocused && !field.isFirstResponder {
            DispatchQueue.main.async { [weak field] in
                guard let field, field.window != nil,
                      coordinator.parent.isFocused, !field.isFirstResponder else { return }
                field.becomeFirstResponder()
            }
        }
        // No explicit resign on !isFocused: a focus handoff lets the next
        // field's becomeFirstResponder do it, and local dismissals (Done,
        // final Next) resign directly in the coordinator.
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: LoggerNumericField
        weak var textField: LoggerInsetTextField?

        private let toolbar = UIToolbar(
            frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44)
        )
        private var toolbarShowsUseLast: Bool?
        private var toolbarPrimaryTitle: String?

        init(parent: LoggerNumericField) {
            self.parent = parent
        }

        // MARK: Toolbar (Use Last / Next|Done / Done)

        func makeToolbar() -> UIToolbar {
            toolbar.tintColor = UIColor(AppTheme.textPrimary)
            toolbar.autoresizingMask = .flexibleWidth
            return toolbar
        }

        func updateToolbar(showsUseLast: Bool, primaryTitle: String) {
            guard showsUseLast != toolbarShowsUseLast || primaryTitle != toolbarPrimaryTitle else {
                return
            }
            toolbarShowsUseLast = showsUseLast
            toolbarPrimaryTitle = primaryTitle

            var items: [UIBarButtonItem] = []
            if showsUseLast {
                items.append(UIBarButtonItem(
                    title: "Use Last",
                    style: .plain,
                    target: self,
                    action: #selector(useLastTapped)
                ))
            }
            items.append(UIBarButtonItem(systemItem: .flexibleSpace))
            items.append(UIBarButtonItem(
                title: primaryTitle,
                style: .plain,
                target: self,
                action: #selector(primaryTapped)
            ))
            items.append(UIBarButtonItem(systemItem: .fixedSpace))
            items.append(UIBarButtonItem(
                title: "Done",
                style: .plain,
                target: self,
                action: #selector(doneTapped)
            ))
            toolbar.items = items
        }

        @objc private func useLastTapped() {
            parent.onUseLast()
        }

        @objc private func primaryTapped() {
            if !parent.onAdvance() {
                textField?.resignFirstResponder()
            }
        }

        @objc private func doneTapped() {
            textField?.resignFirstResponder()
        }

        // MARK: UITextFieldDelegate

        @objc func editingChanged(_ field: UITextField) {
            parent.onTextChange(field.text ?? "")
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            parent.onFocusChange(true)

            // Select the existing text so typing replaces it ("135" → tap →
            // "140", no backspacing). Deferred a runloop: UIKit places the
            // caret after didBegin and would stomp an immediate selection.
            DispatchQueue.main.async { [weak field] in
                guard let field, field.isFirstResponder else { return }
                field.selectedTextRange = field.textRange(
                    from: field.beginningOfDocument,
                    to: field.endOfDocument
                )
            }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            // Deferred: on a field→field handoff the next didBegin fires in
            // the same runloop turn, and its focus write must win — the
            // parent only clears focus if it still points at this field.
            let parentAtEnd = parent
            DispatchQueue.main.async {
                parentAtEnd.onFocusChange(false)
            }
        }
    }
}

/// UITextField whose insets make the WHOLE padded cell the native hit target,
/// and whose colors survive the UIAppearance text-input proxies re-applying
/// at window attach.
final class LoggerInsetTextField: UITextField {
    var textInsets = UIEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)

    var desiredTextColor: UIColor? {
        didSet { textColor = desiredTextColor }
    }

    var desiredTintColor: UIColor? {
        didSet { tintColor = desiredTintColor }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let desiredTextColor { textColor = desiredTextColor }
        if let desiredTintColor { tintColor = desiredTintColor }
    }

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: textInsets)
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: textInsets)
    }

    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: textInsets)
    }

    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.height += textInsets.top + textInsets.bottom
        return size
    }
}
