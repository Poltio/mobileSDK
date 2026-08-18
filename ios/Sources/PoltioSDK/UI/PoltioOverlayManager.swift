#if canImport(UIKit)
    import UIKit

    /// Transparent overlay window that passes through touches except when interacting with the floating trigger.
    @available(iOSApplicationExtension, unavailable)
    public final class PoltioPassthroughWindow: UIWindow {
        override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard let hitView = super.hitTest(point, with: event) else {
                return nil
            }
            // Pass touches through if the user tapped on the empty window or root controller container view
            if hitView === self || hitView === rootViewController?.view {
                NotificationCenter.default.post(name: PoltioFloatingPillTriggerView.didScrollNotification, object: nil)
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
            return true
        }
    }

    /// Manages attaching, presenting, and dismissing native Poltio floating triggers and interactive webviews.
    @available(iOSApplicationExtension, unavailable)
    public final class PoltioOverlayManager {
        public static let shared = PoltioOverlayManager()

        private var overlayWindow: PoltioPassthroughWindow?
        private var activeTriggerView: (UIView & PoltioTriggerPresentable)?
        private var currentPublicId: String?
        private var currentTriggerType: String?

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
                guard let self = self else { return }

                guard widget.overlayOptions.isBoxTrigger || widget.overlayOptions.isPillTrigger else {
                    print("[PoltioSDK] Trigger type '\(widget.overlayOptions.triggerType ?? "none")' is not currently handled (supported: 'box', 'pill').")
                    self.hideTrigger()
                    return
                }

                guard let hostWindow = self.findHostKeyWindow() else {
                    print("[PoltioSDK] Host window not ready yet, retrying showTrigger after 0.2s...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.showTrigger(widget: widget, puid: puid)
                    }
                    return
                }

                let container: UIView = hostWindow
                let targetTriggerType = widget.overlayOptions.triggerType ?? ""

                if self.currentPublicId == widget.publicId,
                   self.currentTriggerType == targetTriggerType,
                   self.activeTriggerView != nil,
                   self.activeTriggerView?.superview != nil
                {
                    // Already active and visible for this exact widget and trigger type
                    return
                }

                // Clean up previous overlay
                self.teardownOverlaySynchronously()
                self.currentPublicId = widget.publicId
                self.currentTriggerType = targetTriggerType

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
                    container.addSubview(pillView)
                    container.bringSubviewToFront(pillView)
                    pillView.layer.zPosition = 9999

                    NSLayoutConstraint.activate([
                        pillView.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                        pillView.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -70),
                    ])
                    triggerView = pillView
                } else {
                    let boxView = PoltioFloatingBoxTriggerView(
                        widget: widget,
                        onOpenWidget: onOpenWidget
                    )
                    boxView.translatesAutoresizingMaskIntoConstraints = false
                    container.addSubview(boxView)
                    container.bringSubviewToFront(boxView)
                    boxView.layer.zPosition = 9999

                    NSLayoutConstraint.activate([
                        boxView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                        boxView.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -20),
                    ])
                    triggerView = boxView
                }

                self.activeTriggerView = triggerView

                print("[PoltioSDK] Attached floating trigger overlay for widget '\(widget.publicId)' (type: \(widget.overlayOptions.triggerType ?? "unknown")) in host container.")

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

        /// Hides and removes any currently displayed floating trigger view with animation.
        public func hideTrigger() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.currentPublicId = nil
                self.currentTriggerType = nil
                let viewToClose = self.activeTriggerView
                self.activeTriggerView = nil

                guard let view = viewToClose else { return }

                UIView.animate(withDuration: 0.25, animations: {
                    view.alpha = 0
                    view.transform = CGAffineTransform(translationX: 80, y: 0)
                }, completion: { _ in
                    view.removeFromSuperview()
                })
            }
        }

        /// Synchronously tears down any existing overlay view.
        private func teardownOverlaySynchronously() {
            currentPublicId = nil
            currentTriggerType = nil
            activeTriggerView?.removeFromSuperview()
            activeTriggerView = nil
        }

        /// Presents the interactive widget modal WebView on top of the active view controller.
        public func presentWidgetWebView(publicId: String, puid: String?) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let topVC = self.findTopmostHostViewController() else {
                    print("[PoltioSDK] Error: Unable to find topmost view controller to present widget.")
                    return
                }

                // Hide the floating trigger while the webview is presented
                self.activeTriggerView?.isHidden = true

                let webVC = PoltioWebViewController(publicId: publicId, puid: puid)
                webVC.onDismiss = { [weak self] in
                    DispatchQueue.main.async {
                        guard let self = self, let trigger = self.activeTriggerView else {
                            return
                        }

                        // Reset to collapsed tab after user interacted with webview
                        trigger.resetToCollapsed(animated: false)

                        trigger.isHidden = false
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
                    if let window = scene.windows.first(where: { $0.isKeyWindow && $0.rootViewController != nil }) {
                        return window
                    }
                    if let window = scene.windows.first(where: { $0.rootViewController != nil }) {
                        return window
                    }
                    if let window = scene.windows.first {
                        return window
                    }
                }
            }

            return UIApplication.shared.windows.first(where: { $0.isKeyWindow && $0.rootViewController != nil })
                ?? UIApplication.shared.windows.first(where: { $0.rootViewController != nil })
                ?? UIApplication.shared.windows.first
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
