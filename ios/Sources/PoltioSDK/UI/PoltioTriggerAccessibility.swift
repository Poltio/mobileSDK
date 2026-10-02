#if canImport(UIKit)
    import UIKit

    /// Shared VoiceOver configuration for the floating triggers. Each tappable trigger container is
    /// exposed as a single button element (its visible text as the label), with any secondary
    /// controls nested inside it — close (X), collapse — surfaced as custom actions, since making the
    /// container an accessibility element hides its subviews from VoiceOver.
    enum PoltioTriggerAccessibility {
        /// Fallback label when a trigger has no visible text (e.g. an icon-only collapsed tab).
        static let fallbackLabel = "Poltio widget"
        static let openHint = "Opens the widget."
        static let closeActionName = "Close"
        static let collapseActionName = "Collapse"

        /// Joins the non-empty `parts` (whitespace/newlines collapsed) into a single spoken label.
        static func label(from parts: [String?]) -> String {
            let words = parts
                .compactMap { $0 }
                .joined(separator: " ")
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            return words.isEmpty ? fallbackLabel : words.joined(separator: " ")
        }

        static func configure(
            _ view: UIView,
            label: String,
            hint: String = openHint,
            actions: [UIAccessibilityCustomAction] = []
        ) {
            view.isAccessibilityElement = true
            view.accessibilityTraits = .button
            view.accessibilityLabel = label
            view.accessibilityHint = hint
            view.accessibilityCustomActions = actions.isEmpty ? nil : actions
        }

        /// Builds a custom action whose handler always reports success. Callers must capture `self`
        /// weakly — the action is retained by the view it's attached to.
        static func action(_ name: String, handler: @escaping () -> Void) -> UIAccessibilityCustomAction {
            UIAccessibilityCustomAction(name: name) { _ in
                handler()
                return true
            }
        }

        /// The collapsed → expanded step is a purely visual teaser; with VoiceOver running, activating
        /// a collapsed trigger opens the widget directly instead of requiring a second activation.
        static var shouldSkipExpandStep: Bool {
            UIAccessibility.isVoiceOverRunning
        }
    }
#endif
