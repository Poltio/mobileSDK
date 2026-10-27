#if canImport(UIKit)
    import UIKit

    /// Transparent overlay window that passes through touches except when interacting with the floating trigger.
    @available(iOSApplicationExtension, unavailable)
    final class PoltioPassthroughWindow: UIWindow {
        private var lastNotificationTime: TimeInterval = 0

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard let hitView = super.hitTest(point, with: event) else {
                return nil
            }
            // Pass touches through if the user tapped on the empty window or root controller container view
            if hitView === self || hitView === rootViewController?.view {
                let now = CACurrentMediaTime()
                if now - lastNotificationTime > 0.1 {
                    lastNotificationTime = now
                    NotificationCenter.default.post(name: PoltioFloatingPillTriggerView.didScrollNotification, object: nil)
                }
                return nil
            }
            return hitView
        }
    }

    /// Dedicated root view controller for the overlay window.
    @available(iOSApplicationExtension, unavailable)
    final class PoltioOverlayRootViewController: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isOpaque = false
        }

        override var shouldAutorotate: Bool {
            true
        }

        override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            // A rotation can change the host tab bar's height: measure it again once both windows
            // have laid out at the new size.
            coordinator.animate(alongsideTransition: nil) { _ in
                PoltioOverlayManager.shared.refreshTabBarClearance()
            }
        }
    }

    /// Manages attaching, presenting, and dismissing native Poltio floating triggers and interactive webviews.
    @available(iOSApplicationExtension, unavailable)
    final class PoltioOverlayManager {
        static let shared = PoltioOverlayManager()

        /// Maximum number of times `showTrigger` will retry while waiting for a `UIWindowScene` to
        /// become available, before giving up. Caps retries at 10 * 0.2s = 2s so a host app that never
        /// produces an active scene (e.g. unusual lifecycle, extension context) doesn't loop forever.
        private static let maxShowTriggerRetries = 10

        private var overlayWindow: PoltioPassthroughWindow?
        private var activeTriggerView: (UIView & PoltioTriggerPresentable)?
        /// How far the active trigger slides in from, and out to, beyond its docked edge.
        private var triggerSlideOffsetX: CGFloat = 80
        /// The active trigger's bottom constraint when it's bottom-docked, and its own inset above the
        /// safe area, kept so its clearance over the host tab bar can follow the bar after it's built.
        private var triggerBottomConstraint: NSLayoutConstraint?
        private var triggerBottomInset: CGFloat = 0
        private var currentPublicId: String?
        private var currentTriggerType: String?
        /// Widgets can share content and trigger type yet differ in copy, colors and position, so the
        /// trigger on screen is only the incoming one when its widget id matches too.
        private var currentWidgetId: Int?
        private var pendingShowWorkItem: DispatchWorkItem?
        private var showTriggerRetryCount = 0

        private init() {}

        /// Displays the floating trigger for the resolved widget on a dedicated passthrough overlay window.
        /// - Parameters:
        ///   - widget: The resolved Poltio widget configuration.
        ///   - puid: Optional developer-provided user identifier.
        func showTrigger(
            widget: PoltioWidgetResponse,
            puid: String? = nil
        ) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                pendingShowWorkItem?.cancel()
                pendingShowWorkItem = nil

                guard widget.overlayOptions.isBoxTrigger || widget.overlayOptions.isPillTrigger || widget.overlayOptions.isCardTrigger else {
                    PoltioLogger.warning("Trigger type '\(widget.overlayOptions.triggerType ?? "none")' is not currently handled (supported: 'box', 'pill', 'card').")
                    hideTrigger()
                    return
                }

                guard !widget.overlayOptions.hideButton else {
                    PoltioLogger.debug("Floating trigger suppressed for widget '\(widget.publicId)' (floating-hide-button).")
                    hideTrigger()
                    return
                }

                guard !PoltioTriggerDismissalStore.isDismissed(publicId: widget.publicId) else {
                    PoltioLogger.debug("Floating trigger suppressed for widget '\(widget.publicId)' (still within its close-remember window).")
                    hideTrigger()
                    return
                }

                let targetTriggerType = widget.overlayOptions.triggerType ?? ""

                if isCurrent(widget),
                   currentTriggerType == targetTriggerType,
                   let activeView = activeTriggerView,
                   activeView.superview != nil,
                   let activeScene = activeView.window?.windowScene,
                   activeScene === findActiveWindowScene()
                {
                    // Already active and visible for this exact widget and trigger type on the
                    // currently active window scene. Still a fresh impression from the caller's
                    // perspective (e.g. the same widget is configured for two screens), so report
                    // it even though nothing is rebuilt.
                    //
                    // The scene check matters on iPadOS multi-window setups: without it, switching
                    // focus to a different scene of the same app while this widget's trigger is
                    // still attached (but inactive) in the first scene would match on
                    // widget and trigger type alone and return here, leaving the trigger invisible in
                    // the scene actually on screen instead of reattaching to it.
                    PoltioSDK.shared.reportCtaView(widget: widget)
                    // The screen tracked may have hidden or shown the host tab bar (a push with
                    // `hidesBottomBarWhenPushed`), so the kept trigger measures it again.
                    refreshTabBarClearance()
                    return
                }

                // A retry (scheduled by this same method below) re-enters here for the same widget while
                // it's still waiting on a UIWindowScene. Only reset the retry counter for a genuinely new
                // widget — otherwise it gets zeroed on every retry and the cap below never trips.
                let isRetryForSameWidget = isCurrent(widget)

                // Clean up previous overlay and update state immediately
                teardownOverlaySynchronously()
                if !isRetryForSameWidget {
                    showTriggerRetryCount = 0
                }
                currentPublicId = widget.publicId
                currentTriggerType = targetTriggerType
                currentWidgetId = widget.widgetId

                guard let windowScene = findActiveWindowScene() else {
                    guard showTriggerRetryCount < Self.maxShowTriggerRetries else {
                        PoltioLogger.warning("UIWindowScene still not available after \(Self.maxShowTriggerRetries) retries; giving up on showing trigger for widget '\(widget.publicId)'.")
                        showTriggerRetryCount = 0
                        currentPublicId = nil
                        currentTriggerType = nil
                        currentWidgetId = nil
                        return
                    }
                    showTriggerRetryCount += 1
                    PoltioLogger.debug("UIWindowScene not ready yet, retrying showTrigger (\(showTriggerRetryCount)/\(Self.maxShowTriggerRetries)) after 0.2s...")
                    let workItem = DispatchWorkItem { [weak self] in
                        guard let self, isCurrent(widget) else { return }
                        showTrigger(widget: widget, puid: puid)
                    }
                    pendingShowWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
                    return
                }

                showTriggerRetryCount = 0

                // The trigger is now guaranteed to actually render below — report the impression
                // once here rather than at the top of the method, so retries while waiting for a
                // `UIWindowScene` (which re-enter this same method) don't double-report.
                PoltioSDK.shared.reportCtaView(widget: widget)

                let window: PoltioPassthroughWindow
                if #available(iOS 13.0, *) {
                    window = PoltioPassthroughWindow(windowScene: windowScene)
                    window.frame = windowScene.coordinateSpace.bounds
                } else {
                    window = PoltioPassthroughWindow(frame: UIScreen.main.bounds)
                }

                // `floatingZindex` (default 100) nudges the overlay window's level around its base position
                // instead of remapping it wholesale, so integrators can order it relative to other custom
                // overlay windows without risking it jumping above system alerts.
                let zIndexOffset = max(-0.5, min(0.5, CGFloat(widget.overlayOptions.floatingZindex - 100) * 0.01))
                window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue - 1 + zIndexOffset)
                window.backgroundColor = .clear
                window.isOpaque = false

                let rootVC = PoltioOverlayRootViewController()
                window.rootViewController = rootVC

                let onOpenWidget: () -> Void = { [weak self] in
                    self?.presentWidgetWebView(publicId: widget.publicId, widgetId: widget.widgetId, puid: puid, overlayOptions: widget.overlayOptions)
                }
                let onDismissForever: (Double) -> Void = { [weak self] hours in
                    PoltioTriggerDismissalStore.recordDismissal(publicId: widget.publicId, hours: hours)
                    self?.hideTrigger()
                }

                let vertical = widget.overlayOptions.verticalPosition
                let isLeftDocked = widget.overlayOptions.isLeftDocked
                let bottomObstruction = vertical == "bottom" ? hostTabBarOverlap() : 0
                let triggerView: UIView & PoltioTriggerPresentable
                let bottomConstraint: NSLayoutConstraint?
                let bottomInset: CGFloat

                if widget.overlayOptions.isPillTrigger {
                    let pillView = PoltioFloatingPillTriggerView(
                        widget: widget,
                        onOpenWidget: onOpenWidget,
                        onDismissForever: onDismissForever
                    )
                    pillView.translatesAutoresizingMaskIntoConstraints = false
                    rootVC.view.addSubview(pillView)
                    bottomInset = 70
                    bottomConstraint = Self.pinTrigger(
                        pillView, in: rootVC.view, vertical: vertical, isLeftDocked: isLeftDocked,
                        horizontalInset: 16, verticalInset: bottomInset, hugsRawEdgeHorizontally: false,
                        bottomObstruction: bottomObstruction
                    )
                    triggerView = pillView
                } else if widget.overlayOptions.isCardTrigger {
                    let cardView = PoltioFloatingCardTriggerView(
                        widget: widget,
                        onOpenWidget: onOpenWidget
                    )
                    cardView.translatesAutoresizingMaskIntoConstraints = false
                    rootVC.view.addSubview(cardView)
                    bottomInset = 70
                    bottomConstraint = Self.pinTrigger(
                        cardView, in: rootVC.view, vertical: vertical, isLeftDocked: isLeftDocked,
                        horizontalInset: 0, verticalInset: bottomInset, hugsRawEdgeHorizontally: true,
                        bottomObstruction: bottomObstruction
                    )
                    triggerView = cardView
                } else {
                    let boxView = PoltioFloatingBoxTriggerView(
                        widget: widget,
                        onOpenWidget: onOpenWidget,
                        onDismissForever: onDismissForever
                    )
                    boxView.translatesAutoresizingMaskIntoConstraints = false
                    rootVC.view.addSubview(boxView)
                    bottomInset = 24
                    bottomConstraint = Self.pinTrigger(
                        boxView, in: rootVC.view, vertical: vertical, isLeftDocked: isLeftDocked,
                        horizontalInset: 0, verticalInset: bottomInset, hugsRawEdgeHorizontally: true,
                        bottomObstruction: bottomObstruction
                    )
                    triggerView = boxView
                }

                activeTriggerView = triggerView
                triggerBottomConstraint = bottomConstraint
                triggerBottomInset = bottomInset
                triggerSlideOffsetX = isLeftDocked ? -80 : 80
                overlayWindow = window
                window.isHidden = false

                PoltioLogger.info("Attached floating trigger overlay for widget '\(widget.publicId)' (type: \(widget.overlayOptions.triggerType ?? "unknown")) in dedicated passthrough window.")

                triggerView.alpha = 0
                triggerView.transform = CGAffineTransform(translationX: triggerSlideOffsetX, y: 0)

                UIView.animate(
                    withDuration: 0.4,
                    delay: 0.05,
                    usingSpringWithDamping: 0.8,
                    initialSpringVelocity: 0.5,
                    options: [.curveEaseOut, .allowUserInteraction],
                    animations: {
                        triggerView.alpha = 1
                        triggerView.transform = .identity
                    },
                    completion: nil
                )
            }
        }

        /// Whether `widget` is the one the current trigger was built for: same content and same widget.
        private func isCurrent(_ widget: PoltioWidgetResponse) -> Bool {
            currentPublicId == widget.publicId && currentWidgetId == widget.widgetId
        }

        /// Hides and removes any currently displayed floating trigger view and its overlay window with animation.
        func hideTrigger() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                pendingShowWorkItem?.cancel()
                pendingShowWorkItem = nil
                currentPublicId = nil
                currentTriggerType = nil
                currentWidgetId = nil
                let windowToClose = overlayWindow
                let viewToClose = activeTriggerView
                let slideOffsetX = triggerSlideOffsetX

                overlayWindow = nil
                activeTriggerView = nil
                triggerBottomConstraint = nil

                guard let view = viewToClose, let window = windowToClose else { return }

                UIView.animate(withDuration: 0.25, animations: {
                    view.alpha = 0
                    view.transform = CGAffineTransform(translationX: slideOffsetX, y: 0)
                }, completion: { _ in
                    view.removeFromSuperview()
                    window.isHidden = true
                })
            }
        }

        /// Synchronously tears down any existing overlay window/view. Main thread only.
        func teardownOverlaySynchronously() {
            pendingShowWorkItem?.cancel()
            pendingShowWorkItem = nil
            currentPublicId = nil
            currentTriggerType = nil
            currentWidgetId = nil
            activeTriggerView?.removeFromSuperview()
            activeTriggerView = nil
            triggerBottomConstraint = nil
            overlayWindow?.isHidden = true
            overlayWindow = nil
        }

        /// Pins `view` within `container` according to the parsed `floatingPosition` (`vertical`, left or right),
        /// generalizing what used to be three hardcoded per-trigger constraint blocks. `hugsRawEdgeHorizontally`
        /// preserves each trigger's pre-existing horizontal-anchoring convention (card/box hug the raw view
        /// edge so their collapsed tabs bleed off-screen; pill insets from the safe area). `bottomObstruction`
        /// lifts a bottom-docked trigger over host chrome the overlay window's safe area can't see.
        ///
        /// Anchors are physical (`left`/`right`), not `leading`/`trailing`: `floating-position` names a
        /// physical side, and the triggers draw their rounded corners for it, so a right-to-left app
        /// language must not flip the trigger onto the other edge.
        ///
        /// Returns the bottom constraint of a bottom-docked trigger, for `updateBottomClearance`.
        @discardableResult
        static func pinTrigger(
            _ view: UIView,
            in container: UIView,
            vertical: String,
            isLeftDocked: Bool,
            horizontalInset: CGFloat,
            verticalInset: CGFloat,
            hugsRawEdgeHorizontally: Bool,
            bottomObstruction: CGFloat = 0
        ) -> NSLayoutConstraint? {
            var constraints: [NSLayoutConstraint] = []
            var bottomConstraint: NSLayoutConstraint?

            if isLeftDocked {
                let anchor = hugsRawEdgeHorizontally ? container.leftAnchor : container.safeAreaLayoutGuide.leftAnchor
                constraints.append(view.leftAnchor.constraint(equalTo: anchor, constant: horizontalInset))
            } else {
                let anchor = hugsRawEdgeHorizontally ? container.rightAnchor : container.safeAreaLayoutGuide.rightAnchor
                constraints.append(view.rightAnchor.constraint(equalTo: anchor, constant: -horizontalInset))
            }

            switch vertical {
            case "top":
                constraints.append(view.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: verticalInset))
            case "center":
                constraints.append(view.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -verticalInset))
            default: // "bottom"
                let bottom = view.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor)
                updateBottomClearance(bottom, inset: verticalInset, overlap: bottomObstruction)
                constraints.append(bottom)
                bottomConstraint = bottom
            }

            NSLayoutConstraint.activate(constraints)
            return bottomConstraint
        }

        /// Points a bottom-docked trigger's bottom `constraint` `inset` above the safe area plus the
        /// `overlap` of host tab bar. Returns whether it moved.
        @discardableResult
        static func updateBottomClearance(_ constraint: NSLayoutConstraint, inset: CGFloat, overlap: CGFloat) -> Bool {
            let constant = -(inset + overlap)
            guard constraint.constant != constant else { return false }
            constraint.constant = constant
            // A new constant alone doesn't always flag the layout as stale; the next pass must move it.
            (constraint.firstItem as? UIView)?.superview?.setNeedsLayout()
            return true
        }

        // MARK: - Host Tab Bar

        /// How far the host app's visible tab bar reaches above the bottom safe area. The trigger has
        /// its own window, whose safe area knows nothing of the host's bars, so a bottom-docked trigger
        /// would otherwise sit over the tab bar and take the taps meant for it.
        private func hostTabBarOverlap() -> CGFloat {
            guard let hostWindow = findHostKeyWindow(),
                  let tabBar = Self.visibleTabBar(under: hostWindow.rootViewController)
            else { return 0 }
            return Self.tabBarOverlap(
                tabBarTop: tabBar.convert(tabBar.bounds, to: hostWindow).minY,
                windowHeight: hostWindow.bounds.height,
                safeAreaBottom: hostWindow.safeAreaInsets.bottom
            )
        }

        /// Measures the host tab bar again and moves a bottom-docked trigger to keep clear of it: the
        /// bar can hide (`hidesBottomBarWhenPushed`), come back, or change height on rotation while the
        /// same trigger stays up. A host transition still running (a push hiding the bar) finishes first.
        func refreshTabBarClearance() {
            DispatchQueue.main.async { [weak self] in
                guard let self, triggerBottomConstraint != nil else { return }
                if let coordinator = Self.transitionInFlight(under: findHostKeyWindow()?.rootViewController) {
                    coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                        self?.applyTabBarClearance()
                    }
                } else {
                    applyTabBarClearance()
                }
            }
        }

        private func applyTabBarClearance() {
            guard let constraint = triggerBottomConstraint,
                  let trigger = activeTriggerView,
                  Self.updateBottomClearance(constraint, inset: triggerBottomInset, overlap: hostTabBarOverlap())
            else { return }
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                trigger.superview?.layoutIfNeeded()
            }
        }

        /// A view controller transition running anywhere under `root` (a push, a presentation), if any.
        private static func transitionInFlight(under root: UIViewController?) -> UIViewControllerTransitionCoordinator? {
            guard let root else { return nil }
            if let coordinator = root.transitionCoordinator {
                return coordinator
            }
            for child in root.children {
                if let coordinator = transitionInFlight(under: child) {
                    return coordinator
                }
            }
            return transitionInFlight(under: root.presentedViewController)
        }

        /// The tab bar on screen under `root`, if any: searched from the topmost presented controller
        /// (a modal over a tab bar controller hides its bar), through child controllers, which is where
        /// SwiftUI's `TabView` keeps its `UITabBarController`.
        static func visibleTabBar(under root: UIViewController?) -> UITabBar? {
            var top = root
            while let presented = top?.presentedViewController, !presented.isBeingDismissed {
                top = presented
            }
            return firstVisibleTabBar(in: top)
        }

        private static func firstVisibleTabBar(in viewController: UIViewController?) -> UITabBar? {
            guard let viewController else { return nil }
            if let tabBarController = viewController as? UITabBarController {
                let tabBar = tabBarController.tabBar
                return !tabBar.isHidden && tabBar.window != nil ? tabBar : nil
            }
            for child in viewController.children {
                if let tabBar = firstVisibleTabBar(in: child) {
                    return tabBar
                }
            }
            return nil
        }

        /// The part of a tab bar starting at `tabBarTop` that lies above the bottom safe area.
        static func tabBarOverlap(tabBarTop: CGFloat, windowHeight: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
            max(0, windowHeight - safeAreaBottom - tabBarTop)
        }

        /// Presents the interactive widget modal WebView on top of the active view controller.
        func presentWidgetWebView(publicId: String, widgetId: Int? = nil, puid: String?, overlayOptions: PoltioOverlayOptions? = nil) {
            DispatchQueue.main.async { [weak self] in
                guard let self, let topVC = findTopmostHostViewController() else {
                    PoltioLogger.error("Unable to find topmost view controller to present widget.")
                    return
                }

                // Hide the floating trigger window while the webview is presented
                overlayWindow?.isHidden = true

                let webVC = PoltioWebViewController(publicId: publicId, widgetId: widgetId, puid: puid, overlayOptions: overlayOptions)
                webVC.onWidgetEvent = { event, data in
                    PoltioSDK.onWidgetEvent?(event, data)
                }
                webVC.onDismiss = { [weak self] in
                    DispatchQueue.main.async {
                        guard let self, let window = self.overlayWindow, let trigger = self.activeTriggerView else {
                            return
                        }

                        // Reset to collapsed tab after user interacted with webview
                        trigger.resetToCollapsed(animated: false)
                        // The host may have rotated or changed screens while the sheet covered it.
                        self.refreshTabBarClearance()

                        window.isHidden = false
                        trigger.alpha = 0
                        trigger.transform = CGAffineTransform(translationX: self.triggerSlideOffsetX, y: 0)

                        UIView.animate(
                            withDuration: 0.35,
                            delay: 0.05,
                            usingSpringWithDamping: 0.8,
                            initialSpringVelocity: 0.5,
                            options: [.curveEaseOut, .allowUserInteraction],
                            animations: {
                                trigger.alpha = 1
                                trigger.transform = .identity
                            },
                            completion: nil
                        )
                    }
                }

                topVC.present(webVC, animated: true, completion: nil)
            }
        }

        // MARK: - Scene & View Controller Traversal

        private func findActiveWindowScene() -> UIWindowScene? {
            if #available(iOS 13.0, *) {
                let scenes = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }

                if let active = scenes.first(where: { $0.activationState == .foregroundActive }) {
                    return active
                }
                if let first = scenes.first {
                    return first
                }
                if let scene = UIApplication.shared.windows.first?.windowScene {
                    return scene
                }
            }
            return nil
        }

        private func findHostKeyWindow() -> UIWindow? {
            if #available(iOS 13.0, *) {
                let scenes = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }

                for scene in scenes {
                    if let window = scene.windows.first(where: { $0 !== self.overlayWindow && $0.isKeyWindow && $0.rootViewController != nil }) {
                        return window
                    }
                    if let window = scene.windows.first(where: { $0 !== self.overlayWindow && $0.rootViewController != nil }) {
                        return window
                    }
                    if let window = scene.windows.first(where: { $0 !== self.overlayWindow }) {
                        return window
                    }
                }
            }

            return UIApplication.shared.windows.first(where: { $0 !== self.overlayWindow && $0.isKeyWindow && $0.rootViewController != nil })
                ?? UIApplication.shared.windows.first(where: { $0 !== self.overlayWindow && $0.rootViewController != nil })
                ?? UIApplication.shared.windows.first(where: { $0 !== self.overlayWindow })
                ?? UIApplication.shared.keyWindow
        }

        private func findTopmostHostViewController(from root: UIViewController? = nil) -> UIViewController? {
            let base = root ?? findHostKeyWindow()?.rootViewController

            if let nav = base as? UINavigationController {
                return findTopmostHostViewController(from: nav.visibleViewController)
            }
            if let tab = base as? UITabBarController {
                return findTopmostHostViewController(from: tab.selectedViewController)
            }
            if let presented = base?.presentedViewController {
                return findTopmostHostViewController(from: presented)
            }

            return base
        }
    }
#endif
