import SwiftUI
import UIKit

/// Keyboard dismissal, app-wide (owner feedback on build 3: "you can't get the
/// keyboard away once it's up"). Number pads have no Return key and multi-line
/// fields turn Return into a newline, so every screen with inputs carries
/// explicit ways down — the same three, applied per screen:
/// - `.keyboardDoneBar()`: a Done button above the keyboard, on screens with a
///   number-pad or multi-line field. (The logger's UIKit set cells carry their
///   own Use Last / Next / Done accessory toolbar — see `LoggerNumericField`.)
/// - `.scrollDismissesKeyboard(.interactively)` on the scroll view that hosts
///   the inputs — the native drag-down.
/// - `.dismissKeyboardOnTap()`: a tap on anything that is NOT a text input
///   resigns the first responder without swallowing the tap — buttons, rows and
///   fields all keep working, and tapping another field moves focus. Not used
///   in the logger, where the pinned COMPLETE SET and the row buttons must keep
///   the keyboard up for the focus hand-off.
enum KeyboardDismiss {
    /// Resigns whatever is first responder — SwiftUI and UIKit fields alike.
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

extension View {
    /// Done above the keyboard. One per screen: SwiftUI merges keyboard
    /// toolbar items up the hierarchy, so nesting would duplicate the button.
    func keyboardDoneBar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("Done") {
                    KeyboardDismiss.dismiss()
                }
                .font(.body.weight(.semibold))
                .tint(AppTheme.textPrimary)
            }
        }
    }

    /// Tap anywhere that isn't a text input to drop the keyboard. Attach once
    /// at the screen root.
    func dismissKeyboardOnTap() -> some View {
        background(KeyboardDismissTapInstaller())
    }
}

/// Zero-footprint view that hangs a tap recognizer on the screen's hosting
/// root (the nearest view controller's view) for as long as the screen is on
/// screen. UIKit-level on purpose: `cancelsTouchesInView = false` lets every
/// tap reach its SwiftUI target untouched (a button tap both dismisses and
/// fires), and the delegate declines touches that land on a text input, so a
/// tap into another field moves focus instead of dropping it. Scoped to that
/// root, the recognizer never fires for a sheet above the screen, the tab bar,
/// the navigation bar, or another tab.
private struct KeyboardDismissTapInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView {
        InstallerView()
    }

    func updateUIView(_ uiView: InstallerView, context: Context) { }

    final class InstallerView: UIView, UIGestureRecognizerDelegate {
        private var recognizer: UITapGestureRecognizer?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.cancelsTouchesInView = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            recognizer = tap
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        deinit {
            detach()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            guard window != nil, let recognizer, let root = hostRootView else { return }
            root.addGestureRecognizer(recognizer)
        }

        private func detach() {
            guard let recognizer, let host = recognizer.view else { return }
            host.removeGestureRecognizer(recognizer)
        }

        /// The nearest ancestor that is a view controller's root view.
        private var hostRootView: UIView? {
            var view = superview
            while let current = view {
                if current.next is UIViewController {
                    return current
                }
                view = current.superview
            }
            return nil
        }

        @objc private func handleTap() {
            KeyboardDismiss.dismiss()
        }

        // MARK: UIGestureRecognizerDelegate

        /// Touches on a text input (or inside one — an editing UITextField
        /// hosts its field editor as a subview) are the field's own business.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView || current is (any UITextInput) {
                    return false
                }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
