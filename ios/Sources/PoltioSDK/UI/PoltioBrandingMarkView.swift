#if canImport(UIKit)
    import UIKit

    /// Small "Poltio" wordmark shown at the bottom of the expanded card trigger, toggled by
    /// `PoltioOverlayOptions.showLogo` (`floating-show-logo`, default true).
    final class PoltioBrandingMarkView: UIView {
        private let dot = UIView()
        private let label = UILabel()

        private enum Constants {
            static let dotSize: CGFloat = 6
            static let spacing: CGFloat = 5
            static let fontSize: CGFloat = 10.5
            static let brandBlue = UIColor(red: 0.0, green: 0.62, blue: 0.93, alpha: 1.0)
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            setup()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }

        private func setup() {
            isUserInteractionEnabled = false

            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.backgroundColor = Constants.brandBlue
            dot.layer.cornerRadius = Constants.dotSize / 2
            addSubview(dot)

            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = "Poltio"
            label.font = .systemFont(ofSize: Constants.fontSize, weight: .semibold)
            label.textColor = .secondaryLabel
            addSubview(label)

            NSLayoutConstraint.activate([
                dot.leadingAnchor.constraint(equalTo: leadingAnchor),
                dot.centerYAnchor.constraint(equalTo: centerYAnchor),
                dot.widthAnchor.constraint(equalToConstant: Constants.dotSize),
                dot.heightAnchor.constraint(equalToConstant: Constants.dotSize),

                label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: Constants.spacing),
                label.trailingAnchor.constraint(equalTo: trailingAnchor),
                label.topAnchor.constraint(equalTo: topAnchor),
                label.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        /// Applies the widget's custom font family, if any, so the branding mark matches the rest
        /// of the card trigger instead of always using the system font, and a wordmark color that
        /// reads on the card's own background (`.secondaryLabel` follows the system appearance, not
        /// the card, and all but disappears on a dark one).
        func configure(with options: PoltioOverlayOptions) {
            label.font = options.resolvedFont(size: Constants.fontSize, weight: .semibold)
            label.textColor = Self.wordmarkColor(on: options.resolvedBgColor)
        }

        /// Light text on a dark background, dark text on a light one.
        static func wordmarkColor(on background: UIColor) -> UIColor {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard background.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
                return .secondaryLabel
            }
            let brightness = 0.299 * red + 0.587 * green + 0.114 * blue
            return brightness < 0.6 ? UIColor(white: 1, alpha: 0.75) : UIColor(white: 0, alpha: 0.5)
        }
    }
#endif
