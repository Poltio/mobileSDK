#if canImport(UIKit)
    import UIKit
    #if canImport(WebKit)
        import WebKit
    #endif

    /// Common protocol for all Poltio floating trigger views (box, pill, etc.).
    public protocol PoltioTriggerPresentable: UIView {
        /// Resets the trigger to its collapsed state.
        func resetToCollapsed(animated: Bool)
    }

    /// Helper view that renders the Poltio sparkle question mark icon.
    final class PoltioSparkleIconView: UIView {
        private let questionMarkLabel = UILabel()
        private let topSparkleLayer = CAShapeLayer()
        private let bottomSparkleLayer = CAShapeLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            setup()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }

        private func setup() {
            backgroundColor = .clear
            isUserInteractionEnabled = false

            // Question mark label
            questionMarkLabel.translatesAutoresizingMaskIntoConstraints = false
            questionMarkLabel.text = "?"
            questionMarkLabel.font = .systemFont(ofSize: 22, weight: .heavy)
            questionMarkLabel.textColor = .white
            questionMarkLabel.textAlignment = .center
            addSubview(questionMarkLabel)

            // Sparkle layers
            topSparkleLayer.fillColor = UIColor.white.withAlphaComponent(0.75).cgColor
            layer.addSublayer(topSparkleLayer)

            bottomSparkleLayer.fillColor = UIColor.white.withAlphaComponent(0.55).cgColor
            layer.addSublayer(bottomSparkleLayer)

            NSLayoutConstraint.activate([
                questionMarkLabel.centerXAnchor.constraint(equalTo: centerXAnchor, constant: -1),
                questionMarkLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            let w = bounds.width
            let h = bounds.height
            guard w > 0, h > 0 else { return }

            // Top right sparkle (larger)
            let topSparkleRect = CGRect(x: w * 0.62, y: h * 0.12, width: w * 0.30, height: h * 0.30)
            topSparkleLayer.path = PoltioSparkleIconView.createSparklePath(in: topSparkleRect).cgPath

            // Bottom left sparkle (smaller)
            let bottomSparkleRect = CGRect(x: w * 0.08, y: h * 0.60, width: w * 0.22, height: h * 0.22)
            bottomSparkleLayer.path = PoltioSparkleIconView.createSparklePath(in: bottomSparkleRect).cgPath
        }

        static func createSparklePath(in rect: CGRect) -> UIBezierPath {
            let path = UIBezierPath()
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let hw = rect.width / 2
            let hh = rect.height / 2
            let indent: CGFloat = 0.22

            path.move(to: CGPoint(x: center.x, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: center.y),
                controlPoint: CGPoint(x: center.x + hw * indent, y: center.y - hh * indent)
            )
            path.addQuadCurve(
                to: CGPoint(x: center.x, y: rect.maxY),
                controlPoint: CGPoint(x: center.x + hw * indent, y: center.y + hh * indent)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: center.y),
                controlPoint: CGPoint(x: center.x - hw * indent, y: center.y + hh * indent)
            )
            path.addQuadCurve(
                to: CGPoint(x: center.x, y: rect.minY),
                controlPoint: CGPoint(x: center.x - hw * indent, y: center.y - hh * indent)
            )
            path.close()
            return path
        }
    }

    /// Native floating pill trigger view supporting collapsed (circular bouncing) and expanded (pill capsule) states.
    public final class PoltioFloatingPillTriggerView: UIView, PoltioTriggerPresentable {
        /// Visual states of the floating pill trigger.
        public enum TriggerState {
            case collapsed
            case expanded
        }

        private let widget: PoltioWidgetResponse
        private let onOpenWidget: () -> Void

        public private(set) var currentState: TriggerState

        // UI Components
        private let cardContainer = UIView()
        private let iconView = PoltioSparkleIconView()
        private let remoteImageView = UIImageView()
        /// Lightweight WKWebView used to render remote vector SVGs without introducing external third-party
        /// dependencies. Created on demand — see `ensureSvgWebView()` — since most triggers never load an SVG
        /// and spinning up WebKit's WebContent process for every trigger would be wasteful.
        /// Hardened with JavaScript disabled and scroll disabled for minimal overhead and security.
        private var svgWebView: WKWebView?

        private let textStackView = UIStackView()
        private let subtitleLabel = UILabel()
        private let titleLabel = UILabel()

        // Layout Constraints
        private var widthConstraint: NSLayoutConstraint!
        private var iconLeadingConstraint: NSLayoutConstraint!
        private var iconCenterConstraint: NSLayoutConstraint!

        // Timers & Observers
        private var autoCollapseTimer: Timer?
        private var scrollObserver: NSObjectProtocol?
        private var imageDownloadTask: URLSessionDataTask?

        /// Bounce Animation Key
        private static let bounceAnimationKey = "poltio.pill.bounce"

        public init(
            widget: PoltioWidgetResponse,
            onOpenWidget: @escaping () -> Void
        ) {
            self.widget = widget
            self.onOpenWidget = onOpenWidget
            let shouldStartExpanded = widget.overlayOptions.isInitialActive || widget.overlayOptions.floatingInitialPosition?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "expanded"
            currentState = shouldStartExpanded ? .expanded : .collapsed
            super.init(frame: .zero)

            setupView()
            applyState(currentState, animated: false)
            loadImageIfNeeded()
            setupScrollObserver()

            if widget.overlayOptions.isInitialActive {
                scheduleAutoCollapse()
            }
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            let timer = autoCollapseTimer
            let webView = svgWebView
            DispatchQueue.main.async {
                timer?.invalidate()
                webView?.stopLoading()
            }
            if let observer = scrollObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            imageDownloadTask?.cancel()
        }

        /// Lazily creates and attaches the SVG-rendering WKWebView the first time it's actually needed,
        /// instead of paying WebKit's WebContent-process cost for every trigger up front.
        private func ensureSvgWebView() -> WKWebView {
            if let existing = svgWebView {
                return existing
            }

            let config = WKWebViewConfiguration()
            config.defaultWebpagePreferences.allowsContentJavaScript = false
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.translatesAutoresizingMaskIntoConstraints = false
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear
            webView.scrollView.isScrollEnabled = false
            webView.isUserInteractionEnabled = false
            webView.isHidden = true
            cardContainer.addSubview(webView)

            NSLayoutConstraint.activate([
                webView.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
                webView.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
                webView.widthAnchor.constraint(equalToConstant: 32),
                webView.heightAnchor.constraint(equalToConstant: 32),
            ])

            svgWebView = webView
            return webView
        }

        private func setupView() {
            translatesAutoresizingMaskIntoConstraints = false
            backgroundColor = .clear
            clipsToBounds = false

            // Main outer container with shadow
            cardContainer.translatesAutoresizingMaskIntoConstraints = false
            cardContainer.backgroundColor = UIColor(red: 0.0, green: 0.64, blue: 0.98, alpha: 1.0) // Vibrant Poltio blue
            cardContainer.layer.cornerRadius = 28
            cardContainer.layer.shadowColor = UIColor.black.cgColor
            cardContainer.layer.shadowOpacity = 0.22
            cardContainer.layer.shadowOffset = CGSize(width: 0, height: 4)
            cardContainer.layer.shadowRadius = 8
            cardContainer.isUserInteractionEnabled = true
            addSubview(cardContainer)

            // Remote Image View (if remote raster image provided)
            remoteImageView.translatesAutoresizingMaskIntoConstraints = false
            remoteImageView.contentMode = .scaleAspectFit
            remoteImageView.clipsToBounds = true
            remoteImageView.isHidden = true
            cardContainer.addSubview(remoteImageView)

            // Sparkle Icon View (default fallback)
            iconView.translatesAutoresizingMaskIntoConstraints = false
            cardContainer.addSubview(iconView)

            // Text Stack for Title and Subtitle
            textStackView.translatesAutoresizingMaskIntoConstraints = false
            textStackView.axis = .vertical
            textStackView.alignment = .leading
            textStackView.distribution = .fillProportionally
            textStackView.spacing = 2
            textStackView.isUserInteractionEnabled = false

            // Subtitle ("Try our")
            let firstText = widget.overlayOptions.floatingBoxTextFirst ?? "Try our"
            subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
            subtitleLabel.text = firstText
            subtitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            subtitleLabel.textColor = .white
            subtitleLabel.numberOfLines = 1
            subtitleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            textStackView.addArrangedSubview(subtitleLabel)

            // Title ("PRODUCT FINDER")
            let secondText = widget.overlayOptions.floatingBoxTextSecond ?? "PRODUCT FINDER"
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.text = secondText.uppercased()
            titleLabel.font = .systemFont(ofSize: 15, weight: .heavy)
            titleLabel.textColor = UIColor(red: 0.88, green: 0.63, blue: 0.35, alpha: 1.0) // Warm Golden Tan
            titleLabel.numberOfLines = 1
            titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

            // Apply slight kerning / tracking to uppercase title
            let attributedTitle = NSMutableAttributedString(string: secondText.uppercased())
            attributedTitle.addAttribute(.kern, value: 0.8, range: NSRange(location: 0, length: attributedTitle.length))
            titleLabel.attributedText = attributedTitle

            textStackView.addArrangedSubview(titleLabel)
            cardContainer.addSubview(textStackView)

            // Setup Width and Constraints
            let collapsedSize: CGFloat = 56
            widthConstraint = widthAnchor.constraint(equalToConstant: collapsedSize)
            let heightConstraint = heightAnchor.constraint(equalToConstant: collapsedSize)

            iconLeadingConstraint = iconView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 14)
            iconCenterConstraint = iconView.centerXAnchor.constraint(equalTo: cardContainer.centerXAnchor)

            NSLayoutConstraint.activate([
                widthConstraint,
                heightConstraint,

                cardContainer.topAnchor.constraint(equalTo: topAnchor),
                cardContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
                cardContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
                cardContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

                iconView.centerYAnchor.constraint(equalTo: cardContainer.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 40),
                iconView.heightAnchor.constraint(equalToConstant: 40),

                remoteImageView.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
                remoteImageView.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
                remoteImageView.widthAnchor.constraint(equalToConstant: 32),
                remoteImageView.heightAnchor.constraint(equalToConstant: 32),

                textStackView.centerYAnchor.constraint(equalTo: cardContainer.centerYAnchor),
                textStackView.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
                textStackView.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -20),
            ])

            // Tap Gesture on the Trigger
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            cardContainer.addGestureRecognizer(tapGesture)

            // Swipe Gestures to Collapse
            let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe))
            swipeRight.direction = .right
            cardContainer.addGestureRecognizer(swipeRight)

            let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe))
            swipeLeft.direction = .left
            cardContainer.addGestureRecognizer(swipeLeft)
        }

        // MARK: - State Management

        public func setState(_ state: TriggerState, animated: Bool = true) {
            guard currentState != state else { return }
            currentState = state
            applyState(state, animated: animated)
        }

        public func resetToCollapsed(animated: Bool) {
            autoCollapseTimer?.invalidate()
            autoCollapseTimer = nil
            setState(.collapsed, animated: animated)
        }

        private func applyState(_ state: TriggerState, animated: Bool) {
            let isExpanded = (state == .expanded)

            // Invalidate previous auto-collapse timer
            autoCollapseTimer?.invalidate()
            autoCollapseTimer = nil

            let expandedWidth: CGFloat = calculateExpandedWidth()
            widthConstraint.constant = isExpanded ? expandedWidth : 56

            if isExpanded {
                iconCenterConstraint.isActive = false
                iconLeadingConstraint.isActive = true
                stopBouncingAnimation()
                if widget.overlayOptions.isInitialActive {
                    scheduleAutoCollapse()
                }
            } else {
                iconLeadingConstraint.isActive = false
                iconCenterConstraint.isActive = true
                startBouncingAnimation()
            }

            let animations = {
                self.textStackView.alpha = isExpanded ? 1.0 : 0.0
                self.superview?.layoutIfNeeded()
            }

            if animated {
                UIView.animate(
                    withDuration: 0.4,
                    delay: 0,
                    usingSpringWithDamping: 0.78,
                    initialSpringVelocity: 0.5,
                    options: [.curveEaseInOut, .allowUserInteraction],
                    animations: animations,
                    completion: nil
                )
            } else {
                animations()
            }
        }

        private func calculateExpandedWidth() -> CGFloat {
            let subtitleWidth = subtitleLabel.intrinsicContentSize.width
            let titleWidth = titleLabel.intrinsicContentSize.width
            let textWidth = max(subtitleWidth, titleWidth)

            // 14 (icon leading) + 40 (icon width) + 8 (spacing) + textWidth + 20 (trailing)
            let total = 14 + 40 + 8 + textWidth + 20
            return max(total, 210)
        }

        // MARK: - Bouncing Animation

        private func startBouncingAnimation() {
            guard cardContainer.layer.animation(forKey: PoltioFloatingPillTriggerView.bounceAnimationKey) == nil else {
                return
            }

            let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
            // Subtle periodic bounce with smooth resting phase
            bounce.values = [0, 0, -8, 2, -4, 0, 0]
            bounce.keyTimes = [0, 0.45, 0.60, 0.75, 0.88, 0.96, 1.0]
            bounce.duration = 2.4
            bounce.repeatCount = .infinity
            bounce.isRemovedOnCompletion = false
            bounce.timingFunctions = [
                CAMediaTimingFunction(name: .easeInEaseOut),
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeIn),
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeIn),
                CAMediaTimingFunction(name: .easeInEaseOut),
            ]

            cardContainer.layer.add(bounce, forKey: PoltioFloatingPillTriggerView.bounceAnimationKey)
        }

        private func stopBouncingAnimation() {
            cardContainer.layer.removeAnimation(forKey: PoltioFloatingPillTriggerView.bounceAnimationKey)
            cardContainer.transform = .identity
        }

        // MARK: - Auto Collapse & Scroll Observers

        private func scheduleAutoCollapse() {
            autoCollapseTimer?.invalidate()
            autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.currentState == .expanded else { return }
                    self.setState(.collapsed, animated: true)
                }
            }
        }

        /// Notification posted when the host app scrolls or receives user touches outside the trigger.
        public static let didScrollNotification = Notification.Name("PoltioSDK.hostDidScroll")

        private func setupScrollObserver() {
            scrollObserver = NotificationCenter.default.addObserver(
                forName: PoltioFloatingPillTriggerView.didScrollNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, currentState == .expanded else { return }
                setState(.collapsed, animated: true)
            }
        }

        // MARK: - Image Loader

        private func loadImageIfNeeded() {
            guard let imageURL = widget.overlayOptions.resolvedImageUrl() else { return }

            let hasSvg = widget.overlayOptions.floatingSvg?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let isSvgFile = imageURL.pathExtension.lowercased() == "svg" || hasSvg

            imageDownloadTask?.cancel()
            imageDownloadTask = URLSession.shared.dataTask(with: imageURL) { [weak self] data, response, error in
                guard let self, let data, error == nil else {
                    return
                }

                let mimeType = response?.mimeType?.lowercased() ?? ""
                let utf8String = String(data: data, encoding: .utf8)
                let isSvgContent = isSvgFile || mimeType.contains("svg") || (utf8String?.contains("<svg") == true)

                if isSvgContent, let svgString = utf8String {
                    let html = """
                    <!DOCTYPE html>
                    <html>
                    <head>
                    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
                    <style>
                    * { margin: 0; padding: 0; box-sizing: border-box; }
                    html, body {
                        background: transparent;
                        width: 100%;
                        height: 100%;
                        display: flex;
                        align-items: center;
                        justify-content: center;
                        overflow: hidden;
                        color: #FFFFFF;
                    }
                    svg {
                        width: 100%;
                        height: 100%;
                        max-width: 32px;
                        max-height: 32px;
                    }
                    svg[style*="color"] {
                        color: #FFFFFF !important;
                    }
                    </style>
                    </head>
                    <body>
                    \(svgString)
                    </body>
                    </html>
                    """
                    DispatchQueue.main.async {
                        let webView = self.ensureSvgWebView()
                        webView.loadHTMLString(html, baseURL: nil)
                        webView.isHidden = false
                        self.remoteImageView.isHidden = true
                        self.iconView.isHidden = true
                    }
                } else if let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self.remoteImageView.image = image
                        self.remoteImageView.isHidden = false
                        // Only hide svgWebView if it was actually created — don't force it into
                        // existence here just to hide it.
                        self.svgWebView?.isHidden = true
                        self.iconView.isHidden = true
                    }
                }
            }
            imageDownloadTask?.resume()
        }

        // MARK: - Actions

        @objc private func handleTap() {
            if currentState == .collapsed {
                setState(.expanded, animated: true)
            } else {
                onOpenWidget()
            }
        }

        @objc private func handleSwipe() {
            if currentState == .expanded {
                setState(.collapsed, animated: true)
            }
        }
    }
#endif
