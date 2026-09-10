#if canImport(UIKit)
    import UIKit

    /// Native floating box trigger view supporting collapsed and expanded states matching Poltio design specs.
    public final class PoltioFloatingBoxTriggerView: UIView, PoltioTriggerPresentable {
        /// Visual states of the floating trigger.
        public enum TriggerState {
            case collapsed
            case expanded
        }

        private let widget: PoltioWidgetResponse
        private let onOpenWidget: () -> Void
        /// Invoked when the user taps the explicit close (X) button (`boxShowCloseButton`). Records a
        /// `boxCloseRememberDuration`-hour dismissal and fully hides the trigger (not just a collapse).
        private let onDismissForever: (Double) -> Void

        public private(set) var currentState: TriggerState

        /// Uniform scale factor applied to every dimension below, from `boxResize` (clamped to a sane
        /// range so bad API data can't produce a degenerate or oversized trigger).
        private let scale: CGFloat

        // Container views
        private let collapsedContainer = UIView()
        private let expandedContainer = UIView()
        private let innerCard = UIView()

        /// Subviews for collapsed state
        private let collapsedLabel = UILabel()

        // Subviews for expanded state
        private let headerLabel = UILabel()
        private let collapseButton = UIButton(type: .system)
        private let closeButton = UIButton(type: .custom)
        private let bannerImageView = UIImageView()
        private let bannerFallbackView = UIView()
        private let footerLabel = UILabel()
        private let headerScrim = UIView()
        private let footerScrim = UIView()

        /// Image loading task
        private var imageDownloadTask: URLSessionDataTask?
        /// One-shot timer for `boxOpenOnTime` auto-expand.
        private var autoOpenTimer: Timer?

        // Self Dimensions
        private var widthConstraint: NSLayoutConstraint!
        private var heightConstraint: NSLayoutConstraint!

        private var collapsedWidth: CGFloat {
            42 * scale
        }

        private var collapsedHeight: CGFloat {
            140 * scale
        }

        private var expandedWidth: CGFloat {
            180 * scale
        }

        private var expandedHeight: CGFloat {
            195 * scale
        }

        public init(
            widget: PoltioWidgetResponse,
            onOpenWidget: @escaping () -> Void,
            onDismissForever: @escaping (Double) -> Void = { _ in }
        ) {
            self.widget = widget
            self.onOpenWidget = onOpenWidget
            self.onDismissForever = onDismissForever
            scale = max(0.5, min(2.0, CGFloat(widget.overlayOptions.boxResize)))
            let shouldStartExpanded = widget.overlayOptions.isInitialExpanded
                || widget.overlayOptions.boxStartMode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "open"
            currentState = shouldStartExpanded ? .expanded : .collapsed
            super.init(frame: .zero)

            setupView()
            applyState(currentState, animated: false)
            loadBannerImage()
            scheduleAutoOpenIfNeeded()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            imageDownloadTask?.cancel()
            let timer = autoOpenTimer
            DispatchQueue.main.async {
                timer?.invalidate()
            }
        }

        private func setupView() {
            translatesAutoresizingMaskIntoConstraints = false
            backgroundColor = .clear
            clipsToBounds = false

            widthConstraint = widthAnchor.constraint(equalToConstant: currentState == .expanded ? expandedWidth : collapsedWidth)
            heightConstraint = heightAnchor.constraint(equalToConstant: currentState == .expanded ? expandedHeight : collapsedHeight)

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
            let outerBg = PoltioOverlayOptions.resolvedColor(widget.overlayOptions.boxBgColorFirst, fallback: .white)
            let headerColor = PoltioOverlayOptions.resolvedColor(widget.overlayOptions.boxTextColorFirst, fallback: .black)

            collapsedContainer.translatesAutoresizingMaskIntoConstraints = false
            collapsedContainer.backgroundColor = outerBg
            collapsedContainer.layer.cornerRadius = 14
            collapsedContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            collapsedContainer.layer.shadowColor = UIColor.black.cgColor
            collapsedContainer.layer.shadowOpacity = 0.18
            collapsedContainer.layer.shadowOffset = CGSize(width: -2, height: 3)
            collapsedContainer.layer.shadowRadius = 8
            collapsedContainer.isUserInteractionEnabled = true

            let text = widget.overlayOptions.floatingBoxTextFirst ?? "Product Finder"
            collapsedLabel.translatesAutoresizingMaskIntoConstraints = false
            collapsedLabel.text = text
            collapsedLabel.font = widget.overlayOptions.resolvedFont(size: 13, weight: .bold)
            collapsedLabel.textColor = headerColor
            collapsedLabel.textAlignment = .center
            collapsedLabel.transform = CGAffineTransform(rotationAngle: -CGFloat.pi / 2)

            collapsedContainer.addSubview(collapsedLabel)
            addSubview(collapsedContainer)

            NSLayoutConstraint.activate([
                collapsedContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
                collapsedContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
                collapsedContainer.widthAnchor.constraint(equalToConstant: collapsedWidth),
                collapsedContainer.heightAnchor.constraint(equalToConstant: collapsedHeight),

                collapsedLabel.centerXAnchor.constraint(equalTo: collapsedContainer.centerXAnchor),
                collapsedLabel.centerYAnchor.constraint(equalTo: collapsedContainer.centerYAnchor),
                collapsedLabel.widthAnchor.constraint(equalToConstant: 130 * scale),
                collapsedLabel.heightAnchor.constraint(equalToConstant: 30 * scale),
            ])
        }

        // MARK: - Expanded View Setup

        private func setupExpandedContainer() {
            let outerBg = PoltioOverlayOptions.resolvedColor(widget.overlayOptions.boxBgColorFirst, fallback: .white)
            let innerBg = PoltioOverlayOptions.resolvedColor(widget.overlayOptions.boxBgColorSecond, fallback: .white)
            let headerColor = PoltioOverlayOptions.resolvedColor(widget.overlayOptions.boxTextColorFirst, fallback: .black)
            let footerColor = PoltioOverlayOptions.resolvedColor(widget.overlayOptions.boxTextColorSecond, fallback: .black)
            let fullImageMode = widget.overlayOptions.boxFullImageMode

            expandedContainer.translatesAutoresizingMaskIntoConstraints = false
            expandedContainer.backgroundColor = outerBg
            expandedContainer.layer.cornerRadius = 18
            expandedContainer.layer.shadowColor = UIColor.black.cgColor
            expandedContainer.layer.shadowOpacity = 0.20
            expandedContainer.layer.shadowOffset = CGSize(width: -3, height: 4)
            expandedContainer.layer.shadowRadius = 12
            expandedContainer.clipsToBounds = false
            expandedContainer.isUserInteractionEnabled = true

            innerCard.translatesAutoresizingMaskIntoConstraints = false
            innerCard.backgroundColor = innerBg
            innerCard.layer.cornerRadius = 18
            innerCard.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            innerCard.clipsToBounds = true
            expandedContainer.addSubview(innerCard)

            // 1. Top Header Label
            headerLabel.translatesAutoresizingMaskIntoConstraints = false
            headerLabel.text = widget.overlayOptions.floatingBoxTextFirst ?? "Product Finder"
            headerLabel.font = widget.overlayOptions.resolvedFont(
                size: widget.overlayOptions.boxTextFirstFontSize,
                weight: widget.overlayOptions.boxTextFirstFontWeight
            )
            headerLabel.textColor = fullImageMode ? .white : headerColor
            headerLabel.textAlignment = widget.overlayOptions.boxTextAlignFirst
            headerLabel.numberOfLines = 1
            headerLabel.lineBreakMode = .byTruncatingTail
            headerLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            innerCard.addSubview(headerLabel)

            // 2. Top Right Collapse Chevron Button
            collapseButton.translatesAutoresizingMaskIntoConstraints = false
            collapseButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
            collapseButton.tintColor = fullImageMode ? .white : .systemGray
            collapseButton.addTarget(self, action: #selector(handleSwipeRight), for: .touchUpInside)
            innerCard.addSubview(collapseButton)

            // 3. Middle Banner (Image & Fallback Graphic)
            bannerImageView.translatesAutoresizingMaskIntoConstraints = false
            bannerImageView.contentMode = .scaleAspectFill
            bannerImageView.clipsToBounds = true
            bannerImageView.backgroundColor = UIColor(red: 0.0, green: 0.62, blue: 0.93, alpha: 1.0)
            innerCard.addSubview(bannerImageView)

            setupBannerFallbackView()
            bannerImageView.addSubview(bannerFallbackView)

            // 4. Bottom Footer Label
            footerLabel.translatesAutoresizingMaskIntoConstraints = false
            footerLabel.text = widget.overlayOptions.floatingBoxTextSecond ?? "Product Finder"
            footerLabel.font = widget.overlayOptions.resolvedFont(
                size: widget.overlayOptions.boxTextSecondFontSize,
                weight: widget.overlayOptions.boxTextSecondFontWeight
            )
            footerLabel.textColor = fullImageMode ? .white : footerColor
            footerLabel.textAlignment = widget.overlayOptions.boxTextAlignSecond
            footerLabel.numberOfLines = 1
            footerLabel.lineBreakMode = .byTruncatingTail
            footerLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            innerCard.addSubview(footerLabel)

            addSubview(expandedContainer)

            NSLayoutConstraint.activate([
                expandedContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
                expandedContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
                expandedContainer.widthAnchor.constraint(equalToConstant: expandedWidth),
                expandedContainer.heightAnchor.constraint(equalToConstant: expandedHeight),

                innerCard.topAnchor.constraint(equalTo: expandedContainer.topAnchor),
                innerCard.leadingAnchor.constraint(equalTo: expandedContainer.leadingAnchor),
                innerCard.trailingAnchor.constraint(equalTo: expandedContainer.trailingAnchor),
                innerCard.bottomAnchor.constraint(equalTo: expandedContainer.bottomAnchor),

                collapseButton.trailingAnchor.constraint(equalTo: innerCard.trailingAnchor, constant: -10),
                collapseButton.widthAnchor.constraint(equalToConstant: 24),
                collapseButton.heightAnchor.constraint(equalToConstant: 24),
            ])

            if fullImageMode {
                setupFullImageModeLayout()
            } else {
                setupStandardBannerLayout()
            }

            if widget.overlayOptions.boxShowCloseButton {
                closeButton.translatesAutoresizingMaskIntoConstraints = false
                closeButton.tintColor = fullImageMode ? .white : .systemGray
                let xmarkConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
                closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: xmarkConfig), for: .normal)
                closeButton.addTarget(self, action: #selector(handleCloseTap), for: .touchUpInside)
                closeButton.accessibilityLabel = "Close"
                innerCard.addSubview(closeButton)

                NSLayoutConstraint.activate([
                    closeButton.trailingAnchor.constraint(equalTo: collapseButton.leadingAnchor, constant: -4),
                    closeButton.centerYAnchor.constraint(equalTo: collapseButton.centerYAnchor),
                    closeButton.widthAnchor.constraint(equalToConstant: 24),
                    closeButton.heightAnchor.constraint(equalToConstant: 24),
                ])
            }
        }

        /// Default layout: header text, a fixed-height banner strip, footer text.
        private func setupStandardBannerLayout() {
            NSLayoutConstraint.activate([
                headerLabel.topAnchor.constraint(equalTo: innerCard.topAnchor, constant: 14),
                headerLabel.leadingAnchor.constraint(equalTo: innerCard.leadingAnchor, constant: 16),
                headerLabel.trailingAnchor.constraint(equalTo: collapseButton.leadingAnchor, constant: -4),

                collapseButton.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),

                bannerImageView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 12),
                bannerImageView.leadingAnchor.constraint(equalTo: innerCard.leadingAnchor),
                bannerImageView.trailingAnchor.constraint(equalTo: innerCard.trailingAnchor),
                bannerImageView.heightAnchor.constraint(equalToConstant: 95 * scale),

                bannerFallbackView.topAnchor.constraint(equalTo: bannerImageView.topAnchor),
                bannerFallbackView.leadingAnchor.constraint(equalTo: bannerImageView.leadingAnchor),
                bannerFallbackView.trailingAnchor.constraint(equalTo: bannerImageView.trailingAnchor),
                bannerFallbackView.bottomAnchor.constraint(equalTo: bannerImageView.bottomAnchor),

                footerLabel.topAnchor.constraint(equalTo: bannerImageView.bottomAnchor, constant: 14),
                footerLabel.leadingAnchor.constraint(equalTo: innerCard.leadingAnchor, constant: 16),
                footerLabel.trailingAnchor.constraint(equalTo: innerCard.trailingAnchor, constant: -16),
            ])
        }

        /// `boxFullImageMode` layout: the banner image fills the whole card, header/footer float over it
        /// on translucent scrims for legibility.
        private func setupFullImageModeLayout() {
            headerScrim.translatesAutoresizingMaskIntoConstraints = false
            headerScrim.backgroundColor = UIColor.black.withAlphaComponent(0.35)
            footerScrim.translatesAutoresizingMaskIntoConstraints = false
            footerScrim.backgroundColor = UIColor.black.withAlphaComponent(0.35)

            innerCard.insertSubview(headerScrim, belowSubview: headerLabel)
            innerCard.insertSubview(footerScrim, belowSubview: footerLabel)
            innerCard.bringSubviewToFront(collapseButton)

            NSLayoutConstraint.activate([
                bannerImageView.topAnchor.constraint(equalTo: innerCard.topAnchor),
                bannerImageView.leadingAnchor.constraint(equalTo: innerCard.leadingAnchor),
                bannerImageView.trailingAnchor.constraint(equalTo: innerCard.trailingAnchor),
                bannerImageView.bottomAnchor.constraint(equalTo: innerCard.bottomAnchor),

                bannerFallbackView.topAnchor.constraint(equalTo: bannerImageView.topAnchor),
                bannerFallbackView.leadingAnchor.constraint(equalTo: bannerImageView.leadingAnchor),
                bannerFallbackView.trailingAnchor.constraint(equalTo: bannerImageView.trailingAnchor),
                bannerFallbackView.bottomAnchor.constraint(equalTo: bannerImageView.bottomAnchor),

                headerScrim.topAnchor.constraint(equalTo: innerCard.topAnchor),
                headerScrim.leadingAnchor.constraint(equalTo: innerCard.leadingAnchor),
                headerScrim.trailingAnchor.constraint(equalTo: innerCard.trailingAnchor),
                headerScrim.bottomAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 10),

                headerLabel.topAnchor.constraint(equalTo: innerCard.topAnchor, constant: 14),
                headerLabel.leadingAnchor.constraint(equalTo: innerCard.leadingAnchor, constant: 16),
                headerLabel.trailingAnchor.constraint(equalTo: collapseButton.leadingAnchor, constant: -4),
                collapseButton.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),

                footerScrim.bottomAnchor.constraint(equalTo: innerCard.bottomAnchor),
                footerScrim.leadingAnchor.constraint(equalTo: innerCard.leadingAnchor),
                footerScrim.trailingAnchor.constraint(equalTo: innerCard.trailingAnchor),
                footerScrim.topAnchor.constraint(equalTo: footerLabel.topAnchor, constant: -10),

                footerLabel.bottomAnchor.constraint(equalTo: innerCard.bottomAnchor, constant: -14),
                footerLabel.leadingAnchor.constraint(equalTo: innerCard.leadingAnchor, constant: 16),
                footerLabel.trailingAnchor.constraint(equalTo: innerCard.trailingAnchor, constant: -16),
            ])
        }

        private func setupBannerFallbackView() {
            bannerFallbackView.translatesAutoresizingMaskIntoConstraints = false
            bannerFallbackView.backgroundColor = UIColor(red: 0.0, green: 0.62, blue: 0.93, alpha: 1.0)

            let titleLabel = UILabel()
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.text = "Find\nyour\nperfect\nproduct"
            titleLabel.numberOfLines = 4
            titleLabel.font = .systemFont(ofSize: 13, weight: .heavy)
            titleLabel.textColor = .white
            bannerFallbackView.addSubview(titleLabel)

            let iconLabel = UILabel()
            iconLabel.translatesAutoresizingMaskIntoConstraints = false
            iconLabel.text = "?"
            iconLabel.font = .systemFont(ofSize: 32, weight: .bold)
            iconLabel.textColor = .white
            iconLabel.textAlignment = .center
            bannerFallbackView.addSubview(iconLabel)

            NSLayoutConstraint.activate([
                titleLabel.leadingAnchor.constraint(equalTo: bannerFallbackView.leadingAnchor, constant: 12),
                titleLabel.centerYAnchor.constraint(equalTo: bannerFallbackView.centerYAnchor),

                iconLabel.trailingAnchor.constraint(equalTo: bannerFallbackView.trailingAnchor, constant: -14),
                iconLabel.centerYAnchor.constraint(equalTo: bannerFallbackView.centerYAnchor),
            ])
        }

        // MARK: - Banner Image Loader

        private func loadBannerImage() {
            guard let imageURL = widget.overlayOptions.resolvedImageUrl() else { return }

            imageDownloadTask?.cancel()
            imageDownloadTask = URLSession.shared.dataTask(with: imageURL) { [weak self] data, _, error in
                guard let self, let data, error == nil, let image = UIImage(data: data) else {
                    return
                }
                DispatchQueue.main.async {
                    self.bannerImageView.image = image
                    self.bannerFallbackView.isHidden = true
                }
            }
            imageDownloadTask?.resume()
        }

        // MARK: - Auto Open (`boxOpenOnTime`)

        private func scheduleAutoOpenIfNeeded() {
            guard let delayMs = widget.overlayOptions.boxOpenOnTime, delayMs > 0 else { return }
            autoOpenTimer?.invalidate()
            autoOpenTimer = Timer.scheduledTimer(withTimeInterval: delayMs / 1000.0, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.currentState == .collapsed else { return }
                    self.setState(.expanded, animated: true)
                }
            }
        }

        // MARK: - State Handling & Actions

        public func setState(_ state: TriggerState, animated: Bool = true) {
            guard currentState != state else { return }
            currentState = state
            applyState(state, animated: animated)
        }

        public func resetToCollapsed(animated: Bool = true) {
            setState(.collapsed, animated: animated)
        }

        private func applyState(_ state: TriggerState, animated: Bool) {
            let isExpanded = (state == .expanded)

            widthConstraint.constant = isExpanded ? expandedWidth : collapsedWidth
            heightConstraint.constant = isExpanded ? expandedHeight : collapsedHeight

            if isExpanded {
                expandedContainer.isHidden = false
            } else {
                collapsedContainer.isHidden = false
            }

            let animations = {
                self.collapsedContainer.alpha = isExpanded ? 0.0 : 1.0
                self.expandedContainer.alpha = isExpanded ? 1.0 : 0.0
                self.superview?.layoutIfNeeded()
            }

            let completion: (Bool) -> Void = { _ in
                if isExpanded {
                    self.collapsedContainer.isHidden = true
                } else {
                    self.expandedContainer.isHidden = true
                }
            }

            if animated {
                UIView.animate(
                    withDuration: 0.35,
                    delay: 0,
                    usingSpringWithDamping: 0.8,
                    initialSpringVelocity: 0.5,
                    options: [.curveEaseInOut, .allowUserInteraction],
                    animations: animations,
                    completion: completion
                )
            } else {
                animations()
                completion(true)
            }
        }

        @objc private func handleCollapsedTap() {
            setState(.expanded, animated: true)
        }

        @objc private func handleExpandedTap() {
            onOpenWidget()
        }

        @objc private func handleSwipeRight() {
            setState(.collapsed, animated: true)
        }

        @objc private func handleCloseTap() {
            autoOpenTimer?.invalidate()
            autoOpenTimer = nil
            onDismissForever(widget.overlayOptions.boxCloseRememberDuration)
        }
    }
#endif
