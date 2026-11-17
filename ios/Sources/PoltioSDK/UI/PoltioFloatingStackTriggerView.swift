#if canImport(UIKit)
    import UIKit

    /// The `stack` ("Multi") trigger: 2–5 glass cards fanned in 3D toward the middle of the screen, the
    /// first one in front. Any card, front or back, opens its own content. × folds the fan into a pill
    /// showing the front card (remembered for 48 hours); tapping the pill fans the cards out again.
    final class PoltioFloatingStackTriggerView: UIView, PoltioTriggerPresentable {
        enum TriggerState {
            case fanned
            case folded
        }

        /// How long a fold is remembered, matching web.
        static let foldRememberHours: Double = 48

        /// The fold's key in `PoltioTriggerDismissalStore`, kept apart from the widget's own public id,
        /// which would hide the trigger outright.
        static func foldKey(publicId: String) -> String {
            "stack-fold:\(publicId)"
        }

        private struct Layout {
            let cardSize: CGSize
            let pillSize: CGSize
            let fanStep: CGPoint
            let tilt: CGFloat
        }

        private static let expandedLayout = Layout(
            cardSize: CGSize(width: 168, height: 216), pillSize: CGSize(width: 250, height: 64),
            fanStep: CGPoint(x: 26, y: 12), tilt: 0.07
        )
        private static let compactLayout = Layout(
            cardSize: CGSize(width: 240, height: 56), pillSize: CGSize(width: 250, height: 64),
            fanStep: CGPoint(x: 14, y: 20), tilt: 0.035
        )

        private let widget: PoltioWidgetResponse
        private let cards: [PoltioStackCard]
        private let onOpenCard: (PoltioStackCard) -> Void
        private let layout: Layout
        /// Unit direction toward the middle of the screen: back cards fan away from the docked corner.
        private let fanDirection: CGPoint

        private(set) var state: TriggerState
        /// Front card first.
        private(set) var cardViews: [PoltioStackCardView] = []
        let closeButton = UIButton(type: .custom)
        let pillView: PoltioStackCardView

        /// Pending scroll-past-threshold reveal of a collapsed start.
        private var scrollUnfoldToken: PoltioScrollObserver.ScrollPastToken?

        init(widget: PoltioWidgetResponse, cards: [PoltioStackCard], onOpenCard: @escaping (PoltioStackCard) -> Void) {
            self.widget = widget
            self.cards = cards
            self.onOpenCard = onOpenCard
            let options = widget.overlayOptions
            layout = options.isStackCompact ? Self.compactLayout : Self.expandedLayout
            fanDirection = CGPoint(x: options.isLeftDocked ? 1 : -1, y: options.verticalPosition == "top" ? 1 : -1)
            pillView = PoltioStackCardView(card: cards[0], style: .pill, options: options)

            let foldRemembered = PoltioTriggerDismissalStore.isDismissed(publicId: Self.foldKey(publicId: widget.publicId))
            let startsCollapsed = options.floatingInitialPosition?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "collapsed"
            state = foldRemembered || startsCollapsed ? .folded : .fanned
            super.init(frame: .zero)

            setupView()
            if state == .fanned {
                fanOut(animated: true)
            } else {
                showPill(animated: false)
                // A collapsed start unfolds once the host scrolls past the threshold, like web; a
                // remembered fold stays folded.
                if !foldRemembered {
                    observeScrollToUnfold()
                }
            }
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            scrollUnfoldToken.map(PoltioScrollObserver.cancelScrollPast)
        }

        private func setupView() {
            translatesAutoresizingMaskIntoConstraints = false
            backgroundColor = .clear
            clipsToBounds = false

            let options = widget.overlayOptions
            let style: PoltioStackCardView.Style = options.isStackCompact ? .compact : .card
            cardViews = cards.map { PoltioStackCardView(card: $0, style: style, options: options) }

            // Back cards first, so the front card draws, and takes touches, on top.
            for (index, cardView) in cardViews.enumerated().reversed() {
                cardView.addTarget(self, action: #selector(handleCardTap(_:)), for: .touchUpInside)
                cardView.tag = index
                pin(cardView, size: layout.cardSize)
            }

            closeButton.translatesAutoresizingMaskIntoConstraints = false
            let xmark = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
            closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: xmark), for: .normal)
            closeButton.tintColor = PoltioOverlayOptions.resolvedColor(cards[0].textColor, fallback: .white)
            closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.18)
            closeButton.layer.cornerRadius = 13
            closeButton.addTarget(self, action: #selector(handleCloseTap), for: .touchUpInside)
            closeButton.accessibilityLabel = PoltioTriggerAccessibility.closeActionName
            closeButton.accessibilityHint = "Folds the cards into one button."
            addSubview(closeButton)
            let front = cardViews[0]
            NSLayoutConstraint.activate([
                closeButton.widthAnchor.constraint(equalToConstant: 26),
                closeButton.heightAnchor.constraint(equalToConstant: 26),
                closeButton.rightAnchor.constraint(equalTo: front.rightAnchor, constant: -8),
                options.isStackCompact
                    ? closeButton.centerYAnchor.constraint(equalTo: front.centerYAnchor)
                    : closeButton.topAnchor.constraint(equalTo: front.topAnchor, constant: 8),
            ])

            pillView.addTarget(self, action: #selector(handlePillTap), for: .touchUpInside)
            PoltioTriggerAccessibility.configure(
                pillView,
                label: PoltioTriggerAccessibility.label(from: [cards[0].title, cards[0].desc]),
                hint: "Shows all cards."
            )
            pin(pillView, size: layout.pillSize)

            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: layout.cardSize.width),
                heightAnchor.constraint(equalToConstant: layout.cardSize.height),
            ])
        }

        /// Pins `view` at the docked corner: the corner the overlay pins this view by.
        private func pin(_ view: UIView, size: CGSize) {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.widthAnchor.constraint(equalToConstant: size.width),
                view.heightAnchor.constraint(equalToConstant: size.height),
                fanDirection.x > 0 ? view.leftAnchor.constraint(equalTo: leftAnchor) : view.rightAnchor.constraint(equalTo: rightAnchor),
                fanDirection.y > 0 ? view.topAnchor.constraint(equalTo: topAnchor) : view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        /// Where card `index` rests in the fan: shifted toward the middle of the screen, pushed back, tilted.
        func fanTransform(index: Int) -> CATransform3D {
            guard index > 0 else { return CATransform3DIdentity }
            let step = CGFloat(index)
            var transform = CATransform3DIdentity
            transform.m34 = -1 / 800
            transform = CATransform3DTranslate(transform, fanDirection.x * step * layout.fanStep.x, fanDirection.y * step * layout.fanStep.y, -step * 24)
            transform = CATransform3DRotate(transform, -fanDirection.x * fanDirection.y * step * layout.tilt, 0, 0, 1)
            return CATransform3DRotate(transform, fanDirection.x * step * 0.12, 0, 1, 0)
        }

        // MARK: - Hit testing

        /// Back cards lean out of this view's bounds, so any visible child counts; empty space passes
        /// touches through to the host app.
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            subviews.contains { child in
                !child.isHidden && child.alpha > 0.01 && child.point(inside: convert(point, to: child), with: event)
            }
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let hit = super.hitTest(point, with: event)
            return hit === self ? nil : hit
        }

        // MARK: - State

        func setState(_ newState: TriggerState, animated: Bool) {
            guard state != newState else { return }
            state = newState
            if newState == .fanned {
                fanOut(animated: animated)
            } else {
                showPill(animated: animated)
            }
        }

        /// Closing a card's experience brings the stack back unchanged.
        func resetToCollapsed(animated _: Bool) {}

        private var animates: Bool {
            !UIAccessibility.isReduceMotionEnabled
        }

        /// The staggered cascade: each card leaves the front position for its place in the fan, then a
        /// soft glow crosses the cards three times to hint they're tappable.
        private func fanOut(animated: Bool) {
            let animate = animated && animates
            UIView.animate(withDuration: animate ? 0.2 : 0, animations: { self.pillView.alpha = 0 }, completion: { _ in
                if self.state == .fanned {
                    self.pillView.isHidden = true
                }
            })
            closeButton.isHidden = false
            for (index, cardView) in cardViews.enumerated() {
                cardView.isHidden = false
                guard animate else {
                    cardView.alpha = 1
                    cardView.transform3D = fanTransform(index: index)
                    continue
                }
                cardView.alpha = 0
                cardView.transform3D = CATransform3DMakeScale(0.85, 0.85, 1)
                UIView.animate(
                    withDuration: 0.55, delay: 0.09 * Double(index),
                    usingSpringWithDamping: 0.78, initialSpringVelocity: 0.4,
                    options: [.curveEaseOut, .allowUserInteraction],
                    animations: {
                        cardView.alpha = 1
                        cardView.transform3D = self.fanTransform(index: index)
                    }
                )
                cardView.playGlow(after: 0.6 + 0.09 * Double(cardViews.count) + 0.15 * Double(index))
            }
            closeButton.alpha = animate ? 0 : 1
            UIView.animate(withDuration: animate ? 0.3 : 0, delay: animate ? 0.3 : 0, options: .allowUserInteraction) {
                self.closeButton.alpha = 1
            }
            accessibilityElements = [cardViews[0], closeButton] + cardViews.dropFirst().map { $0 as Any }
        }

        /// Cards gather onto the front card and fade while the pill takes their place.
        private func showPill(animated: Bool) {
            let animate = animated && animates
            cardViews.forEach { $0.stopGlow() }
            UIView.animate(withDuration: animate ? 0.28 : 0, animations: {
                for cardView in self.cardViews {
                    cardView.alpha = 0
                    cardView.transform3D = CATransform3DMakeScale(0.9, 0.9, 1)
                }
                self.closeButton.alpha = 0
            }, completion: { _ in
                guard self.state == .folded else { return }
                self.cardViews.forEach { $0.isHidden = true }
                self.closeButton.isHidden = true
            })
            pillView.isHidden = false
            pillView.alpha = 0
            pillView.transform = animate ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity
            UIView.animate(
                withDuration: animate ? 0.4 : 0, delay: animate ? 0.15 : 0,
                usingSpringWithDamping: 0.8, initialSpringVelocity: 0.4,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: {
                    self.pillView.alpha = 1
                    self.pillView.transform = .identity
                }
            )
            accessibilityElements = [pillView]
        }

        // MARK: - Actions

        @objc private func handleCardTap(_ sender: PoltioStackCardView) {
            guard cards.indices.contains(sender.tag) else { return }
            onOpenCard(cards[sender.tag])
        }

        @objc private func handleCloseTap() {
            stopObservingScroll()
            PoltioTriggerDismissalStore.recordDismissal(publicId: Self.foldKey(publicId: widget.publicId), hours: Self.foldRememberHours)
            setState(.folded, animated: true)
        }

        @objc private func handlePillTap() {
            stopObservingScroll()
            setState(.fanned, animated: true)
        }

        // MARK: - Scroll to unfold

        private func observeScrollToUnfold() {
            scrollUnfoldToken = PoltioScrollObserver.onScrollPast(for: self, threshold: CGFloat(widget.overlayOptions.floatingScrollThreshold)) { [weak self] in
                DispatchQueue.main.async {
                    self?.scrollUnfoldToken = nil
                    self?.setState(.fanned, animated: true)
                }
            }
        }

        private func stopObservingScroll() {
            scrollUnfoldToken.map(PoltioScrollObserver.cancelScrollPast)
            scrollUnfoldToken = nil
        }
    }

    /// One glass card of the stack trigger, drawn as a vertical card, a compact pill (image and title),
    /// or the folded pill (image, title and description). The whole card is one button.
    final class PoltioStackCardView: UIControl {
        enum Style {
            case card
            case compact
            case pill
        }

        let card: PoltioStackCard
        private let glowLayer = CAGradientLayer()
        private let tintLayer = CAGradientLayer()
        private let surface = UIView()
        private var imageLoader: PoltioTriggerIconLoader?
        private static let glowAnimationKey = "poltio.stack.glow"

        init(card: PoltioStackCard, style: Style, options: PoltioOverlayOptions) {
            self.card = card
            super.init(frame: .zero)

            let cardColor = PoltioOverlayOptions.resolvedColor(card.bg, fallback: options.resolvedBgColor)
            let textColor = PoltioOverlayOptions.resolvedColor(card.textColor, fallback: .white)
            let cornerRadius: CGFloat = style == .card ? 22 : 28

            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.2
            layer.shadowRadius = 12
            layer.shadowOffset = CGSize(width: 0, height: 6)

            surface.translatesAutoresizingMaskIntoConstraints = false
            surface.isUserInteractionEnabled = false
            surface.layer.cornerRadius = cornerRadius
            surface.layer.borderWidth = 1
            surface.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
            surface.clipsToBounds = true
            addSubview(surface)
            pinEdges(surface, to: self)

            let glass = Self.glassView()
            glass.translatesAutoresizingMaskIntoConstraints = false
            surface.addSubview(glass)
            pinEdges(glass, to: surface)

            // The card color as a gradient from a lighter shade, at the card's opacity, over the glass.
            tintLayer.colors = [Self.lighter(cardColor).cgColor, cardColor.cgColor]
            tintLayer.startPoint = CGPoint(x: 0, y: 0)
            tintLayer.endPoint = CGPoint(x: 1, y: 1)
            tintLayer.opacity = Float(card.alpha)
            surface.layer.addSublayer(tintLayer)

            let imageSize: CGFloat = switch style {
            case .card: 52
            case .compact: 36
            case .pill: 44
            }
            let imageSlot = UIView()
            imageSlot.translatesAutoresizingMaskIntoConstraints = false
            imageSlot.backgroundColor = cardColor
            imageSlot.layer.cornerRadius = imageSize / 2
            imageSlot.layer.borderWidth = 1
            imageSlot.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
            imageSlot.clipsToBounds = true
            surface.addSubview(imageSlot)
            if let url = card.imageUrl {
                let loader = PoltioTriggerIconLoader(container: imageSlot, size: imageSize, contentMode: .scaleAspectFill)
                loader.load(url: url, centeredOn: imageSlot) {}
                imageLoader = loader
            }

            let titleLabel = UILabel()
            titleLabel.text = card.title
            titleLabel.textColor = textColor
            titleLabel.font = options.resolvedFont(size: style == .card ? 16 : 14, weight: .bold)
            titleLabel.numberOfLines = style == .card ? 2 : 1

            let descLabel = UILabel()
            descLabel.text = card.desc
            descLabel.textColor = textColor.withAlphaComponent(0.9)
            descLabel.font = options.resolvedFont(size: style == .card ? 13 : 12)
            descLabel.numberOfLines = style == .card ? 3 : 1

            let texts = UIStackView(arrangedSubviews: style == .compact ? [titleLabel] : [titleLabel, descLabel])
            texts.translatesAutoresizingMaskIntoConstraints = false
            texts.axis = .vertical
            texts.spacing = style == .card ? 4 : 1
            texts.alignment = .leading
            descLabel.isHidden = card.desc?.isEmpty ?? true
            surface.addSubview(texts)

            switch style {
            case .card:
                let button = UILabel()
                button.translatesAutoresizingMaskIntoConstraints = false
                let buttonText = card.button?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                button.text = buttonText.isEmpty ? "Start" : buttonText
                button.textColor = .white
                button.textAlignment = .center
                button.font = options.resolvedFont(size: 14, weight: .bold)
                button.backgroundColor = PoltioOverlayOptions.resolvedColor(card.buttonBg, fallback: Self.darker(cardColor))
                button.layer.cornerRadius = 17
                button.clipsToBounds = true
                surface.addSubview(button)
                NSLayoutConstraint.activate([
                    imageSlot.topAnchor.constraint(equalTo: surface.topAnchor, constant: 14),
                    imageSlot.leftAnchor.constraint(equalTo: surface.leftAnchor, constant: 14),
                    texts.topAnchor.constraint(equalTo: imageSlot.bottomAnchor, constant: 10),
                    texts.leftAnchor.constraint(equalTo: surface.leftAnchor, constant: 14),
                    texts.rightAnchor.constraint(equalTo: surface.rightAnchor, constant: -14),
                    texts.bottomAnchor.constraint(lessThanOrEqualTo: button.topAnchor, constant: -8),
                    button.leftAnchor.constraint(equalTo: surface.leftAnchor, constant: 14),
                    button.rightAnchor.constraint(equalTo: surface.rightAnchor, constant: -14),
                    button.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -14),
                    button.heightAnchor.constraint(equalToConstant: 34),
                ])
            case .compact, .pill:
                NSLayoutConstraint.activate([
                    imageSlot.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
                    imageSlot.leftAnchor.constraint(equalTo: surface.leftAnchor, constant: 10),
                    texts.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
                    texts.leftAnchor.constraint(equalTo: imageSlot.rightAnchor, constant: 10),
                    // Compact cards leave room for the front card's ×.
                    texts.rightAnchor.constraint(equalTo: surface.rightAnchor, constant: style == .compact ? -40 : -16),
                ])
            }
            NSLayoutConstraint.activate([
                imageSlot.widthAnchor.constraint(equalToConstant: imageSize),
                imageSlot.heightAnchor.constraint(equalToConstant: imageSize),
            ])

            glowLayer.colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.withAlphaComponent(0.4).cgColor, UIColor.white.withAlphaComponent(0).cgColor]
            glowLayer.startPoint = CGPoint(x: 0, y: 0.3)
            glowLayer.endPoint = CGPoint(x: 1, y: 0.7)
            // Parked before the card's start edge, so nothing shows once the animation ends.
            glowLayer.locations = [-0.6, -0.3, 0]
            surface.layer.addSublayer(glowLayer)

            PoltioTriggerAccessibility.configure(self, label: PoltioTriggerAccessibility.label(from: [card.title, card.desc, style == .card ? card.button : nil]))
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            tintLayer.frame = surface.bounds
            glowLayer.frame = surface.bounds
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: surface.layer.cornerRadius).cgPath
        }

        override var isHighlighted: Bool {
            didSet { surface.alpha = isHighlighted ? 0.8 : 1 }
        }

        /// Sweeps a soft highlight across the card three times, starting after `delay`.
        func playGlow(after delay: CFTimeInterval) {
            let sweep = CABasicAnimation(keyPath: "locations")
            sweep.fromValue = [-0.6, -0.3, 0]
            sweep.toValue = [1, 1.3, 1.6]
            sweep.duration = 1.3
            sweep.repeatCount = 3
            sweep.beginTime = CACurrentMediaTime() + delay
            sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glowLayer.add(sweep, forKey: Self.glowAnimationKey)
        }

        func stopGlow() {
            glowLayer.removeAnimation(forKey: Self.glowAnimationKey)
        }

        var isGlowing: Bool {
            glowLayer.animation(forKey: Self.glowAnimationKey) != nil
        }

        /// iOS 26 system glass where available, a thin blur otherwise.
        private static func glassView() -> UIVisualEffectView {
            #if compiler(>=6.2)
                if #available(iOS 26.0, *) {
                    return UIVisualEffectView(effect: UIGlassEffect())
                }
            #endif
            return UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        }

        static func lighter(_ color: UIColor) -> UIColor {
            mix(color, with: .white, amount: 0.35)
        }

        static func darker(_ color: UIColor) -> UIColor {
            mix(color, with: .black, amount: 0.3)
        }

        private static func mix(_ color: UIColor, with other: UIColor, amount: CGFloat) -> UIColor {
            var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            guard color.getRed(&r1, green: &g1, blue: &b1, alpha: &a1), other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else {
                return color
            }
            return UIColor(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount, blue: b1 + (b2 - b1) * amount, alpha: a1)
        }

        private func pinEdges(_ view: UIView, to container: UIView) {
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                view.leftAnchor.constraint(equalTo: container.leftAnchor),
                view.rightAnchor.constraint(equalTo: container.rightAnchor),
            ])
        }
    }
#endif
