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
    }
#endif
