#if canImport(UIKit)
    import UIKit

    /// Native floating card trigger view supporting collapsed (rounded edge tab with sparkle & chevron)
    /// and expanded (floating rounded card with close button, title, description, and action button) states.
    public final class PoltioFloatingCardTriggerView: UIView, PoltioTriggerPresentable {
        /// Visual states of the floating card trigger.
        public enum TriggerState {
            case collapsed
            case expanded
        }

        private let widget: PoltioWidgetResponse
        private let onOpenWidget: () -> Void

        public private(set) var currentState: TriggerState

        // Container views
        private let collapsedContainer = UIView()
        private let expandedContainer = UIView()

        // Subviews for collapsed state
        private let collapsedSparkleIcon = PoltioSparkleIconView()
        private let collapsedChevron = UIImageView()

        // Subviews for expanded state
        private let expandedSparkleIcon = PoltioSparkleIconView()
        private let closeButton = UIButton(type: .custom)
        private let titleLabel = UILabel()
        private let descLabel = UILabel()
        private let actionButton = UIButton(type: .custom)

        // Dimensions constraints
        private var widthConstraint: NSLayoutConstraint!
        private var heightConstraint: NSLayoutConstraint!

        private static let collapsedWidth: CGFloat = 44
        private static let collapsedHeight: CGFloat = 104
        private static let expandedCardWidth: CGFloat = 290
        private static let expandedCardMargin: CGFloat = 16
        private static let expandedTotalWidth: CGFloat = 290 + 16

        public init(
            widget: PoltioWidgetResponse,
            onOpenWidget: @escaping () -> Void
        ) {
            self.widget = widget
            self.onOpenWidget = onOpenWidget
            currentState = widget.overlayOptions.isInitialActive ? .expanded : .collapsed
            super.init(frame: .zero)

            setupView()
            applyState(currentState, animated: false)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func setupView() {
            translatesAutoresizingMaskIntoConstraints = false
            backgroundColor = .clear
            clipsToBounds = false

            let initialWidth = (currentState == .expanded) ? Self.expandedTotalWidth : Self.collapsedWidth
            let initialHeight = (currentState == .expanded) ? 230 : Self.collapsedHeight

            widthConstraint = widthAnchor.constraint(equalToConstant: initialWidth)
            heightConstraint = heightAnchor.constraint(equalToConstant: initialHeight)

            NSLayoutConstraint.activate([
                widthConstraint,
                heightConstraint,
            ])

            setupCollapsedContainer()
            setupExpandedContainer()

            // Gestures
            let tapCollapsed = UITapGestureRecognizer(target: self, action: #selector(handleCollapsedTap))
            collapsedContainer.addGestureRecognizer(tapCollapsed)

            let tapExpanded = UITapGestureRecognizer(target: self, action: #selector(handleExpandedTap))
            expandedContainer.addGestureRecognizer(tapExpanded)

            let swipeToCollapse = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeRight))
            swipeToCollapse.direction = .right
            expandedContainer.addGestureRecognizer(swipeToCollapse)
        }

        // MARK: - Collapsed View Setup

        private func setupCollapsedContainer() {
            collapsedContainer.translatesAutoresizingMaskIntoConstraints = false
            collapsedContainer.backgroundColor = widget.overlayOptions.resolvedBgColor
            collapsedContainer.layer.cornerRadius = 24
            collapsedContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            collapsedContainer.layer.shadowColor = UIColor.black.cgColor
            collapsedContainer.layer.shadowOpacity = 0.20
            collapsedContainer.layer.shadowOffset = CGSize(width: -2, height: 3)
            collapsedContainer.layer.shadowRadius = 8
            collapsedContainer.isUserInteractionEnabled = true

            // Top sparkle icon
            collapsedSparkleIcon.translatesAutoresizingMaskIntoConstraints = false
            collapsedContainer.addSubview(collapsedSparkleIcon)

            // Bottom left chevron
            collapsedChevron.translatesAutoresizingMaskIntoConstraints = false
            collapsedChevron.contentMode = .scaleAspectFit
            collapsedChevron.tintColor = widget.overlayOptions.resolvedIconColor
            let chevronConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            collapsedChevron.image = UIImage(systemName: "chevron.left", withConfiguration: chevronConfig)
            collapsedContainer.addSubview(collapsedChevron)

            addSubview(collapsedContainer)

            NSLayoutConstraint.activate([
                collapsedContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
                collapsedContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
                collapsedContainer.widthAnchor.constraint(equalToConstant: Self.collapsedWidth),
                collapsedContainer.heightAnchor.constraint(equalToConstant: Self.collapsedHeight),

                collapsedSparkleIcon.centerXAnchor.constraint(equalTo: collapsedContainer.centerXAnchor),
                collapsedSparkleIcon.topAnchor.constraint(equalTo: collapsedContainer.topAnchor, constant: 14),
                collapsedSparkleIcon.widthAnchor.constraint(equalToConstant: 28),
                collapsedSparkleIcon.heightAnchor.constraint(equalToConstant: 28),

                collapsedChevron.centerXAnchor.constraint(equalTo: collapsedContainer.centerXAnchor),
                collapsedChevron.bottomAnchor.constraint(equalTo: collapsedContainer.bottomAnchor, constant: -16),
                collapsedChevron.widthAnchor.constraint(equalToConstant: 16),
                collapsedChevron.heightAnchor.constraint(equalToConstant: 16),
            ])
        }

        // MARK: - Expanded View Setup

        private func setupExpandedContainer() {
            expandedContainer.translatesAutoresizingMaskIntoConstraints = false
            expandedContainer.backgroundColor = widget.overlayOptions.resolvedBgColor
            expandedContainer.layer.cornerRadius = 24
            expandedContainer.layer.shadowColor = UIColor.black.cgColor
            expandedContainer.layer.shadowOpacity = 0.22
            expandedContainer.layer.shadowOffset = CGSize(width: 0, height: 6)
            expandedContainer.layer.shadowRadius = 14
            expandedContainer.clipsToBounds = false
            expandedContainer.isUserInteractionEnabled = true

            // 1. Top Sparkle Icon
            expandedSparkleIcon.translatesAutoresizingMaskIntoConstraints = false
            expandedContainer.addSubview(expandedSparkleIcon)

            // 2. Top-Right Close Button
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            closeButton.tintColor = widget.overlayOptions.resolvedIconColor
            let xmarkConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: xmarkConfig), for: .normal)
            closeButton.addTarget(self, action: #selector(handleCloseTap), for: .touchUpInside)
            closeButton.accessibilityLabel = "Close Poltio Widget Card"
            expandedContainer.addSubview(closeButton)

            // 3. Title Label
            let titleText = widget.overlayOptions.floatingTitle
                ?? widget.overlayOptions.floatingBoxTextFirst
                ?? "Let us choose together"
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.text = titleText
            titleLabel.font = .systemFont(ofSize: 18, weight: .heavy)
            titleLabel.textColor = widget.overlayOptions.resolvedTextColor
            titleLabel.numberOfLines = 2
            titleLabel.lineBreakMode = .byWordWrapping
            expandedContainer.addSubview(titleLabel)

            // 4. Description Label
            let descText = widget.overlayOptions.floatingDesc
                ?? widget.overlayOptions.floatingBoxTextSecond
                ?? "Let's find your perfect match together"
            descLabel.translatesAutoresizingMaskIntoConstraints = false
            descLabel.text = descText
            descLabel.font = .systemFont(ofSize: 13.5, weight: .medium)
            descLabel.textColor = widget.overlayOptions.resolvedTextColor.withAlphaComponent(0.95)
            descLabel.numberOfLines = 0
            descLabel.lineBreakMode = .byWordWrapping
            expandedContainer.addSubview(descLabel)

            // 5. Action Button ("Start Now")
            let btnText = widget.overlayOptions.floatingButtonText ?? "Start Now"
            actionButton.translatesAutoresizingMaskIntoConstraints = false
            actionButton.backgroundColor = .white
            actionButton.layer.cornerRadius = 20
            actionButton.setTitle(btnText, for: .normal)
            actionButton.setTitleColor(.black, for: .normal)
            actionButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
            actionButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
            actionButton.layer.shadowColor = UIColor.black.cgColor
            actionButton.layer.shadowOpacity = 0.12
            actionButton.layer.shadowOffset = CGSize(width: 0, height: 2)
            actionButton.layer.shadowRadius = 4
            actionButton.addTarget(self, action: #selector(handleActionTap), for: .touchUpInside)
            expandedContainer.addSubview(actionButton)

            addSubview(expandedContainer)

            NSLayoutConstraint.activate([
                expandedContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.expandedCardMargin),
                expandedContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
                expandedContainer.widthAnchor.constraint(equalToConstant: Self.expandedCardWidth),

                // Top icons row
                expandedSparkleIcon.leadingAnchor.constraint(equalTo: expandedContainer.leadingAnchor, constant: 20),
                expandedSparkleIcon.topAnchor.constraint(equalTo: expandedContainer.topAnchor, constant: 18),
                expandedSparkleIcon.widthAnchor.constraint(equalToConstant: 32),
                expandedSparkleIcon.heightAnchor.constraint(equalToConstant: 32),

                closeButton.trailingAnchor.constraint(equalTo: expandedContainer.trailingAnchor, constant: -8),
                closeButton.centerYAnchor.constraint(equalTo: expandedSparkleIcon.centerYAnchor),
                closeButton.widthAnchor.constraint(equalToConstant: 44),
                closeButton.heightAnchor.constraint(equalToConstant: 44),

                // Title
                titleLabel.leadingAnchor.constraint(equalTo: expandedContainer.leadingAnchor, constant: 20),
                titleLabel.trailingAnchor.constraint(equalTo: expandedContainer.trailingAnchor, constant: -20),
                titleLabel.topAnchor.constraint(equalTo: expandedSparkleIcon.bottomAnchor, constant: 12),

                // Description
                descLabel.leadingAnchor.constraint(equalTo: expandedContainer.leadingAnchor, constant: 20),
                descLabel.trailingAnchor.constraint(equalTo: expandedContainer.trailingAnchor, constant: -20),
                descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),

                // Action Button
                actionButton.leadingAnchor.constraint(equalTo: expandedContainer.leadingAnchor, constant: 20),
                actionButton.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 16),
                actionButton.bottomAnchor.constraint(equalTo: expandedContainer.bottomAnchor, constant: -20),
                actionButton.heightAnchor.constraint(equalToConstant: 40),
            ])
        }

        // MARK: - State Management

        public func setState(_ state: TriggerState, animated: Bool) {
            guard currentState != state else { return }
            currentState = state
            applyState(state, animated: animated)
        }

        public func resetToCollapsed(animated: Bool) {
            setState(.collapsed, animated: animated)
        }

        private func applyState(_ state: TriggerState, animated: Bool) {
            let isExpanded = (state == .expanded)
            let targetWidth = isExpanded ? Self.expandedTotalWidth : Self.collapsedWidth

            // Measure height needed for expanded state
            let targetHeight: CGFloat = if isExpanded {
                expandedContainer.systemLayoutSizeFitting(
                    CGSize(width: Self.expandedCardWidth, height: UIView.layoutFittingCompressedSize.height),
                    withHorizontalFittingPriority: .required,
                    verticalFittingPriority: .fittingSizeLevel
                ).height
            } else {
                Self.collapsedHeight
            }

            let effectiveHeight = max(targetHeight, isExpanded ? 210 : Self.collapsedHeight)

            if !animated {
                widthConstraint.constant = targetWidth
                heightConstraint.constant = effectiveHeight
                collapsedContainer.alpha = isExpanded ? 0.0 : 1.0
                expandedContainer.alpha = isExpanded ? 1.0 : 0.0
                collapsedContainer.isHidden = isExpanded
                expandedContainer.isHidden = !isExpanded
                collapsedContainer.transform = .identity
                expandedContainer.transform = .identity
                return
            }

            // Prepare unhidden view before animation
            collapsedContainer.isHidden = false
            expandedContainer.isHidden = false

            layoutIfNeeded()

            UIView.animate(
                withDuration: 0.35,
                delay: 0,
                usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0.5,
                options: [.curveEaseInOut, .allowUserInteraction],
                animations: { [weak self] in
                    guard let self else { return }
                    widthConstraint.constant = targetWidth
                    heightConstraint.constant = effectiveHeight
                    collapsedContainer.alpha = isExpanded ? 0.0 : 1.0
                    expandedContainer.alpha = isExpanded ? 1.0 : 0.0
                    collapsedContainer.transform = isExpanded ? CGAffineTransform(translationX: 30, y: 0) : .identity
                    expandedContainer.transform = isExpanded ? .identity : CGAffineTransform(translationX: 30, y: 0)
                    superview?.layoutIfNeeded()
                },
                completion: { [weak self] _ in
                    guard let self else { return }
                    collapsedContainer.isHidden = (currentState != .collapsed)
                    expandedContainer.isHidden = (currentState != .expanded)
                }
            )
        }

        // MARK: - Actions

        @objc private func handleCollapsedTap() {
            setState(.expanded, animated: true)
        }

        @objc private func handleExpandedTap() {
            onOpenWidget()
        }

        @objc private func handleCloseTap() {
            setState(.collapsed, animated: true)
        }

        @objc private func handleSwipeRight() {
            setState(.collapsed, animated: true)
        }

        @objc private func handleActionTap() {
            onOpenWidget()
        }
    }
#endif
