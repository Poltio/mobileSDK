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
        private let brandingRow = PoltioBrandingMarkView()

        /// Loads `floatingSvg`/`floatingImg` into the collapsed/expanded icon slots when configured,
        /// falling back to `PoltioSparkleIconView` (created eagerly above) otherwise.
        private var collapsedIconLoader: PoltioTriggerIconLoader?
        private var expandedIconLoader: PoltioTriggerIconLoader?

        // Dimensions constraints
        private var widthConstraint: NSLayoutConstraint!
        private var heightConstraint: NSLayoutConstraint!

        /// Timestamp of the most recent transition into `.expanded`, used to give a brief grace
        /// window before a real host scroll is allowed to auto-collapse the card — otherwise the
        /// very same scroll gesture that revealed it would immediately collapse it again a few
        /// points later.
        private var expandedAt: Date?
        /// Minimum time an expand must have been visible before a host scroll can collapse it.
        private static let scrollCollapseGracePeriod: TimeInterval = 0.4
        /// Kept so `deinit` can cancel this still-pending registration if the threshold was never
        /// crossed — see `PoltioScrollObserver.cancelScrollPast`.
        private var scrollRevealToken: PoltioScrollObserver.ScrollPastToken?

        /// UI layout and styling constants for the collapsed/expanded card trigger.
        private enum Constants {
            static let collapsedWidth: CGFloat = 44
            static let collapsedHeight: CGFloat = 104
            static let collapsedCornerRadius: CGFloat = 24
            static let collapsedShadowOpacity: Float = 0.20
            static let collapsedShadowOffset = CGSize(width: -2, height: 3)
            static let collapsedShadowRadius: CGFloat = 8
            static let collapsedSparkleTopInset: CGFloat = 14
            static let collapsedSparkleSize: CGFloat = 28
            static let collapsedChevronBottomInset: CGFloat = -16
            static let collapsedChevronSize: CGFloat = 16
            static let collapsedChevronPointSize: CGFloat = 13

            static let expandedCardWidth: CGFloat = 290
            static let expandedCardMargin: CGFloat = 16
            static let expandedTotalWidth: CGFloat = expandedCardWidth + expandedCardMargin
            static let expandedCornerRadius: CGFloat = 24
            static let expandedShadowOpacity: Float = 0.22
            static let expandedShadowOffset = CGSize(width: 0, height: 6)
            static let expandedShadowRadius: CGFloat = 14
            static let expandedInitialHeight: CGFloat = 230
            static let expandedMinHeight: CGFloat = 210

            static let sparkleLeadingInset: CGFloat = 20
            static let sparkleTopInset: CGFloat = 18
            static let sparkleSize: CGFloat = 32
            static let closeButtonTrailingInset: CGFloat = -8
            static let closeButtonSize: CGFloat = 44
            static let closeButtonPointSize: CGFloat = 13

            static let titleFontSize: CGFloat = 18
            static let titleTopSpacing: CGFloat = 12
            static let descFontSize: CGFloat = 13.5
            static let descTopSpacing: CGFloat = 6
            static let descTextAlpha: CGFloat = 0.95
            static let contentHorizontalInset: CGFloat = 20

            static let actionButtonCornerRadius: CGFloat = 20
            static let actionButtonTopSpacing: CGFloat = 16
            static let actionButtonBottomInset: CGFloat = -20
            static let actionButtonHeight: CGFloat = 40
            static let actionButtonHorizontalInset: CGFloat = 24
            static let actionButtonFontSize: CGFloat = 15
            static let actionButtonShadowOpacity: Float = 0.12
            static let actionButtonShadowOffset = CGSize(width: 0, height: 2)
            static let actionButtonShadowRadius: CGFloat = 4

            static let brandingTopSpacing: CGFloat = 10
            static let brandingBottomInset: CGFloat = -14

            static let animationDuration: TimeInterval = 0.35
            static let animationDamping: CGFloat = 0.82
            static let animationInitialVelocity: CGFloat = 0.5
            static let collapseTransformOffsetX: CGFloat = 30
        }

        /// Fallback copy shown when no widget-provided text is available.
        /// Centralized here to make future localization straightforward.
        private enum DefaultStrings {
            static let title = "Let us choose together"
            static let description = "Let's find your perfect match together"
            static let actionButton = "Start Now"
            static let closeAccessibilityLabel = "Close Poltio Widget Card"
        }

        public init(
            widget: PoltioWidgetResponse,
            onOpenWidget: @escaping () -> Void
        ) {
            self.widget = widget
            self.onOpenWidget = onOpenWidget
            currentState = widget.overlayOptions.isInitialExpanded ? .expanded : .collapsed
            super.init(frame: .zero)

            setupView()
            applyState(currentState, animated: false)
            setupScrollReveal()
            setupScrollCollapseObserver()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            NotificationCenter.default.removeObserver(self, name: PoltioScrollObserver.didDetectScrollMovementNotification, object: nil)
            scrollRevealToken.map(PoltioScrollObserver.cancelScrollPast)
        }

        private func setupView() {
            translatesAutoresizingMaskIntoConstraints = false
            backgroundColor = .clear
            clipsToBounds = false

            let initialWidth = (currentState == .expanded) ? Constants.expandedTotalWidth : Constants.collapsedWidth
            let initialHeight = (currentState == .expanded) ? Constants.expandedInitialHeight : Constants.collapsedHeight

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
            collapsedContainer.layer.cornerRadius = Constants.collapsedCornerRadius
            collapsedContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            collapsedContainer.layer.shadowColor = UIColor.black.cgColor
            collapsedContainer.layer.shadowOpacity = Constants.collapsedShadowOpacity
            collapsedContainer.layer.shadowOffset = Constants.collapsedShadowOffset
            collapsedContainer.layer.shadowRadius = Constants.collapsedShadowRadius
            collapsedContainer.isUserInteractionEnabled = true

            // Top sparkle icon
            collapsedSparkleIcon.translatesAutoresizingMaskIntoConstraints = false
            collapsedContainer.addSubview(collapsedSparkleIcon)

            // Bottom left chevron
            collapsedChevron.translatesAutoresizingMaskIntoConstraints = false
            collapsedChevron.contentMode = .scaleAspectFit
            collapsedChevron.tintColor = widget.overlayOptions.resolvedIconColor
            let chevronConfig = UIImage.SymbolConfiguration(pointSize: Constants.collapsedChevronPointSize, weight: .bold)
            collapsedChevron.image = UIImage(systemName: "chevron.left", withConfiguration: chevronConfig)
            collapsedContainer.addSubview(collapsedChevron)

            addSubview(collapsedContainer)

            NSLayoutConstraint.activate([
                collapsedContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
                collapsedContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
                collapsedContainer.widthAnchor.constraint(equalToConstant: Constants.collapsedWidth),
                collapsedContainer.heightAnchor.constraint(equalToConstant: Constants.collapsedHeight),

                collapsedSparkleIcon.centerXAnchor.constraint(equalTo: collapsedContainer.centerXAnchor),
                collapsedSparkleIcon.topAnchor.constraint(equalTo: collapsedContainer.topAnchor, constant: Constants.collapsedSparkleTopInset),
                collapsedSparkleIcon.widthAnchor.constraint(equalToConstant: Constants.collapsedSparkleSize),
                collapsedSparkleIcon.heightAnchor.constraint(equalToConstant: Constants.collapsedSparkleSize),

                collapsedChevron.centerXAnchor.constraint(equalTo: collapsedContainer.centerXAnchor),
                collapsedChevron.bottomAnchor.constraint(equalTo: collapsedContainer.bottomAnchor, constant: Constants.collapsedChevronBottomInset),
                collapsedChevron.widthAnchor.constraint(equalToConstant: Constants.collapsedChevronSize),
                collapsedChevron.heightAnchor.constraint(equalToConstant: Constants.collapsedChevronSize),
            ])

            let loader = PoltioTriggerIconLoader(container: collapsedContainer, size: Constants.collapsedSparkleSize)
            collapsedIconLoader = loader
            loader.load(from: widget.overlayOptions, centeredOn: collapsedSparkleIcon) { [weak self] in
                self?.collapsedSparkleIcon.isHidden = true
            }
        }

        // MARK: - Expanded View Setup

        private func setupExpandedContainer() {
            expandedContainer.translatesAutoresizingMaskIntoConstraints = false
            expandedContainer.backgroundColor = widget.overlayOptions.resolvedBgColor
            expandedContainer.layer.cornerRadius = widget.overlayOptions.resolvedMobileTopBorderRadius
            expandedContainer.layer.shadowColor = UIColor.black.cgColor
            expandedContainer.layer.shadowOpacity = Constants.expandedShadowOpacity
            expandedContainer.layer.shadowOffset = Constants.expandedShadowOffset
            expandedContainer.layer.shadowRadius = Constants.expandedShadowRadius
            expandedContainer.clipsToBounds = false
            expandedContainer.isUserInteractionEnabled = true

            // 1. Top Sparkle Icon
            expandedSparkleIcon.translatesAutoresizingMaskIntoConstraints = false
            expandedContainer.addSubview(expandedSparkleIcon)

            // 2. Top-Right Close Button
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            closeButton.tintColor = widget.overlayOptions.resolvedIconColor
            let xmarkConfig = UIImage.SymbolConfiguration(pointSize: Constants.closeButtonPointSize, weight: .bold)
            closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: xmarkConfig), for: .normal)
            closeButton.addTarget(self, action: #selector(handleCloseTap), for: .touchUpInside)
            closeButton.accessibilityLabel = DefaultStrings.closeAccessibilityLabel
            expandedContainer.addSubview(closeButton)

            // 3. Title Label
            let titleText = widget.overlayOptions.floatingTitle
                ?? widget.overlayOptions.floatingBoxTextFirst
                ?? DefaultStrings.title
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.text = titleText
            titleLabel.font = widget.overlayOptions.resolvedFont(size: Constants.titleFontSize, weight: .heavy)
            titleLabel.textColor = widget.overlayOptions.resolvedTextColor
            titleLabel.numberOfLines = 2
            titleLabel.lineBreakMode = .byWordWrapping
            expandedContainer.addSubview(titleLabel)

            // 4. Description Label
            let descText = widget.overlayOptions.floatingDesc
                ?? widget.overlayOptions.floatingBoxTextSecond
                ?? DefaultStrings.description
            descLabel.translatesAutoresizingMaskIntoConstraints = false
            descLabel.text = descText
            descLabel.font = widget.overlayOptions.resolvedFont(size: Constants.descFontSize, weight: .medium)
            descLabel.textColor = widget.overlayOptions.resolvedTextColor.withAlphaComponent(Constants.descTextAlpha)
            descLabel.numberOfLines = 0
            descLabel.lineBreakMode = .byWordWrapping
            expandedContainer.addSubview(descLabel)

            // 5. Action Button ("Start Now")
            let btnText = widget.overlayOptions.floatingButtonText ?? DefaultStrings.actionButton
            actionButton.translatesAutoresizingMaskIntoConstraints = false
            actionButton.backgroundColor = .white
            actionButton.layer.cornerRadius = Constants.actionButtonCornerRadius
            actionButton.setTitle(btnText, for: .normal)
            actionButton.setTitleColor(.black, for: .normal)
            actionButton.titleLabel?.font = widget.overlayOptions.resolvedFont(size: Constants.actionButtonFontSize, weight: .bold)
            actionButton.contentEdgeInsets = UIEdgeInsets(
                top: 0, left: Constants.actionButtonHorizontalInset,
                bottom: 0, right: Constants.actionButtonHorizontalInset
            )
            actionButton.layer.shadowColor = UIColor.black.cgColor
            actionButton.layer.shadowOpacity = Constants.actionButtonShadowOpacity
            actionButton.layer.shadowOffset = Constants.actionButtonShadowOffset
            actionButton.layer.shadowRadius = Constants.actionButtonShadowRadius
            actionButton.addTarget(self, action: #selector(handleActionTap), for: .touchUpInside)
            expandedContainer.addSubview(actionButton)

            // 6. Poltio branding mark (hidden when `floating-show-logo` is explicitly `false`)
            let showLogo = widget.overlayOptions.showLogo
            brandingRow.translatesAutoresizingMaskIntoConstraints = false
            brandingRow.isHidden = !showLogo
            brandingRow.configure(with: widget.overlayOptions)
            expandedContainer.addSubview(brandingRow)

            addSubview(expandedContainer)

            let bottomAnchorConstraint = showLogo
                ? expandedContainer.bottomAnchor.constraint(equalTo: brandingRow.bottomAnchor, constant: -Constants.brandingBottomInset)
                : expandedContainer.bottomAnchor.constraint(equalTo: actionButton.bottomAnchor, constant: -Constants.actionButtonBottomInset)

            NSLayoutConstraint.activate([
                expandedContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.expandedCardMargin),
                expandedContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
                expandedContainer.widthAnchor.constraint(equalToConstant: Constants.expandedCardWidth),

                // Top icons row
                expandedSparkleIcon.leadingAnchor.constraint(equalTo: expandedContainer.leadingAnchor, constant: Constants.sparkleLeadingInset),
                expandedSparkleIcon.topAnchor.constraint(equalTo: expandedContainer.topAnchor, constant: Constants.sparkleTopInset),
                expandedSparkleIcon.widthAnchor.constraint(equalToConstant: Constants.sparkleSize),
                expandedSparkleIcon.heightAnchor.constraint(equalToConstant: Constants.sparkleSize),

                closeButton.trailingAnchor.constraint(equalTo: expandedContainer.trailingAnchor, constant: Constants.closeButtonTrailingInset),
                closeButton.centerYAnchor.constraint(equalTo: expandedSparkleIcon.centerYAnchor),
                closeButton.widthAnchor.constraint(equalToConstant: Constants.closeButtonSize),
                closeButton.heightAnchor.constraint(equalToConstant: Constants.closeButtonSize),

                // Title
                titleLabel.leadingAnchor.constraint(equalTo: expandedContainer.leadingAnchor, constant: Constants.contentHorizontalInset),
                titleLabel.trailingAnchor.constraint(equalTo: expandedContainer.trailingAnchor, constant: -Constants.contentHorizontalInset),
                titleLabel.topAnchor.constraint(equalTo: expandedSparkleIcon.bottomAnchor, constant: Constants.titleTopSpacing),

                // Description
                descLabel.leadingAnchor.constraint(equalTo: expandedContainer.leadingAnchor, constant: Constants.contentHorizontalInset),
                descLabel.trailingAnchor.constraint(equalTo: expandedContainer.trailingAnchor, constant: -Constants.contentHorizontalInset),
                descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Constants.descTopSpacing),

                // Action Button
                actionButton.leadingAnchor.constraint(equalTo: expandedContainer.leadingAnchor, constant: Constants.contentHorizontalInset),
                actionButton.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: Constants.actionButtonTopSpacing),
                actionButton.heightAnchor.constraint(equalToConstant: Constants.actionButtonHeight),

                // Branding mark (only laid out when visible; container bottom otherwise ties to the action button)
                brandingRow.centerXAnchor.constraint(equalTo: expandedContainer.centerXAnchor),
                brandingRow.topAnchor.constraint(equalTo: actionButton.bottomAnchor, constant: Constants.brandingTopSpacing),

                bottomAnchorConstraint,
            ])

            let loader = PoltioTriggerIconLoader(container: expandedContainer, size: Constants.sparkleSize)
            expandedIconLoader = loader
            loader.load(from: widget.overlayOptions, centeredOn: expandedSparkleIcon) { [weak self] in
                self?.expandedSparkleIcon.isHidden = true
            }
        }

        /// Matches web's card (`core.ts`'s `first` → `second` transition): reveals the collapsed
        /// card once the host content scrolls past `floatingScrollThreshold` (default 300pt,
        /// matching web's own `scrollThreshold ?? 300`). One-shot, like web's own scroll listener
        /// (`controller.abort()`). Unlike web (which leaves the card expanded indefinitely once
        /// revealed), mobile also auto-collapses it while the host keeps scrolling — see
        /// `setupScrollCollapseObserver()` — a deliberate mobile-specific UX choice.
        private func setupScrollReveal() {
            scrollRevealToken = PoltioScrollObserver.onScrollPast(CGFloat(widget.overlayOptions.floatingScrollThreshold)) { [weak self] in
                DispatchQueue.main.async {
                    guard let self, self.currentState == .collapsed else { return }
                    self.setState(.expanded, animated: true)
                }
            }
        }

        /// Auto-collapses an expanded card while the host page is actively being scrolled, smoothly
        /// following the existing expand/collapse animation — regardless of what caused the expand
        /// (manual tap or the scroll-reveal above).
        private func setupScrollCollapseObserver() {
            PoltioScrollObserver.installIfNeeded()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleScrollMovementDetected),
                name: PoltioScrollObserver.didDetectScrollMovementNotification,
                object: nil
            )
        }

        @objc private func handleScrollMovementDetected() {
            guard currentState == .expanded,
                  let expandedAt, Date().timeIntervalSince(expandedAt) > Self.scrollCollapseGracePeriod
            else { return }
            setState(.collapsed, animated: true)
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
            if isExpanded {
                expandedAt = Date()
                // The scroll-reveal registration (if still pending) has nothing left to do once
                // already expanded — its own callback checks `currentState == .collapsed` before
                // acting — so free it now instead of leaving it to be checked against every
                // further scroll update until it happens to cross the threshold on its own.
                if let token = scrollRevealToken {
                    PoltioScrollObserver.cancelScrollPast(token)
                    scrollRevealToken = nil
                }
            }
            let targetWidth = isExpanded ? Constants.expandedTotalWidth : Constants.collapsedWidth

            // Measure height needed for expanded state
            let targetHeight: CGFloat = if isExpanded {
                expandedContainer.systemLayoutSizeFitting(
                    CGSize(width: Constants.expandedCardWidth, height: UIView.layoutFittingCompressedSize.height),
                    withHorizontalFittingPriority: .required,
                    verticalFittingPriority: .fittingSizeLevel
                ).height
            } else {
                Constants.collapsedHeight
            }

            let effectiveHeight = max(targetHeight, isExpanded ? Constants.expandedMinHeight : Constants.collapsedHeight)

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
                withDuration: Constants.animationDuration,
                delay: 0,
                usingSpringWithDamping: Constants.animationDamping,
                initialSpringVelocity: Constants.animationInitialVelocity,
                options: [.curveEaseInOut, .allowUserInteraction],
                animations: { [weak self] in
                    guard let self else { return }
                    widthConstraint.constant = targetWidth
                    heightConstraint.constant = effectiveHeight
                    collapsedContainer.alpha = isExpanded ? 0.0 : 1.0
                    expandedContainer.alpha = isExpanded ? 1.0 : 0.0
                    collapsedContainer.transform = isExpanded ? CGAffineTransform(translationX: Constants.collapseTransformOffsetX, y: 0) : .identity
                    expandedContainer.transform = isExpanded ? .identity : CGAffineTransform(translationX: Constants.collapseTransformOffsetX, y: 0)
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
