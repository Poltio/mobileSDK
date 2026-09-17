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
    enum PoltioScrollObserver {
        static let didScrollPastThresholdNotification = Notification.Name("PoltioSDK.scrollObserverDidScrollPastThreshold")

        /// Matches the web SDK's own hardcoded `floating-box-open-on-scroll` threshold (`box.ts`),
        /// not the separate/configurable `floatingScrollThreshold` field used elsewhere.
        fileprivate static let threshold: CGFloat = 100

        private static let lock = NSLock()
        private static var isInstalled = false
        private static var pendingThresholds: [(threshold: CGFloat, callback: () -> Void)] = []

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
        /// `threshold`, then automatically un-registers itself. Used by triggers with their own
        /// configurable threshold (the card trigger's `floatingScrollThreshold`, default 300pt,
        /// matching web), as an alternative to the fixed-`100`pt `didScrollPastThresholdNotification`
        /// used by the box/pill triggers.
        static func onScrollPast(_ threshold: CGFloat, callback: @escaping () -> Void) {
            lock.lock()
            pendingThresholds.append((threshold, callback))
            lock.unlock()
            installIfNeeded()
        }

        fileprivate static func handleScrolled(_ distance: CGFloat) {
            lock.lock()
            let toFire = pendingThresholds.filter { distance > $0.threshold }
            pendingThresholds.removeAll { distance > $0.threshold }
            lock.unlock()
            toFire.forEach { $0.callback() }
        }
    }

    fileprivate extension UIScrollView {
        @objc func poltio_setContentOffset(_ contentOffset: CGPoint) {
            // Calls through to the original implementation — this method IS the original after the
            // swizzle exchange above, despite the name.
            poltio_setContentOffset(contentOffset)
            let scrolled = contentOffset.y + adjustedContentInset.top
            if scrolled > PoltioScrollObserver.threshold {
                NotificationCenter.default.post(name: PoltioScrollObserver.didScrollPastThresholdNotification, object: nil)
            }
            PoltioScrollObserver.handleScrolled(scrolled)
        }
    }
#endif
