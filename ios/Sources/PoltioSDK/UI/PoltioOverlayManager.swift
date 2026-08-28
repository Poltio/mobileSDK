#if canImport(UIKit)
    import UIKit

    /// Transparent overlay window that passes through touches except when interacting with the floating trigger.
    @available(iOSApplicationExtension, unavailable)
    public final class PoltioPassthroughWindow: UIWindow {
        private var lastNotificationTime: TimeInterval = 0

        override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
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
    }

    /// Manages attaching, presenting, and dismissing native Poltio floating triggers and interactive webviews.
    @available(iOSApplicationExtension, unavailable)
    public final class PoltioOverlayManager {
        public static let shared = PoltioOverlayManager()

        /// Maximum number of times `showTrigger` will retry while waiting for a `UIWindowScene` to
        /// become available, before giving up. Caps retries at 10 * 0.2s = 2s so a host app that never
        /// produces an active scene (e.g. unusual lifecycle, extension context) doesn't loop forever.
        private static let maxShowTriggerRetries = 10

        private var overlayWindow: PoltioPassthroughWindow?
        private var activeTriggerView: (UIView & PoltioTriggerPresentable)?
        private var currentPublicId: String?
        private var currentTriggerType: String?
        private var pendingShowWorkItem: DispatchWorkItem?
        private var showTriggerRetryCount = 0

        private init() {}

        /// Displays the floating trigger for the resolved widget on a dedicated passthrough overlay window.
        /// - Parameters:
        ///   - widget: The resolved Poltio widget configuration.
        ///   - puid: Optional developer-provided user identifier.
        public func showTrigger(
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

                let targetTriggerType = widget.overlayOptions.triggerType ?? ""

                if currentPublicId == widget.publicId,
                   currentTriggerType == targetTriggerType,
                   activeTriggerView != nil,
                   activeTriggerView?.superview != nil
                {
                    // Already active and visible for this exact widget and trigger type
                    return
                }

                // Clean up previous overlay and update state immediately
                teardownOverlaySynchronously()
                showTriggerRetryCount = 0
                currentPublicId = widget.publicId
                currentTriggerType = targetTriggerType

                guard let windowScene = findActiveWindowScene() else {
                    guard showTriggerRetryCount < Self.maxShowTriggerRetries else {
                        PoltioLogger.warning("UIWindowScene still not available after \(Self.maxShowTriggerRetries) retries; giving up on showing trigger for widget '\(widget.publicId)'.")
                        showTriggerRetryCount = 0
                        currentPublicId = nil
                        currentTriggerType = nil
                        return
                    }
                    showTriggerRetryCount += 1
                    PoltioLogger.debug("UIWindowScene not ready yet, retrying showTrigger (\(showTriggerRetryCount)/\(Self.maxShowTriggerRetries)) after 0.2s...")
                    let workItem = DispatchWorkItem { [weak self] in
                        guard let self, currentPublicId == widget.publicId else { return }
                        showTrigger(widget: widget, puid: puid)
                    }
                    pendingShowWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
                    return
                }

                showTriggerRetryCount = 0

                let window: PoltioPassthroughWindow
                if #available(iOS 13.0, *) {
                    window = PoltioPassthroughWindow(windowScene: windowScene)
                    window.frame = windowScene.coordinateSpace.bounds
                } else {
                    window = PoltioPassthroughWindow(frame: UIScreen.main.bounds)
                }

                window.windowLevel = UIWindow.Level.alert - 1
                window.backgroundColor = .clear
                window.isOpaque = false

                let rootVC = PoltioOverlayRootViewController()
                window.rootViewController = rootVC

                let onOpenWidget: () -> Void = { [weak self] in
                    self?.presentWidgetWebView(publicId: widget.publicId, puid: puid)
                }

                let triggerView: UIView & PoltioTriggerPresentable

                if widget.overlayOptions.isPillTrigger {
                    let pillView = PoltioFloatingPillTriggerView(
                        widget: widget,
                        onOpenWidget: onOpenWidget
                    )
                    pillView.translatesAutoresizingMaskIntoConstraints = false
                    rootVC.view.addSubview(pillView)

                    NSLayoutConstraint.activate([
                        pillView.trailingAnchor.constraint(equalTo: rootVC.view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                        pillView.bottomAnchor.constraint(equalTo: rootVC.view.safeAreaLayoutGuide.bottomAnchor, constant: -70),
                    ])
                    triggerView = pillView
                } else if widget.overlayOptions.isCardTrigger {
                    let cardView = PoltioFloatingCardTriggerView(
                        widget: widget,
                        onOpenWidget: onOpenWidget
                    )
                    cardView.translatesAutoresizingMaskIntoConstraints = false
                    rootVC.view.addSubview(cardView)

                    NSLayoutConstraint.activate([
                        cardView.trailingAnchor.constraint(equalTo: rootVC.view.trailingAnchor),
                        cardView.bottomAnchor.constraint(equalTo: rootVC.view.safeAreaLayoutGuide.bottomAnchor, constant: -70),
                    ])
                    triggerView = cardView
                } else {
                    let boxView = PoltioFloatingBoxTriggerView(
                        widget: widget,
                        onOpenWidget: onOpenWidget
                    )
                    boxView.translatesAutoresizingMaskIntoConstraints = false
                    rootVC.view.addSubview(boxView)

                    NSLayoutConstraint.activate([
                        boxView.trailingAnchor.constraint(equalTo: rootVC.view.trailingAnchor),
                        boxView.centerYAnchor.constraint(equalTo: rootVC.view.centerYAnchor, constant: -20),
                    ])
                    triggerView = boxView
                }

                activeTriggerView = triggerView
                overlayWindow = window
                window.isHidden = false

                PoltioLogger.info("Attached floating trigger overlay for widget '\(widget.publicId)' (type: \(widget.overlayOptions.triggerType ?? "unknown")) in dedicated passthrough window.")

                triggerView.alpha = 0
                triggerView.transform = CGAffineTransform(translationX: 80, y: 0)

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

        /// Hides and removes any currently displayed floating trigger view and its overlay window with animation.
        public func hideTrigger() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                pendingShowWorkItem?.cancel()
                pendingShowWorkItem = nil
                currentPublicId = nil
                currentTriggerType = nil
                let windowToClose = overlayWindow
                let viewToClose = activeTriggerView

                overlayWindow = nil
                activeTriggerView = nil

                guard let view = viewToClose, let window = windowToClose else { return }

                UIView.animate(withDuration: 0.25, animations: {
                    view.alpha = 0
                    view.transform = CGAffineTransform(translationX: 80, y: 0)
                }, completion: { _ in
                    view.removeFromSuperview()
                    window.isHidden = true
                })
            }
        }

        /// Synchronously tears down any existing overlay window/view.
        private func teardownOverlaySynchronously() {
            pendingShowWorkItem?.cancel()
            pendingShowWorkItem = nil
            currentPublicId = nil
            currentTriggerType = nil
            activeTriggerView?.removeFromSuperview()
            activeTriggerView = nil
            overlayWindow?.isHidden = true
            overlayWindow = nil
        }

        /// Presents the interactive widget modal WebView on top of the active view controller.
        public func presentWidgetWebView(publicId: String, puid: String?) {
            DispatchQueue.main.async { [weak self] in
                guard let self, let topVC = findTopmostHostViewController() else {
                    PoltioLogger.error("Unable to find topmost view controller to present widget.")
                    return
                }

                // Hide the floating trigger window while the webview is presented
                overlayWindow?.isHidden = true

                let webVC = PoltioWebViewController(publicId: publicId, puid: puid)
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

                        window.isHidden = false
                        trigger.alpha = 0
                        trigger.transform = CGAffineTransform(translationX: 80, y: 0)

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
