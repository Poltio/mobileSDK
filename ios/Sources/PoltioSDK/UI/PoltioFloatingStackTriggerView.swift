#if canImport(UIKit)
    import UIKit

    /// Web's em on phones (13px): the stack's sizes are web's, in em.
    private let em: CGFloat = 13

    /// The `stack` ("Multi") trigger: 2–5 glass cards stacked toward the middle of the screen, the first
    /// one in front. Back cards stand upright and only peek out: odd ones past the front card's top edge,
    /// even ones past its side. Any card, front or back, opens its own content. × folds the stack into a
    /// pill showing the front card (remembered for 48 hours); tapping the pill brings the cards back.
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

        /// Where back card `index` (1-based) rests, in em toward the middle of the screen: odd ones peek
        /// past the front card's top edge, even ones past its side. Compact pills only stack upward.
        static func place(_ index: Int, compact: Bool) -> (up: Bool, side: CGFloat, rise: CGFloat) {
            if compact {
                return (true, 0, 2.9 * CGFloat(index))
            }
            let step = CGFloat((index + 1) / 2 - 1)
            return index % 2 == 1 ? (true, 0.5 + 0.8 * step, 3.4 + 2.8 * step) : (false, 3.6 + 2.8 * step, 1.6 + 0.5 * step)
        }

        private let widget: PoltioWidgetResponse
        private let cards: [PoltioStackCard]
        private let onOpenCard: (PoltioStackCard) -> Void
        private let isCompact: Bool
        private let cardSize: CGSize
        /// Unit direction toward the middle of the screen: back cards peek out away from the docked corner.
        private let fanDirection: CGPoint
        /// Set once the visitor opens a card or folds them: the light sweep was only a hint.
        private var hinted = false

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
            isCompact = options.isStackCompact
            cardSize = isCompact ? CGSize(width: 16 * em, height: 3.75 * em) : CGSize(width: 13.5 * em, height: 16.5 * em)
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
            cardViews = cards.enumerated().map { index, card in
                let style: PoltioStackCardView.Style = if isCompact {
                    .compact
                } else if index == 0 {
                    .card
                } else {
                    Self.place(index, compact: false).up ? .up : .side
                }
                return PoltioStackCardView(card: card, style: style, options: options)
            }

            // Back cards first, so the front card draws, and takes touches, on top.
            for (index, cardView) in cardViews.enumerated().reversed() {
                cardView.addTarget(self, action: #selector(handleCardTap(_:)), for: .touchUpInside)
                cardView.tag = index
                pin(cardView, width: cardSize.width, height: cardSize.height)
            }

            closeButton.translatesAutoresizingMaskIntoConstraints = false
            let xmark = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
            closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: xmark), for: .normal)
            closeButton.tintColor = PoltioOverlayOptions.resolvedColor(cards[0].textColor, fallback: .white)
            closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.28)
            closeButton.layer.cornerRadius = 13
            closeButton.layer.shadowColor = UIColor.black.cgColor
            closeButton.layer.shadowOpacity = 0.2
            closeButton.layer.shadowRadius = 3
            closeButton.layer.shadowOffset = CGSize(width: 0, height: 2)
            closeButton.addTarget(self, action: #selector(handleCloseTap), for: .touchUpInside)
            closeButton.accessibilityLabel = PoltioTriggerAccessibility.closeActionName
            closeButton.accessibilityHint = "Folds the cards into one button."
            addSubview(closeButton)
            let front = cardViews[0]
            // Compact: beside the front pill, toward the middle of the screen, clear of the pills above it.
            let placement = if !isCompact {
                [closeButton.topAnchor.constraint(equalTo: front.topAnchor, constant: 8), closeButton.rightAnchor.constraint(equalTo: front.rightAnchor, constant: -8)]
            } else if fanDirection.x > 0 {
                [closeButton.centerYAnchor.constraint(equalTo: front.centerYAnchor), closeButton.leftAnchor.constraint(equalTo: front.rightAnchor, constant: 4.5)]
            } else {
                [closeButton.centerYAnchor.constraint(equalTo: front.centerYAnchor), closeButton.rightAnchor.constraint(equalTo: front.leftAnchor, constant: -4.5)]
            }
            NSLayoutConstraint.activate(placement + [
                closeButton.widthAnchor.constraint(equalToConstant: 26),
                closeButton.heightAnchor.constraint(equalToConstant: 26),
            ])

            pillView.addTarget(self, action: #selector(handlePillTap), for: .touchUpInside)
            PoltioTriggerAccessibility.configure(
                pillView,
                label: PoltioTriggerAccessibility.label(from: [cards[0].title, cards[0].desc]),
                hint: "Shows all cards."
            )
            // As wide as its content, up to web's 21em.
            pin(pillView, width: nil, height: 4.5 * em)
            pillView.widthAnchor.constraint(lessThanOrEqualToConstant: 21 * em).isActive = true

            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: cardSize.width),
                heightAnchor.constraint(equalToConstant: cardSize.height),
            ])
        }

        /// Pins `view` at the docked corner: the corner the overlay pins this view by.
        private func pin(_ view: UIView, width: CGFloat?, height: CGFloat) {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.heightAnchor.constraint(equalToConstant: height),
                fanDirection.x > 0 ? view.leftAnchor.constraint(equalTo: leftAnchor) : view.rightAnchor.constraint(equalTo: rightAnchor),
                fanDirection.y > 0 ? view.topAnchor.constraint(equalTo: topAnchor) : view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            width.map { view.widthAnchor.constraint(equalToConstant: $0).isActive = true }
        }

        /// Where card `index` rests: upright, shifted toward the middle of the screen and pushed back, so
        /// the perspective gives the depth.
        func fanTransform(index: Int) -> CATransform3D {
            guard index > 0 else { return CATransform3DIdentity }
            let place = Self.place(index, compact: isCompact)
            var transform = CATransform3DIdentity
            transform.m34 = -1 / 900
            return CATransform3DTranslate(transform, fanDirection.x * place.side * em, fanDirection.y * place.rise * em, CGFloat(-30 * index))
        }

        // MARK: - Hit testing

        /// Back cards peek out of this view's bounds, so any visible child counts; empty space passes
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

        /// The staggered cascade: each card rises from the docked edge into its place, then light sweeps
        /// across the cards three times to hint they're tappable.
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
                cardView.transform3D = CATransform3DScale(CATransform3DMakeTranslation(0, -fanDirection.y * 1.5 * em, 0), 0.9, 0.9, 1)
                UIView.animate(
                    withDuration: 0.55, delay: 0.09 * Double(index),
                    usingSpringWithDamping: 0.8, initialSpringVelocity: 0.4,
                    options: [.curveEaseOut, .allowUserInteraction],
                    animations: {
                        cardView.alpha = 1
                        cardView.transform3D = self.fanTransform(index: index)
                    }
                )
                if !hinted {
                    cardView.playGlow(after: 0.7 + 0.3 * Double(index))
                }
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
            hinted = true
            cardViews.forEach { $0.stopGlow() }
            onOpenCard(cards[sender.tag])
        }

        @objc private func handleCloseTap() {
            stopObservingScroll()
            hinted = true
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

    /// One glass card of the stack trigger, drawn as the front card, a back card peeking past the front
    /// one's top edge (`up`) or side (`side`), a compact pill, or the folded pill. The whole card is one
    /// button.
    final class PoltioStackCardView: UIControl {
        enum Style {
            case card
            case up
            case side
            case compact
            case pill
        }

        let card: PoltioStackCard
        let style: Style
        /// A CSS drop shadow, in em.
        private typealias Drop = (offset: CGFloat, blur: CGFloat, spread: CGFloat, alpha: Float)
        /// Web's: a hairline edge, a contact shadow and two steps of lift.
        private static let cardDrops: [Drop] = [(0, 0, 0.5 / 13, 0.1), (1 / 13, 2 / 13, 0, 0.12), (0.5, 1, -0.4, 0.25), (1.4, 2.8, -0.8, 0.45)]
        private static let imageDrops: [Drop] = [(0.35, 0.9, -0.25, 0.45)]

        private let lift = PoltioStackCardView.outerShadow(PoltioStackCardView.cardDrops)
        private let surface = UIView()
        private let tint = UIView()
        private let sheen = CAGradientLayer()
        private let edge = UIView()
        private var glints: [CAGradientLayer] = []
        /// How far each corner's light reaches.
        private let glintRadius: CGFloat
        private var insetShadows: [(layer: CAShapeLayer, spread: CGFloat)] = []
        private let glowLayer = CAGradientLayer()
        private var imageLoader: PoltioTriggerIconLoader?
        private static let glowAnimationKey = "poltio.stack.glow"
        private static let shade = UIColor(red: 40 / 255, green: 22 / 255, blue: 12 / 255, alpha: 1)

        init(card: PoltioStackCard, style: Style, options: PoltioOverlayOptions) {
            self.card = card
            self.style = style
            glintRadius = (style == .compact || style == .pill ? 1.8 : 3) * em
            super.init(frame: .zero)

            let cardColor = PoltioOverlayOptions.resolvedColor(card.bg, fallback: options.resolvedBgColor)
            let textColor = PoltioOverlayOptions.resolvedColor(card.textColor, fallback: .white)
            let buttonColor = PoltioOverlayOptions.resolvedColor(card.buttonBg, fallback: Self.darker(cardColor))
            let font = { (size: CGFloat, weight: UIFont.Weight) in options.resolvedFont(size: size * em, weight: weight) }

            // A slab of milky glass lifted off the page.
            layer.addSublayer(lift)

            surface.translatesAutoresizingMaskIntoConstraints = false
            surface.isUserInteractionEnabled = false
            surface.layer.cornerRadius = switch style {
            case .card, .up, .side: 1.5 * em
            case .compact: 1.875 * em
            case .pill: 1.4 * em
            }
            surface.clipsToBounds = true
            addSubview(surface)
            Self.pinEdges(surface, to: self)

            let glass = Self.glassView()
            glass.translatesAutoresizingMaskIntoConstraints = false
            surface.addSubview(glass)
            Self.pinEdges(glass, to: surface)

            // The card color under a white sheen, both at the card's opacity.
            tint.translatesAutoresizingMaskIntoConstraints = false
            tint.isUserInteractionEnabled = false
            tint.backgroundColor = cardColor
            tint.alpha = card.alpha
            sheen.colors = [0.5, 0.12, 0.04, 0.2].map { UIColor.white.withAlphaComponent($0).cgColor }
            sheen.locations = [0, 0.38, 0.62, 1]
            sheen.startPoint = CGPoint(x: 0.29, y: 0.05)
            sheen.endPoint = CGPoint(x: 0.71, y: 0.95)
            tint.layer.addSublayer(sheen)
            surface.addSubview(tint)
            Self.pinEdges(tint, to: surface)

            // The slab's thickness, above the tint so any opacity shows it: light pooled in the corners,
            // strongest where it enters top-left, and a soft bevel along the edges.
            edge.translatesAutoresizingMaskIntoConstraints = false
            edge.isUserInteractionEnabled = false
            surface.addSubview(edge)
            Self.pinEdges(edge, to: surface)
            glints = [0.9, 0.7, 0.4, 0.35].map { alpha in
                let glint = CAGradientLayer()
                glint.type = .radial
                glint.colors = [UIColor.white.withAlphaComponent(alpha).cgColor, UIColor.white.withAlphaComponent(0).cgColor]
                glint.startPoint = CGPoint(x: 0.5, y: 0.5)
                glint.endPoint = CGPoint(x: 1, y: 1)
                edge.layer.addSublayer(glint)
                return glint
            }
            // Web lists these top first, so they're added bottom first.
            addInsetShadow(.white, opacity: 0.2, offset: .zero, blur: 2 * em)
            addInsetShadow(Self.shade, opacity: 0.22, offset: CGSize(width: 0, height: -0.6 * em), blur: em, spread: -0.6 * em)
            addInsetShadow(.white, opacity: 0.45, offset: CGSize(width: -0.35 * em, height: -0.4 * em), blur: 0.7 * em, spread: -0.3 * em)
            addInsetShadow(.white, opacity: 0.8, offset: CGSize(width: 0.35 * em, height: 0.4 * em), blur: 0.6 * em, spread: -0.3 * em)

            let buttonText = card.button?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cta = { (size: CGFloat, padding: CGFloat) in
                PoltioStackGlossView(
                    color: buttonColor,
                    content: Self.label((buttonText.isEmpty ? "Start" : buttonText).localizedUppercase, font: font(size, .bold), color: .white, kern: 0.1 * size * em),
                    unit: size * em, padding: padding * size * em
                )
            }
            let image = { (size: CGFloat) in self.makeImage(size: size * em, ring: (options.isStackCompact ? 0.15 : 0.24) * em) }

            switch style {
            case .card:
                let head = image(4.5)
                let title = Self.label(card.title, font: font(1.05, .bold), color: textColor, lines: 2)
                let name = UIStackView(arrangedSubviews: [title, Self.line(width: 1.6 * em, color: textColor)])
                name.axis = .vertical
                name.alignment = .leading
                name.spacing = 0.5 * em
                let desc = Self.label(card.desc ?? "", font: font(0.85, .regular), color: textColor, lines: 3, lineSpacing: 0.2 * 0.85 * em)
                let button = cta(0.85, 1)
                [head, name, desc, button].forEach(surface.addSubview)
                name.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    head.topAnchor.constraint(equalTo: surface.topAnchor, constant: em),
                    head.leftAnchor.constraint(equalTo: surface.leftAnchor, constant: em),
                    name.centerYAnchor.constraint(equalTo: head.centerYAnchor),
                    name.leftAnchor.constraint(equalTo: head.rightAnchor, constant: 0.65 * em),
                    name.rightAnchor.constraint(equalTo: surface.rightAnchor, constant: -em),
                    desc.topAnchor.constraint(equalTo: head.bottomAnchor, constant: 0.75 * em),
                    desc.leftAnchor.constraint(equalTo: surface.leftAnchor, constant: em),
                    desc.rightAnchor.constraint(equalTo: surface.rightAnchor, constant: -em),
                    desc.bottomAnchor.constraint(lessThanOrEqualTo: button.topAnchor, constant: -0.55 * em),
                    button.leftAnchor.constraint(equalTo: surface.leftAnchor, constant: em),
                    button.rightAnchor.constraint(equalTo: surface.rightAnchor, constant: -em),
                    button.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -em),
                    button.heightAnchor.constraint(equalToConstant: 2.75 * 0.85 * em),
                ])
            case .up:
                // Its full-size image moves into the strip showing past the front card's edge, beside a
                // spaced label.
                let fromTop = options.verticalPosition == "top"
                let head = image(4.5)
                let title = Self.label(card.title.localizedUppercase, font: font(0.75, .bold), color: textColor, kern: 0.14 * 0.75 * em)
                [head, title].forEach(surface.addSubview)
                NSLayoutConstraint.activate([
                    head.leftAnchor.constraint(equalTo: surface.leftAnchor, constant: em),
                    fromTop ? head.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -0.7 * em) : head.topAnchor.constraint(equalTo: surface.topAnchor, constant: 0.7 * em),
                    title.leftAnchor.constraint(equalTo: head.rightAnchor, constant: 0.65 * em),
                    title.rightAnchor.constraint(lessThanOrEqualTo: surface.rightAnchor, constant: -em),
                    fromTop ? title.bottomAnchor.constraint(equalTo: head.bottomAnchor, constant: -1.15 * 0.75 * em) : title.topAnchor.constraint(equalTo: head.topAnchor, constant: 1.15 * 0.75 * em),
                ])
            case .side:
                // Its full-size image moves to the bottom of the strip showing past the front card's side,
                // under a vertical label.
                let onLeft = !options.isLeftDocked
                let head = image(4.5)
                surface.addSubview(head)
                NSLayoutConstraint.activate([
                    head.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -0.7 * em),
                    onLeft ? head.leftAnchor.constraint(equalTo: surface.leftAnchor, constant: 0.7 * em) : head.rightAnchor.constraint(equalTo: surface.rightAnchor, constant: -0.7 * em),
                ])
                addSpine(font: font(0.75, .bold), color: textColor, onLeft: onLeft)
            case .compact:
                let head = image(2.85)
                let title = Self.label(card.title, font: font(0.95, .bold), color: textColor)
                let arrowIcon = UIImageView(image: UIImage(systemName: "arrow.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 0.85 * em, weight: .bold)))
                arrowIcon.tintColor = textColor
                let arrow = PoltioStackGlossView(color: buttonColor, content: arrowIcon, unit: em)
                [head, title, arrow].forEach(surface.addSubview)
                NSLayoutConstraint.activate([
                    head.leftAnchor.constraint(equalTo: surface.leftAnchor, constant: 0.45 * em),
                    head.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
                    title.leftAnchor.constraint(equalTo: head.rightAnchor, constant: 0.6 * em),
                    title.rightAnchor.constraint(equalTo: arrow.leftAnchor, constant: -0.6 * em),
                    title.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
                    arrow.rightAnchor.constraint(equalTo: surface.rightAnchor, constant: -0.6 * em),
                    arrow.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
                    arrow.widthAnchor.constraint(equalToConstant: 1.9 * em),
                    arrow.heightAnchor.constraint(equalToConstant: 1.9 * em),
                ])
            case .pill:
                let head = image(3.3)
                let title = Self.label(card.title, font: font(0.95, .bold), color: textColor)
                let line = Self.line(width: 1.3 * em, color: textColor)
                line.isHidden = options.isStackCompact
                let desc = Self.label(card.desc ?? "", font: font(0.75, .regular), color: textColor)
                desc.isHidden = card.desc?.isEmpty ?? true
                let texts = UIStackView(arrangedSubviews: [title, line, desc])
                texts.translatesAutoresizingMaskIntoConstraints = false
                texts.axis = .vertical
                texts.alignment = .leading
                texts.setCustomSpacing(0.3 * em, after: title)
                texts.setCustomSpacing(0.25 * em, after: line)
                // Past web's max width, the texts truncate before the button does.
                [title, desc].forEach { $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
                let button = cta(0.75, 1.1)
                [head, texts, button].forEach(surface.addSubview)
                NSLayoutConstraint.activate([
                    head.leftAnchor.constraint(equalTo: surface.leftAnchor, constant: 0.55 * em),
                    head.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
                    texts.leftAnchor.constraint(equalTo: head.rightAnchor, constant: 0.7 * em),
                    texts.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
                    button.leftAnchor.constraint(equalTo: texts.rightAnchor, constant: 0.7 * em),
                    button.rightAnchor.constraint(equalTo: surface.rightAnchor, constant: -0.55 * em),
                    button.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
                    button.heightAnchor.constraint(equalToConstant: 2.4 * 0.75 * em),
                ])
            }

            glowLayer.colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.withAlphaComponent(0.5).cgColor, UIColor.white.withAlphaComponent(0).cgColor]
            glowLayer.startPoint = CGPoint(x: 0.05, y: 0.29)
            glowLayer.endPoint = CGPoint(x: 0.95, y: 0.71)
            // Parked before the card's start edge, so nothing shows once the animation ends.
            glowLayer.locations = [-0.6, -0.3, 0]
            surface.layer.addSublayer(glowLayer)

            PoltioTriggerAccessibility.configure(self, label: PoltioTriggerAccessibility.label(from: [card.title, card.desc, [.card, .up, .side].contains(style) ? card.button : nil]))
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let bounds = surface.bounds
            let radius = min(surface.layer.cornerRadius, bounds.height / 2)
            // A negative CSS spread grows the hole the inset shadow is cast into.
            for (shadow, spread) in insetShadows {
                shadow.path = Self.frame(around: UIBezierPath(roundedRect: bounds.insetBy(dx: spread, dy: spread), cornerRadius: radius - spread))
            }
            let corners = [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.minY), CGPoint(x: bounds.minX, y: bounds.maxY)]
            for (glint, corner) in zip(glints, corners) {
                glint.frame = CGRect(x: corner.x - glintRadius, y: corner.y - glintRadius, width: 2 * glintRadius, height: 2 * glintRadius)
            }
            sheen.frame = tint.bounds
            glowLayer.frame = bounds
            Self.shape(lift, Self.cardDrops, bounds: self.bounds, cornerRadius: radius)
        }

        override var isHighlighted: Bool {
            didSet { surface.alpha = isHighlighted ? 0.8 : 1 }
        }

        /// Sweeps a band of light across the glass three times, starting after `delay`.
        func playGlow(after delay: CFTimeInterval) {
            let sweep = CABasicAnimation(keyPath: "locations")
            sweep.fromValue = [-0.6, -0.3, 0]
            sweep.toValue = [1, 1.3, 1.6]
            sweep.duration = 1.1
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

        /// Warm drop shadows that only fall outside the shape, as CSS draws them, so see-through glass
        /// doesn't show them from below.
        private static func outerShadow(_ drops: [Drop]) -> CALayer {
            let lift = CALayer()
            for drop in drops {
                let step = CALayer()
                step.shadowColor = shade.cgColor
                step.shadowOpacity = drop.alpha
                step.shadowRadius = drop.blur / 2 * em
                step.shadowOffset = CGSize(width: 0, height: drop.offset * em)
                lift.addSublayer(step)
            }
            let cutout = CAShapeLayer()
            cutout.fillRule = .evenOdd
            lift.mask = cutout
            return lift
        }

        /// Fits an `outerShadow` to a rounded shape.
        private static func shape(_ lift: CALayer, _ drops: [Drop], bounds: CGRect, cornerRadius: CGFloat) {
            lift.frame = bounds
            for (step, drop) in zip(lift.sublayers ?? [], drops) {
                let spread = drop.spread * em
                step.frame = bounds
                step.shadowPath = UIBezierPath(roundedRect: bounds.insetBy(dx: -spread, dy: -spread), cornerRadius: max(cornerRadius + spread, 0)).cgPath
            }
            (lift.mask as? CAShapeLayer)?.path = frame(around: UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius))
        }

        /// `hole` inside a wide frame: the frame casts a shape's inset shadow, or masks off its inside.
        private static func frame(around hole: UIBezierPath) -> CGPath {
            let frame = UIBezierPath(rect: hole.bounds.insetBy(dx: -8 * em, dy: -8 * em))
            frame.append(hole)
            return frame.cgPath
        }

        /// An inset shadow, cast inward by a frame the clipping view hides; `blur` is CSS's.
        private static func insetShadow(_ color: UIColor, opacity: Float, offset: CGSize, blur: CGFloat) -> CAShapeLayer {
            let shadow = CAShapeLayer()
            shadow.fillRule = .evenOdd
            shadow.fillColor = UIColor.black.cgColor
            shadow.shadowColor = color.cgColor
            shadow.shadowOpacity = opacity
            shadow.shadowOffset = offset
            shadow.shadowRadius = blur / 2
            return shadow
        }

        private func addInsetShadow(_ color: UIColor, opacity: Float, offset: CGSize, blur: CGFloat, spread: CGFloat = 0) {
            let shadow = Self.insetShadow(color, opacity: opacity, offset: offset, blur: blur)
            edge.layer.addSublayer(shadow)
            insetShadows.append((shadow, spread))
        }

        /// The round image under a glass ring, bright top-left and bottom-right, with a soft inner
        /// shade, lifted off the card by a soft shadow.
        private func makeImage(size: CGFloat, ring: CGFloat) -> UIView {
            let holder = UIView()
            holder.translatesAutoresizingMaskIntoConstraints = false
            let bounds = CGRect(x: 0, y: 0, width: size, height: size)
            let imageLift = Self.outerShadow(Self.imageDrops)
            Self.shape(imageLift, Self.imageDrops, bounds: bounds, cornerRadius: size / 2)
            holder.layer.addSublayer(imageLift)
            let slot = UIView()
            slot.backgroundColor = UIColor.white.withAlphaComponent(0.3)
            // The glass goes over the photo, in its own view: the loader adds the photo to `slot`.
            let glass = UIView()
            glass.isUserInteractionEnabled = false
            for view in [slot, glass] {
                view.translatesAutoresizingMaskIntoConstraints = false
                view.layer.cornerRadius = size / 2
                view.clipsToBounds = true
                holder.addSubview(view)
                Self.pinEdges(view, to: holder)
            }
            let circle = Self.frame(around: UIBezierPath(ovalIn: bounds))
            for inner in [
                Self.insetShadow(.white, opacity: 0.3, offset: CGSize(width: 0, height: -0.25 * em), blur: 0.5 * em),
                Self.insetShadow(.black, opacity: 0.16, offset: CGSize(width: 0, height: 0.3 * em), blur: 0.6 * em),
            ] {
                inner.path = circle
                glass.layer.addSublayer(inner)
            }
            let rim = CAGradientLayer()
            rim.frame = bounds
            rim.colors = [0.95, 0.4, 0.25, 0.8].map { UIColor.white.withAlphaComponent($0).cgColor }
            rim.locations = [0, 0.35, 0.6, 1]
            rim.startPoint = CGPoint(x: 0.21, y: 0.09)
            rim.endPoint = CGPoint(x: 0.79, y: 0.91)
            let ringShape = CAShapeLayer()
            ringShape.path = UIBezierPath(ovalIn: bounds.insetBy(dx: ring / 2, dy: ring / 2)).cgPath
            ringShape.fillColor = nil
            ringShape.strokeColor = UIColor.black.cgColor
            ringShape.lineWidth = ring
            rim.mask = ringShape
            glass.layer.addSublayer(rim)
            NSLayoutConstraint.activate([
                holder.widthAnchor.constraint(equalToConstant: size),
                holder.heightAnchor.constraint(equalToConstant: size),
            ])
            if let url = card.imageUrl {
                let loader = PoltioTriggerIconLoader(container: slot, size: size, contentMode: .scaleAspectFill)
                loader.load(url: url, centeredOn: slot) {}
                imageLoader = loader
            }
            return holder
        }

        /// The side card's vertical label behind a short line, read from the bottom when the strip is on
        /// the left, from the top when it's on the right.
        private func addSpine(font: UIFont, color: UIColor, onLeft: Bool) {
            let unit = font.pointSize
            let title = Self.label(card.title.localizedUppercase, font: font, color: color, kern: 0.12 * unit)
            title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let spine = UIStackView(arrangedSubviews: [Self.line(width: 1.3 * unit, color: color), title])
            spine.translatesAutoresizingMaskIntoConstraints = false
            spine.alignment = .center
            spine.spacing = 0.7 * unit
            spine.transform = CGAffineTransform(rotationAngle: onLeft ? -.pi / 2 : .pi / 2)
            // Auto Layout ignores the rotation, so a box with the rotated size places it.
            let box = UILayoutGuide()
            surface.addLayoutGuide(box)
            surface.addSubview(spine)
            NSLayoutConstraint.activate([
                box.widthAnchor.constraint(equalTo: spine.heightAnchor),
                box.heightAnchor.constraint(equalTo: spine.widthAnchor),
                box.topAnchor.constraint(equalTo: surface.topAnchor, constant: 1.2 * unit),
                onLeft ? box.leftAnchor.constraint(equalTo: surface.leftAnchor, constant: 0.6 * unit) : box.rightAnchor.constraint(equalTo: surface.rightAnchor, constant: -0.6 * unit),
                spine.centerXAnchor.constraint(equalTo: box.centerXAnchor),
                spine.centerYAnchor.constraint(equalTo: box.centerYAnchor),
                spine.widthAnchor.constraint(lessThanOrEqualToConstant: 9 * unit),
            ])
        }

        private static func label(_ text: String, font: UIFont, color: UIColor, kern: CGFloat = 0, lines: Int = 1, lineSpacing: CGFloat = 0) -> UILabel {
            let shadow = NSShadow()
            shadow.shadowOffset = CGSize(width: 0, height: 1)
            shadow.shadowBlurRadius = 2
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.18)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = lineSpacing
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .shadow: shadow, .paragraphStyle: paragraph]
            // A kern of 0 would turn the font's own kerning off.
            if kern != 0 {
                attributes[.kern] = kern
            }
            label.attributedText = NSAttributedString(string: text, attributes: attributes)
            label.numberOfLines = lines
            label.lineBreakMode = .byTruncatingTail
            return label
        }

        /// The short white line under a title.
        private static func line(width: CGFloat, color: UIColor) -> UIView {
            let line = UIView()
            line.translatesAutoresizingMaskIntoConstraints = false
            line.backgroundColor = color
            line.alpha = 0.85
            line.layer.cornerRadius = 1
            NSLayoutConstraint.activate([
                line.widthAnchor.constraint(equalToConstant: width),
                line.heightAnchor.constraint(equalToConstant: 2),
            ])
            return line
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

        static func darker(_ color: UIColor) -> UIColor {
            var (red, green, blue, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return color }
            return UIColor(red: red * 0.7, green: green * 0.7, blue: blue * 0.7, alpha: alpha)
        }

        static func pinEdges(_ view: UIView, to container: UIView) {
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                view.leftAnchor.constraint(equalTo: container.leftAnchor),
                view.rightAnchor.constraint(equalTo: container.rightAnchor),
            ])
        }
    }

    /// A glossy 3D button face in the button color: a lit top half under a shine, a shaded base and a
    /// soft drop. `unit` is web's em for the button.
    final class PoltioStackGlossView: UIView {
        private let gloss = CAGradientLayer()
        private let shine = CAGradientLayer()
        private let unit: CGFloat

        /// The face is as wide as `content` plus `padding` a side, unless its own constraints size it.
        init(color: UIColor, content: UIView, unit: CGFloat, padding: CGFloat = 0) {
            self.unit = unit
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
            isUserInteractionEnabled = false
            backgroundColor = color
            layer.borderWidth = 1
            layer.borderColor = UIColor.white.withAlphaComponent(0.14).cgColor
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.45
            layer.shadowRadius = 0.5 * unit
            layer.shadowOffset = CGSize(width: 0, height: 0.45 * unit)
            gloss.colors = [UIColor.white.withAlphaComponent(0.3), UIColor.white.withAlphaComponent(0), UIColor.black.withAlphaComponent(0.14)].map(\.cgColor)
            gloss.masksToBounds = true
            shine.colors = [UIColor.white.withAlphaComponent(0.55), UIColor.white.withAlphaComponent(0.04)].map(\.cgColor)
            shine.masksToBounds = true
            layer.addSublayer(gloss)
            layer.addSublayer(shine)
            content.translatesAutoresizingMaskIntoConstraints = false
            content.setContentHuggingPriority(.required, for: .horizontal)
            addSubview(content)
            let hug = widthAnchor.constraint(equalTo: content.widthAnchor, constant: 2 * padding)
            hug.priority = .defaultHigh
            NSLayoutConstraint.activate([
                content.centerXAnchor.constraint(equalTo: centerXAnchor),
                content.centerYAnchor.constraint(equalTo: centerYAnchor),
                content.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -2 * padding),
                hug,
            ])
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let radius = bounds.height / 2
            layer.cornerRadius = radius
            gloss.frame = bounds
            gloss.cornerRadius = radius
            shine.frame = CGRect(x: bounds.width * 0.12, y: 0.14 * unit, width: bounds.width * 0.76, height: bounds.height * 0.46)
            shine.cornerRadius = shine.frame.height / 2
            layer.shadowPath = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.3 * unit, dy: 0.3 * unit), cornerRadius: radius).cgPath
        }
    }
#endif
