#if canImport(UIKit)
    import UIKit
    #if canImport(WebKit)
        import WebKit
    #endif

    /// Loads a remote SVG or raster image (`floatingSvg`/`floatingImg`) into an icon-sized slot, used by
    /// triggers that show an optional custom icon in place of their default sparkle mark. SVGs render via
    /// a lightweight, JS-disabled `WKWebView` (there's no first-party SVG renderer in UIKit); it's created
    /// on demand since most triggers never load one.
    final class PoltioTriggerIconLoader {
        private weak var container: UIView?
        private let size: CGFloat
        private var imageView: UIImageView?
        private var svgWebView: WKWebView?
        private var task: URLSessionDataTask?

        init(container: UIView, size: CGFloat) {
            self.container = container
            self.size = size
        }

        deinit {
            task?.cancel()
            let webView = svgWebView
            DispatchQueue.main.async {
                webView?.stopLoading()
            }
        }

        /// Attempts to load `overlayOptions`'s custom icon, centered on `anchor`. Calls `onLoaded` (main
        /// thread) once an image/SVG successfully renders; the caller is responsible for hiding its
        /// fallback icon there. A no-op if no icon URL is configured or the download/decode fails.
        func load(from overlayOptions: PoltioOverlayOptions, centeredOn anchor: UIView, onLoaded: @escaping () -> Void) {
            guard let container, let url = overlayOptions.resolvedImageUrl() else { return }

            let hasSvg = !(overlayOptions.floatingSvg?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let isSvgFile = url.pathExtension.lowercased() == "svg" || hasSvg

            task?.cancel()
            task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                guard let self, let container = self.container, let data, error == nil else { return }

                let mimeType = response?.mimeType?.lowercased() ?? ""
                let utf8String = String(data: data, encoding: .utf8)
                let isSvgContent = isSvgFile || mimeType.contains("svg") || (utf8String?.contains("<svg") == true)

                if isSvgContent, let svgString = utf8String {
                    DispatchQueue.main.async {
                        self.showSvg(svgString, in: container, centeredOn: anchor, onLoaded: onLoaded)
                    }
                } else if let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self.showImage(image, in: container, centeredOn: anchor, onLoaded: onLoaded)
                    }
                }
            }
            task?.resume()
        }

        private func showImage(_ image: UIImage, in container: UIView, centeredOn anchor: UIView, onLoaded: () -> Void) {
            let imageView = ensureImageView(in: container, centeredOn: anchor)
            imageView.image = image
            imageView.isHidden = false
            svgWebView?.isHidden = true
            onLoaded()
        }

        private func showSvg(_ svgString: String, in container: UIView, centeredOn anchor: UIView, onLoaded: () -> Void) {
            let webView = ensureSvgWebView(in: container, centeredOn: anchor)
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            html, body {
                background: transparent;
                width: 100%;
                height: 100%;
                display: flex;
                align-items: center;
                justify-content: center;
                overflow: hidden;
            }
            svg {
                width: 100%;
                height: 100%;
                max-width: \(Int(size))px;
                max-height: \(Int(size))px;
            }
            </style>
            </head>
            <body>
            \(svgString)
            </body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: nil)
            webView.isHidden = false
            imageView?.isHidden = true
            onLoaded()
        }

        private func ensureImageView(in container: UIView, centeredOn anchor: UIView) -> UIImageView {
            if let existing = imageView {
                return existing
            }
            let iv = UIImageView()
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.contentMode = .scaleAspectFit
            iv.clipsToBounds = true
            container.addSubview(iv)
            NSLayoutConstraint.activate([
                iv.centerXAnchor.constraint(equalTo: anchor.centerXAnchor),
                iv.centerYAnchor.constraint(equalTo: anchor.centerYAnchor),
                iv.widthAnchor.constraint(equalToConstant: size),
                iv.heightAnchor.constraint(equalToConstant: size),
            ])
            imageView = iv
            return iv
        }

        private func ensureSvgWebView(in container: UIView, centeredOn anchor: UIView) -> WKWebView {
            if let existing = svgWebView {
                return existing
            }
            let config = WKWebViewConfiguration()
            config.defaultWebpagePreferences.allowsContentJavaScript = false
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.translatesAutoresizingMaskIntoConstraints = false
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear
            webView.scrollView.isScrollEnabled = false
            webView.isUserInteractionEnabled = false
            container.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.centerXAnchor.constraint(equalTo: anchor.centerXAnchor),
                webView.centerYAnchor.constraint(equalTo: anchor.centerYAnchor),
                webView.widthAnchor.constraint(equalToConstant: size),
                webView.heightAnchor.constraint(equalToConstant: size),
            ])
            svgWebView = webView
            return webView
        }
    }
#endif
