#if canImport(UIKit)
import UIKit
import WebKit

/// In-app browser modal presenting the interactive Poltio widget WebView.
public final class PoltioWebViewController: UIViewController, WKNavigationDelegate, UIAdaptivePresentationControllerDelegate {
    private let publicId: String
    private let puid: String?
    private var webView: WKWebView!
    private var activityIndicator: UIActivityIndicatorView!

    /// Callback invoked when the modal is dismissed (via close button or swipe down).
    public var onDismiss: (() -> Void)?
    private var isDismissHandled = false

    public init(publicId: String, puid: String? = nil, onDismiss: (() -> Void)? = nil) {
        self.publicId = publicId
        self.puid = puid
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        presentationController?.delegate = self
        setupUI()
        loadWidgetURL()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        // Header Navigation / Close Bar
        let headerView = UIView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = .systemBackground
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

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .systemBackground
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

    /// Helper that constructs the widget WebView URL with query parameters.
    public static func buildWidgetURL(
        publicId: String,
        puid: String?,
        disclaimer: String = "off"
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.poltio.com"
        components.path = "/widget/\(publicId)"
        var queryItems: [URLQueryItem] = []

        if let puid = puid?.trimmingCharacters(in: .whitespacesAndNewlines), !puid.isEmpty {
            queryItems.append(URLQueryItem(name: "puid", value: puid))
        }

        queryItems.append(URLQueryItem(name: "disclaimer", value: disclaimer))
        components.queryItems = queryItems
        return components.url
    }

    private func loadWidgetURL() {
        guard let url = PoltioWebViewController.buildWidgetURL(publicId: publicId, puid: puid) else {
            print("[PoltioSDK] Error: Invalid widget URL string for publicId '\(publicId)'")
            return
        }

        print("[PoltioSDK] Loading widget WebView: \(url.absoluteString)")
        activityIndicator.startAnimating()
        let request = URLRequest(url: url)
        webView.load(request)
    }

    private func notifyDismiss() {
        guard !isDismissHandled else { return }
        isDismissHandled = true
        onDismiss?()
    }

    @objc private func didTapClose() {
        dismiss(animated: true) { [weak self] in
            self?.notifyDismiss()
        }
    }

    public func presentationControllerDidDismiss(_: UIPresentationController) {
        notifyDismiss()
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            notifyDismiss()
        }
    }

    // MARK: - WKNavigationDelegate

    public func webView(_: WKWebView, didFinish _: WKNavigation!) {
        activityIndicator.stopAnimating()
    }

    public func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
        print("[PoltioSDK] Webview navigation failed: \(error.localizedDescription)")
    }

    public func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
        print("[PoltioSDK] Webview provisional navigation failed: \(error.localizedDescription)")
    }
}
#endif
