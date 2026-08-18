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

        public private(set) var currentState: TriggerState

        // Container views
        private let collapsedContainer = UIView()
        private let expandedContainer = UIView()

        /// Subviews for collapsed state
        private let collapsedLabel = UILabel()

        // Subviews for expanded state
        private let headerLabel = UILabel()
        private let collapseButton = UIButton(type: .system)
        private let bannerImageView = UIImageView()
        private let bannerFallbackView = UIView()
        private let footerLabel = UILabel()

        /// Image loading task
        private var imageDownloadTask: URLSessionDataTask?

        // Self Dimensions
        private var widthConstraint: NSLayoutConstraint!
        private var heightConstraint: NSLayoutConstraint!

        public init(
            widget: PoltioWidgetResponse,
            onOpenWidget: @escaping () -> Void
        ) {
            self.widget = widget
            self.onOpenWidget = onOpenWidget
            // Initially load in collapsed state
            currentState = .collapsed
            super.init(frame: .zero)

            setupView()
            applyState(currentState, animated: false)
            loadBannerImage()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            imageDownloadTask?.cancel()
        }

        private func setupView() {
            translatesAutoresizingMaskIntoConstraints = false
            backgroundColor = .clear
            clipsToBounds = false

            widthConstraint = widthAnchor.constraint(equalToConstant: currentState == .expanded ? 180 : 42)
            heightConstraint = heightAnchor.constraint(equalToConstant: currentState == .expanded ? 195 : 140)

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
            collapsedContainer.backgroundColor = .white
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
            collapsedLabel.font = .systemFont(ofSize: 13, weight: .bold)
            collapsedLabel.textColor = .black
            collapsedLabel.textAlignment = .center
            collapsedLabel.transform = CGAffineTransform(rotationAngle: -CGFloat.pi / 2)

            collapsedContainer.addSubview(collapsedLabel)
            addSubview(collapsedContainer)

            NSLayoutConstraint.activate([
                collapsedContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
                collapsedContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
                collapsedContainer.widthAnchor.constraint(equalToConstant: 42),
                collapsedContainer.heightAnchor.constraint(equalToConstant: 140),

                collapsedLabel.centerXAnchor.constraint(equalTo: collapsedContainer.centerXAnchor),
                collapsedLabel.centerYAnchor.constraint(equalTo: collapsedContainer.centerYAnchor),
                collapsedLabel.widthAnchor.constraint(equalToConstant: 130),
                collapsedLabel.heightAnchor.constraint(equalToConstant: 30),
            ])
        }

        // MARK: - Expanded View Setup

        private func setupExpandedContainer() {
            expandedContainer.translatesAutoresizingMaskIntoConstraints = false
            expandedContainer.backgroundColor = .white
            expandedContainer.layer.cornerRadius = 18
            expandedContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            expandedContainer.layer.shadowColor = UIColor.black.cgColor
            expandedContainer.layer.shadowOpacity = 0.20
            expandedContainer.layer.shadowOffset = CGSize(width: -3, height: 4)
            expandedContainer.layer.shadowRadius = 12
            expandedContainer.clipsToBounds = false
            expandedContainer.isUserInteractionEnabled = true

            let innerCard = UIView()
            innerCard.translatesAutoresizingMaskIntoConstraints = false
            innerCard.backgroundColor = .white
            innerCard.layer.cornerRadius = 18
            innerCard.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            innerCard.clipsToBounds = true
            expandedContainer.addSubview(innerCard)

            // 1. Top Header Label
            headerLabel.translatesAutoresizingMaskIntoConstraints = false
            headerLabel.text = widget.overlayOptions.floatingBoxTextFirst ?? "Product Finder"
            headerLabel.font = .systemFont(ofSize: 15, weight: .bold)
            headerLabel.textColor = .black
            headerLabel.numberOfLines = 1
            headerLabel.lineBreakMode = .byTruncatingTail
            headerLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            innerCard.addSubview(headerLabel)

            // 2. Top Right Collapse Chevron Button
            collapseButton.translatesAutoresizingMaskIntoConstraints = false
            collapseButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
            collapseButton.tintColor = .systemGray
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
            footerLabel.font = .systemFont(ofSize: 15, weight: .bold)
            footerLabel.textColor = .black
            footerLabel.numberOfLines = 1
            footerLabel.lineBreakMode = .byTruncatingTail
            footerLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            innerCard.addSubview(footerLabel)

            addSubview(expandedContainer)

            NSLayoutConstraint.activate([
                expandedContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
                expandedContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
                expandedContainer.widthAnchor.constraint(equalToConstant: 180),
                expandedContainer.heightAnchor.constraint(equalToConstant: 195),

                innerCard.topAnchor.constraint(equalTo: expandedContainer.topAnchor),
                innerCard.leadingAnchor.constraint(equalTo: expandedContainer.leadingAnchor),
                innerCard.trailingAnchor.constraint(equalTo: expandedContainer.trailingAnchor),
                innerCard.bottomAnchor.constraint(equalTo: expandedContainer.bottomAnchor),

                headerLabel.topAnchor.constraint(equalTo: innerCard.topAnchor, constant: 14),
                headerLabel.leadingAnchor.constraint(equalTo: innerCard.leadingAnchor, constant: 16),
                headerLabel.trailingAnchor.constraint(equalTo: collapseButton.leadingAnchor, constant: -4),

                collapseButton.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
                collapseButton.trailingAnchor.constraint(equalTo: innerCard.trailingAnchor, constant: -10),
                collapseButton.widthAnchor.constraint(equalToConstant: 24),
                collapseButton.heightAnchor.constraint(equalToConstant: 24),

                bannerImageView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 12),
                bannerImageView.leadingAnchor.constraint(equalTo: innerCard.leadingAnchor),
                bannerImageView.trailingAnchor.constraint(equalTo: innerCard.trailingAnchor),
                bannerImageView.heightAnchor.constraint(equalToConstant: 95),

                bannerFallbackView.topAnchor.constraint(equalTo: bannerImageView.topAnchor),
                bannerFallbackView.leadingAnchor.constraint(equalTo: bannerImageView.leadingAnchor),
                bannerFallbackView.trailingAnchor.constraint(equalTo: bannerImageView.trailingAnchor),
                bannerFallbackView.bottomAnchor.constraint(equalTo: bannerImageView.bottomAnchor),

                footerLabel.topAnchor.constraint(equalTo: bannerImageView.bottomAnchor, constant: 14),
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
                guard let self = self, let data = data, error == nil, let image = UIImage(data: data) else {
                    return
                }
                DispatchQueue.main.async {
                    self.bannerImageView.image = image
                    self.bannerFallbackView.isHidden = true
                }
            }
            imageDownloadTask?.resume()
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

            widthConstraint.constant = isExpanded ? 180 : 42
            heightConstraint.constant = isExpanded ? 195 : 140

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
    }
#endif
