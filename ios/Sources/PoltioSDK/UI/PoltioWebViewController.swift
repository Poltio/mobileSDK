#if canImport(UIKit)
    import UIKit
    import WebKit

    /// Proxy `WKScriptMessageHandler` that holds only a weak reference to its target.
    /// `WKUserContentController` retains its message handlers strongly, so registering a view controller
    /// directly would create a retain cycle (controller -> webView -> userContentController -> controller).
    private final class PoltioWeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
        private weak var target: WKScriptMessageHandler?

        init(target: WKScriptMessageHandler) {
            self.target = target
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.userContentController(userContentController, didReceive: message)
        }
    }

    /// In-app browser modal presenting the interactive Poltio widget WebView.
    @available(iOSApplicationExtension, unavailable)
    final class PoltioWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UIAdaptivePresentationControllerDelegate {
        private let publicId: String
        private let widgetId: Int?
        private let puid: String?
        private let overlayOptions: PoltioOverlayOptions?
        private var webView: WKWebView!
        private var activityIndicator: UIActivityIndicatorView!

        /// Name of the JS bridge message handler. The widget page communicates back to native code via
        /// `window.webkit.messageHandlers.poltioNative.postMessage({ event: "close" | "complete" | "leadSubmit", data: {...} })`.
        private static let bridgeHandlerName = "poltioNative"

        /// Callback invoked when the modal is dismissed (via close button or swipe down).
        var onDismiss: (() -> Void)?
        /// Callback invoked when the widget page sends a bridge event (e.g. "close", "complete", "leadSubmit").
        var onWidgetEvent: ((_ event: String, _ data: [String: Any]?) -> Void)?
        private var isDismissHandled = false

        init(publicId: String, widgetId: Int? = nil, puid: String? = nil, overlayOptions: PoltioOverlayOptions? = nil, onDismiss: (() -> Void)? = nil) {
            self.publicId = publicId
            self.widgetId = widgetId
            self.puid = puid
            self.overlayOptions = overlayOptions
            self.onDismiss = onDismiss
            super.init(nibName: nil, bundle: nil)
            modalPresentationStyle = .pageSheet
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            presentationController?.delegate = self
            setupUI()
            loadWidgetURL()
        }

        deinit {
            // WKWebView APIs are main-thread-only; deinit can run on any thread, so hop over defensively.
            // Explicitly typed as optional (rather than relying on the IUO directly) and guarded so
            // there's nothing to dispatch when the controller is deallocated before its view ever loaded.
            let webViewToClean: WKWebView? = webView
            guard let webViewToClean else { return }
            let handlerName = Self.bridgeHandlerName
            DispatchQueue.main.async {
                webViewToClean.stopLoading()
                webViewToClean.configuration.userContentController.removeScriptMessageHandler(forName: handlerName)
                webViewToClean.navigationDelegate = nil
                webViewToClean.uiDelegate = nil
            }
        }

        private func setupUI() {
            let panelBackgroundColor = overlayOptions?.resolvedWidgetBgColor ?? .systemBackground
            view.backgroundColor = panelBackgroundColor

            // Header Navigation / Close Bar
            let headerView = UIView()
            headerView.translatesAutoresizingMaskIntoConstraints = false
            headerView.backgroundColor = panelBackgroundColor
            view.addSubview(headerView)

            let closeButton = UIButton(type: .system)
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            let image = UIImage(systemName: "xmark.circle.fill")
            closeButton.setImage(image, for: .normal)
            closeButton.tintColor = .secondaryLabel
            closeButton.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)
            headerView.addSubview(closeButton)

            // WebKit Configuration
            let config = WKWebViewConfiguration()
            config.allowsInlineMediaPlayback = true
            config.defaultWebpagePreferences.allowsContentJavaScript = true

            let contentController = WKUserContentController()
            contentController.add(PoltioWeakScriptMessageHandler(target: self), name: Self.bridgeHandlerName)
            config.userContentController = contentController

            webView = WKWebView(frame: .zero, configuration: config)
            webView.translatesAutoresizingMaskIntoConstraints = false
            webView.navigationDelegate = self
            webView.uiDelegate = self
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = panelBackgroundColor
            view.addSubview(webView)

            // Activity Indicator
            activityIndicator = UIActivityIndicatorView(style: .medium)
            activityIndicator.translatesAutoresizingMaskIntoConstraints = false
            activityIndicator.hidesWhenStopped = true
            view.addSubview(activityIndicator)

            NSLayoutConstraint.activate([
                headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                headerView.heightAnchor.constraint(equalToConstant: 48),

                closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
                closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
                closeButton.widthAnchor.constraint(equalToConstant: 32),
                closeButton.heightAnchor.constraint(equalToConstant: 32),

                webView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
        }

        /// Helper that constructs the widget WebView URL with query parameters. Pass-through params
        /// (`content`, `custom_id`, `loc`, `resultfit`, `disclaimer`) reuse their `WidgetParams` key
        /// names verbatim as query keys, matching the existing `puid`/`disclaimer` convention.
        static func buildWidgetURL(
            publicId: String,
            widgetId: Int? = nil,
            puid: String?,
            disclaimer: String = "off",
            content: String? = nil,
            customId: String? = nil,
            loc: String? = nil,
            resultfit: String? = nil
        ) -> URL? {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "www.poltio.com"
            components.path = "/widget/\(publicId)"
            var queryItems: [URLQueryItem] = []

            func appendIfPresent(_ name: String, _ value: String?) {
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let trimmed, !trimmed.isEmpty else { return }
                queryItems.append(URLQueryItem(name: name, value: trimmed))
            }

            if let widgetId {
                queryItems.append(URLQueryItem(name: "widget_id", value: String(widgetId)))
            }
            appendIfPresent("puid", puid)
            appendIfPresent("content", content)
            appendIfPresent("custom_id", customId)
            appendIfPresent("loc", loc)
            appendIfPresent("resultfit", resultfit)

            queryItems.append(URLQueryItem(name: "disclaimer", value: disclaimer))
            components.queryItems = queryItems
            return components.url
        }

        private func loadWidgetURL() {
            let resolvedDisclaimer = overlayOptions?.disclaimer?.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = PoltioWebViewController.buildWidgetURL(
                publicId: publicId,
                widgetId: widgetId,
                puid: puid,
                disclaimer: (resolvedDisclaimer?.isEmpty == false ? resolvedDisclaimer : nil) ?? "off",
                content: overlayOptions?.content,
                customId: overlayOptions?.customId,
                loc: overlayOptions?.loc,
                resultfit: overlayOptions?.resultfit
            )
            guard let url else {
                PoltioLogger.error("Invalid widget URL string for publicId '\(publicId)'")
                return
            }

            PoltioLogger.debug("Loading widget WebView: \(url.absoluteString)")
            activityIndicator.startAnimating()
            let request = URLRequest(url: url)
            webView.load(request)
        }

        private func notifyDismiss() {
            guard !isDismissHandled else { return }
            isDismissHandled = true
            cleanupWebView()
            onDismiss?()
        }

        /// Stops any in-flight navigation and detaches the JS bridge handler. Safe to call more than once.
        private func cleanupWebView() {
            guard webView != nil else { return }
            webView.stopLoading()
            webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.bridgeHandlerName)
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }

        @objc private func didTapClose() {
            dismiss(animated: true) { [weak self] in
                self?.notifyDismiss()
            }
        }

        func presentationControllerDidDismiss(_: UIPresentationController) {
            notifyDismiss()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if isBeingDismissed || isMovingFromParent {
                notifyDismiss()
            }
        }

        // MARK: - Navigation Policy

        /// Whether `url` may load inside the widget WebView. The JS bridge (`poltioNative`) is exposed
        /// to whatever page is loaded, so main-frame navigation stays confined to Poltio's own domain;
        /// anything else (product links, external sites, `tel:`/`mailto:`, host-app deep links) is
        /// handed to the system instead. Mirrors Android's `PoltioWebViewActivity.isTrustedWidgetUrl`.
        static func isTrustedWidgetURL(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            if scheme == "about" || scheme == "blob" || scheme == "data" {
                return true
            }
            guard scheme == "https" || scheme == "http", let host = url.host?.lowercased() else {
                return false
            }
            return host == "poltio.com" || host.hasSuffix(".poltio.com")
        }

        private func openExternally(_ url: URL) {
            PoltioLogger.debug("Opening external URL outside the widget: \(url.absoluteString)")
            UIApplication.shared.open(url, options: [:]) { success in
                if !success {
                    PoltioLogger.warning("No app could open external URL '\(url.absoluteString)'.")
                }
            }
        }

        func webView(
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            // Sub-frame loads (e.g. embedded media inside the widget) never replace the widget page
            // itself, so they're allowed as-is — matching Android, where shouldOverrideUrlLoading
            // only intercepts main-frame navigations.
            if let targetFrame = navigationAction.targetFrame, !targetFrame.isMainFrame {
                decisionHandler(.allow)
                return
            }

            // A nil target frame means a new-window request (`target="_blank"` / `window.open`),
            // which WKWebView would otherwise silently drop.
            if navigationAction.targetFrame != nil, Self.isTrustedWidgetURL(url) {
                decisionHandler(.allow)
                return
            }

            decisionHandler(.cancel)
            openExternally(url)
        }

        // MARK: - WKUIDelegate

        func webView(
            _: WKWebView,
            createWebViewWith _: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures _: WKWindowFeatures
        ) -> WKWebView? {
            // Fallback for new-window requests that bypass the navigation policy above; never open a
            // second in-app WebView.
            if let url = navigationAction.request.url {
                openExternally(url)
            }
            return nil
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // The web content process was killed (e.g. memory pressure) — reload rather than leaving
            // a blank sheet. Never affects the host app's own process.
            PoltioLogger.warning("Widget WebView content process terminated; reloading.")
            webView.reload()
        }

        // MARK: - WKNavigationDelegate

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            activityIndicator.stopAnimating()
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            activityIndicator.stopAnimating()
            PoltioLogger.error("Webview navigation failed: \(error.localizedDescription)")
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            activityIndicator.stopAnimating()
            PoltioLogger.error("Webview provisional navigation failed: \(error.localizedDescription)")
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.bridgeHandlerName else { return }

            guard let body = message.body as? [String: Any], let event = body["event"] as? String else {
                PoltioLogger.warning("Received malformed widget bridge message: \(message.body)")
                return
            }

            let data = body["data"] as? [String: Any]
            PoltioLogger.debug("Received widget bridge event '\(event)'.")
            onWidgetEvent?(event, data)

            if event == "close" {
                dismiss(animated: true) { [weak self] in
                    self?.notifyDismiss()
                }
            }
        }
    }
#endif
