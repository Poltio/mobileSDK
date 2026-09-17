#if canImport(UIKit)
    import UIKit

    /// Passively observes scroll activity anywhere in the host app by swizzling `UIScrollView`'s
    /// `contentOffset` setter, broadcasting a notification whenever any scroll view moves past a
    /// small threshold from its resting position. Used to implement `floating-box-open-on-scroll`,
    /// mirroring the web SDK's `document.scroll` listener — mobile has no single "page scroll"
    /// concept, so any host scroll view moving (UIKit or SwiftUI, both ultimately backed by
    /// `UIScrollView`) is treated as a reasonable proxy for it.
    ///
    /// Purely observational: the swizzled implementation always calls through to the original, so
    /// host scrolling behavior is completely unaffected. This is a standard, widely-used technique
    /// (the same one many analytics SDKs use for scroll-depth tracking) rather than anything that
    /// touches gesture recognizers or view controllers.
    ///
    /// Both notifications below post the scrolling `UIScrollView` itself as their `object` (not
    /// `nil`) — the swizzle is process-wide, not scoped to any one window/scene, so a trigger whose
    /// own overlay window belongs to a scene that's since gone to the background (e.g. iPad
    /// multi-window/Stage Manager, or a scene the host app simply isn't showing anymore) would
    /// otherwise react to scrolling happening in a completely different, now-active scene.
    /// Observers are expected to compare `(notification.object as? UIScrollView)?.window?.windowScene`
    /// against their own trigger's `window?.windowScene` before acting — see each trigger view's
    /// scroll handlers for the pattern. (The trigger itself lives in its own dedicated overlay
    /// `UIWindow`, never the same `UIWindow` as host content, so comparing `.window` directly would
    /// never match; `.windowScene` is the right granularity, analogous to comparing Activities on
    /// Android.)
    enum PoltioScrollObserver {
        static let didScrollPastThresholdNotification = Notification.Name("PoltioSDK.scrollObserverDidScrollPastThreshold")

        /// Posted whenever the host page moves by more than `movementEpsilon` in a single update —
        /// a genuine "the user is actively scrolling right now" signal, independent of any absolute
        /// position threshold. Used to auto-collapse an expanded trigger while the host scrolls.
        static let didDetectScrollMovementNotification = Notification.Name("PoltioSDK.scrollObserverDidDetectMovement")

        /// Matches the web SDK's own hardcoded `floating-box-open-on-scroll` threshold (`box.ts`),
        /// not the separate/configurable `floatingScrollThreshold` field used elsewhere.
        fileprivate static let threshold: CGFloat = 100

        /// Minimum per-update movement (in points) treated as real scroll activity rather than
        /// floating-point/rounding jitter.
        fileprivate static let movementEpsilon: CGFloat = 4

        /// Opaque handle returned by `onScrollPast`, used solely to cancel that specific
        /// registration later via `cancelScrollPast` — e.g. when its view is torn down before the
        /// threshold was ever crossed.
        struct ScrollPastToken: Hashable {
            fileprivate let id = UUID()
        }

        /// Tuple elements can't be `weak` directly, so this small box holds the weak reference to
        /// the observing view instead — used purely to compare `windowScene` when deciding whether
        /// a scroll event is relevant to this particular pending registration.
        private final class WeakViewBox {
            weak var view: UIView?
            init(_ view: UIView) {
                self.view = view
            }
        }

        private static let lock = NSLock()
        private static var isInstalled = false
        private static var pendingThresholds: [(token: ScrollPastToken, threshold: CGFloat, view: WeakViewBox, callback: () -> Void)] = []

        /// Installs the swizzle exactly once per process. Safe to call repeatedly/concurrently.
        static func installIfNeeded() {
            lock.lock()
            defer { lock.unlock() }
            guard !isInstalled else { return }
            isInstalled = true

            guard
                let originalMethod = class_getInstanceMethod(UIScrollView.self, #selector(setter: UIScrollView.contentOffset)),
                let swizzledMethod = class_getInstanceMethod(UIScrollView.self, #selector(UIScrollView.poltio_setContentOffset(_:)))
            else {
                PoltioLogger.warning("PoltioScrollObserver: could not locate UIScrollView.contentOffset setter; floating-box-open-on-scroll will not trigger.")
                return
            }
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }

        /// Registers a one-shot callback that fires the first time total scroll distance exceeds
        /// `threshold` **in the same window scene as `view`**, then automatically un-registers
        /// itself. Used by triggers with their own configurable threshold (the card trigger's
        /// `floatingScrollThreshold`, default 300pt, matching web), as an alternative to the
        /// fixed-`100`pt `didScrollPastThresholdNotification` used by the box/pill triggers.
        /// `view` is held weakly purely to compare `windowScene` against the scrolling scroll
        /// view's — see the type-level doc comment above for why that comparison (not `view.window`
        /// itself, since the trigger lives in its own dedicated overlay window) is what's needed.
        /// Returns a token that `cancelScrollPast` can later use to remove this registration if the
        /// threshold is never crossed (e.g. the view is torn down first) — otherwise the closure
        /// would sit in `pendingThresholds` for the app's lifetime.
        @discardableResult
        static func onScrollPast(for view: UIView, threshold: CGFloat, callback: @escaping () -> Void) -> ScrollPastToken {
            let token = ScrollPastToken()
            lock.lock()
            pendingThresholds.append((token, threshold, WeakViewBox(view), callback))
            lock.unlock()
            installIfNeeded()
            return token
        }

        /// Cancels a still-pending `onScrollPast` registration. Safe to call even if it already
        /// fired (and was thus already removed) or was never registered.
        static func cancelScrollPast(_ token: ScrollPastToken) {
            lock.lock()
            pendingThresholds.removeAll { $0.token == token }
            lock.unlock()
        }

        fileprivate static func handleScrolled(_ distance: CGFloat, scrollView: UIScrollView) {
            // Called on every contentOffset update while scrolling — the common case (no card
            // trigger currently observing a custom threshold) has nothing to do here, so skip the
            // lock and list work entirely rather than paying for it on every scroll event. A stale
            // read outside the lock is fine: worst case is one extra check on the next update.
            guard !pendingThresholds.isEmpty else { return }
            // A `nil` scene here (scrollView not yet attached to any window) must never match a
            // pending entry whose own view also happens to have a `nil` scene for the same reason
            // — comparing two Optionals directly makes `nil == nil` true, which would be a false
            // "same scene" match between two views that aren't really in any scene together.
            guard let scrolledScene = scrollView.window?.windowScene else { return }
            lock.lock()
            // Only entries in the same window scene as the scrolling view are even eligible to
            // fire — a registration whose view has already been deallocated (nil weak ref) can
            // never match and is pruned here too, same as if it had explicitly cancelled.
            let eligible = pendingThresholds.filter { $0.view.view != nil && $0.view.view?.window?.windowScene == scrolledScene }
            let toFire = eligible.filter { distance > $0.threshold }
            pendingThresholds.removeAll { entry in entry.view.view == nil || toFire.contains { $0.token == entry.token } }
            lock.unlock()
            toFire.forEach { $0.callback() }
        }
    }

    /// Association key for `UIScrollView.poltio_lastScrolled` below. The address of this variable
    /// (not its value) is what `objc_get/setAssociatedObject` key on.
    private var poltio_lastScrolledKey: UInt8 = 0

    fileprivate extension UIScrollView {
        /// Per-instance last-seen scroll position, used to detect real movement in
        /// `poltio_setContentOffset`. Previously a single value shared across every `UIScrollView`
        /// in the app, which made two scroll views scrolling independently look like one erratic
        /// one — associating it with `self` instead scopes it correctly per scroll view.
        ///
        /// Nullable (rather than defaulting to 0) so a scroll view first observed while already
        /// scrolled — e.g. restored to a mid-scroll position — doesn't compute a huge bogus delta
        /// against an assumed starting position of zero on its very first update.
        var poltio_lastScrolled: CGFloat? {
            get { objc_getAssociatedObject(self, &poltio_lastScrolledKey) as? CGFloat }
            set { objc_setAssociatedObject(self, &poltio_lastScrolledKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
        }

        /// `dynamic` is required here, not just `@objc`: without it, the self-call to
        /// `poltio_setContentOffset` a few lines below can be statically resolved/devirtualized by
        /// the Swift optimizer (this doesn't show up in unoptimized debug builds, only release/WMO
        /// builds), which would call straight back into this same implementation after the swizzle
        /// swap instead of routing through the Objective-C runtime — infinite recursion and a stack
        /// overflow. `dynamic` forces genuine objc_msgSend dispatch for this call.
        @objc dynamic func poltio_setContentOffset(_ contentOffset: CGPoint) {
            // Calls through to the original implementation — this method IS the original after the
            // swizzle exchange above, despite the name.
            poltio_setContentOffset(contentOffset)

            // Skip scroll views that can't scroll vertically at all (a horizontal-only carousel,
            // or a `UITextView` whose content fits without scrolling) — otherwise their own
            // incidental contentOffset changes would be misread as the host page scrolling.
            guard bounds.height > 0, contentSize.height > bounds.height else { return }

            let scrolled = contentOffset.y + adjustedContentInset.top
            if scrolled > PoltioScrollObserver.threshold {
                NotificationCenter.default.post(name: PoltioScrollObserver.didScrollPastThresholdNotification, object: self)
            }
            if let lastScrolled = poltio_lastScrolled, abs(scrolled - lastScrolled) > PoltioScrollObserver.movementEpsilon {
                NotificationCenter.default.post(name: PoltioScrollObserver.didDetectScrollMovementNotification, object: self)
            }
            poltio_lastScrolled = scrolled
            PoltioScrollObserver.handleScrolled(scrolled, scrollView: self)
        }
    }
#endif
