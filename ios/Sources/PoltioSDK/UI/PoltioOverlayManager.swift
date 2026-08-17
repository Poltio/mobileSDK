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
    private var activeTriggerView: PoltioFloatingBoxTriggerView?
    private var currentPublicId: String?

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

            guard widget.overlayOptions.isBoxTrigger else {
                print("[PoltioSDK] Trigger type '\(widget.overlayOptions.triggerType ?? "none")' is not currently handled (supported: 'box').")
                self.hideTrigger()
                return
            }

            guard let windowScene = self.findActiveWindowScene() else {
                print("[PoltioSDK] Error: Unable to find active UIWindowScene to attach floating trigger.")
                return
            }

            if self.currentPublicId == widget.publicId, self.activeTriggerView != nil, self.overlayWindow?.isHidden == false {
                // Already active and visible for this widget
                return
            }

            // Synchronously clean up previous overlay without scheduling conflicting async blocks
            self.teardownOverlaySynchronously()

            self.currentPublicId = widget.publicId

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

            let triggerView = PoltioFloatingBoxTriggerView(
                widget: widget,
                onOpenWidget: { [weak self] in
                    self?.presentWidgetWebView(publicId: widget.publicId, puid: puid)
                }
            )

            rootVC.view.addSubview(triggerView)
            self.activeTriggerView = triggerView
            self.overlayWindow = window

            NSLayoutConstraint.activate([
                triggerView.trailingAnchor.constraint(equalTo: rootVC.view.safeAreaLayoutGuide.trailingAnchor),
                triggerView.centerYAnchor.constraint(equalTo: rootVC.view.centerYAnchor, constant: -20),
            ])

            window.isHidden = false

            print("[PoltioSDK] Attached floating trigger overlay for widget '\(widget.publicId)' in dedicated overlay window.")

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
            guard let self = self else { return }
            self.currentPublicId = nil
            let windowToClose = self.overlayWindow
            let viewToClose = self.activeTriggerView

            self.overlayWindow = nil
            self.activeTriggerView = nil

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
        currentPublicId = nil
        activeTriggerView?.removeFromSuperview()
        activeTriggerView = nil
        overlayWindow?.isHidden = true
        overlayWindow = nil
    }

    /// Presents the interactive widget modal WebView on top of the active view controller.
    public func presentWidgetWebView(publicId: String, puid: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let topVC = self.findTopmostHostViewController() else {
                print("[PoltioSDK] Error: Unable to find topmost view controller to present widget.")
                return
            }

            // Hide the floating trigger while the webview is presented
            self.overlayWindow?.isHidden = true

            let webVC = PoltioWebViewController(publicId: publicId, puid: puid)
            webVC.onDismiss = { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self, let window = self.overlayWindow, let trigger = self.activeTriggerView else {
                        return
                    }

                    // Reset to collapsed tab after user interacted with webview
                    trigger.setState(.collapsed, animated: false)

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

            return scenes.first(where: { $0.activationState == .foregroundActive })
                ?? scenes.first
        }
        return nil
    }

    private func findHostKeyWindow() -> UIWindow? {
        if #available(iOS 13.0, *) {
            if let scene = findActiveWindowScene() {
                if let window = scene.windows.first(where: { $0 !== self.overlayWindow && $0.isKeyWindow }) {
                    return window
                }
                if let window = scene.windows.first(where: { $0 !== self.overlayWindow }) {
                    return window
                }
            }
        }

        return UIApplication.shared.windows.first(where: { $0 !== self.overlayWindow && $0.isKeyWindow })
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
