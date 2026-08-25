@testable import PoltioSDK
import XCTest

/// Helper mock URLProtocol for testing network requests without hitting live servers.
final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            XCTFail("Handler is not set.")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class PoltioSDKTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        PoltioSDK.shared.reset()
        MockURLProtocol.requestHandler = nil
    }

    private func createMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testConfigureWithValidKey() {
        let sdk = PoltioSDK.shared
        PoltioSDK.configure(clientKey: "poltio_test_pk_12345")

        XCTAssertTrue(sdk.isInitialized)
        XCTAssertEqual(sdk.clientKey, "poltio_test_pk_12345")
        XCTAssertFalse(sdk.sdkId.isEmpty)
    }

    func testConfigureWithEmptyKeyFails() {
        let sdk = PoltioSDK()
        sdk.configure(clientKey: "   ")

        XCTAssertFalse(sdk.isInitialized)
        XCTAssertNil(sdk.clientKey)
    }

    func testSDKIdIsGeneratedAndPersisted() {
        let sdk = PoltioSDK.shared
        let generatedId = sdk.sdkId

        XCTAssertFalse(generatedId.isEmpty)
        XCTAssertEqual(sdk.sdkId, generatedId, "sdkId should remain consistent across calls")
    }

    func testIdentifySetsAndClearsPuid() {
        let sdk = PoltioSDK.shared

        XCTAssertNil(sdk.puid)

        PoltioSDK.identify(puid: "user_puid_98765")
        XCTAssertEqual(sdk.puid, "user_puid_98765")

        PoltioSDK.identify(puid: "   user_puid_54321   ")
        XCTAssertEqual(sdk.puid, "user_puid_54321")

        PoltioSDK.identify(puid: "")
        XCTAssertNil(sdk.puid)

        PoltioSDK.identify(puid: "user_puid_123")
        XCTAssertEqual(sdk.puid, "user_puid_123")

        PoltioSDK.identify(puid: nil)
        XCTAssertNil(sdk.puid)
    }

    func testIsViewEventDetection() {
        let sdk = PoltioSDK.shared
        XCTAssertTrue(sdk.isViewEvent("view"))
        XCTAssertTrue(sdk.isViewEvent("VIEW"))
        XCTAssertTrue(sdk.isViewEvent("ViewContent"))
        XCTAssertTrue(sdk.isViewEvent("view_content"))
        XCTAssertFalse(sdk.isViewEvent("TrackConversion"))
        XCTAssertFalse(sdk.isViewEvent("purchase"))
    }

    func testSanitizeOrFormatURL() {
        // Full URLs with scheme and host should remain intact
        let fullURL = "https://www.poltio.com/products/sneakers?color=black"
        XCTAssertEqual(PoltioSDK.sanitizeOrFormatURL(fullURL), fullURL)

        let deepLink = "app://pdp/123"
        XCTAssertEqual(PoltioSDK.sanitizeOrFormatURL(deepLink), deepLink)

        // Absolute URIs with unencoded spaces or query parameters should be percent-encoded rather than prepended
        let urlWithSpaces = "https://example.com/pdp?name=foo bar"
        XCTAssertEqual(PoltioSDK.sanitizeOrFormatURL(urlWithSpaces), "https://example.com/pdp?name=foo%20bar")

        // Bare paths or names should be formatted with scheme and host
        XCTAssertEqual(PoltioSDK.sanitizeOrFormatURL("pdp"), "https://app.poltio.com/pdp")
        XCTAssertEqual(PoltioSDK.sanitizeOrFormatURL("/home/screen/"), "https://app.poltio.com/home/screen")
        XCTAssertEqual(PoltioSDK.sanitizeOrFormatURL(""), "https://app.poltio.com/default")
    }

    func testTrackViewEventWithFoundationURLObject() {
        let mockSession = createMockSession()
        let sdk = PoltioSDK.shared
        PoltioSDK.configure(clientKey: "pk_test_url_obj")

        let client = PoltioAPIClient(session: mockSession)
        sdk.apiClient = client

        let expectation = expectation(description: "Foundation URL object converted to string in API call")

        MockURLProtocol.requestHandler = { request in
            if let bodyData = request.httpBody ?? request.httpBodyStreamData(),
               let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: String]
            {
                XCTAssertEqual(json["url"], "https://www.poltio.com/checkout")
            } else {
                XCTFail("Failed to parse request body")
            }
            expectation.fulfill()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let dummyWidgetJSON = """
            {"public_id":"dummy_1","overlay_options":{"trigger-type":"box"}}
            """
            return (response, Data(dummyWidgetJSON.utf8))
        }

        guard let urlObj = URL(string: "https://www.poltio.com/checkout") else {
            XCTFail("Invalid URL")
            return
        }

        PoltioSDK.track(event: "view", params: ["url": urlObj])
        waitForExpectations(timeout: 2.0)
    }

    func testResolveMobileWidgetAPIClientRequestFormatting() {
        let mockSession = createMockSession()
        let client = PoltioAPIClient(session: mockSession)
        let expectation = expectation(description: "Network request completion")

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Poltio-SDK-Key"), "pk_test_key_123")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.url?.absoluteString, "https://sdk-stage.poltio.com/sdk/mobile/v1/widget")

            if let bodyData = request.httpBody ?? request.httpBodyStreamData(),
               let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: String]
            {
                XCTAssertEqual(json["url"], "https://www.poltio.com/pdp")
                XCTAssertEqual(json["device_id"], "device_abc_123")
            } else {
                XCTFail("Failed to parse request body")
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let jsonString = """
            {
              "public_id": "6c964c1d-6eb4-4c19-ad16-342bd59bdac3",
              "overlay_options": {
                "trigger-type": "box",
                "floating-box-text-first": "Product Finder",
                "floating-box-text-second": "Product Finder",
                "floating-img": "widget/box-default.png",
                "floating-initial-position": "active"
              }
            }
            """
            return (response, Data(jsonString.utf8))
        }

        client.resolveMobileWidget(
            clientKey: "pk_test_key_123",
            deviceId: "device_abc_123",
            targetURL: "https://www.poltio.com/pdp"
        ) { result in
            if case let .success(widget) = result {
                XCTAssertEqual(widget.publicId, "6c964c1d-6eb4-4c19-ad16-342bd59bdac3")
                XCTAssertEqual(widget.overlayOptions.triggerType, "box")
                XCTAssertEqual(widget.overlayOptions.floatingBoxTextFirst, "Product Finder")
                XCTAssertEqual(widget.overlayOptions.floatingBoxTextSecond, "Product Finder")
                XCTAssertEqual(widget.overlayOptions.floatingImg, "widget/box-default.png")
                XCTAssertTrue(widget.overlayOptions.isBoxTrigger)
                XCTAssertTrue(widget.overlayOptions.isInitialActive)
            } else {
                XCTFail("Expected success but got failure")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }

    func testPoltioWidgetResponseModelDecoding() throws {
        let json = """
        {
          "public_id": "test-uuid-12345",
          "overlay_options": {
            "trigger-type": "box",
            "floating-box-text-first": "Quiz Time",
            "floating-box-text-second": "Start Quiz",
            "floating-img": "https://cdn.poltio.com/banner.png",
            "floating-initial-position": "active",
            "mobile": {
              "floating-box-text-first": "Mobile Quiz"
            }
          }
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(PoltioWidgetResponse.self, from: data)

        XCTAssertEqual(decoded.publicId, "test-uuid-12345")
        XCTAssertEqual(decoded.overlayOptions.triggerType, "box")
        XCTAssertTrue(decoded.overlayOptions.isBoxTrigger)
        XCTAssertEqual(decoded.overlayOptions.floatingBoxTextFirst, "Mobile Quiz", "Mobile override should take precedence")
        XCTAssertEqual(decoded.overlayOptions.floatingBoxTextSecond, "Start Quiz")
        XCTAssertEqual(decoded.overlayOptions.floatingImg, "https://cdn.poltio.com/banner.png")
        XCTAssertTrue(decoded.overlayOptions.isInitialActive)
        XCTAssertEqual(decoded.overlayOptions.resolvedImageUrl()?.absoluteString, "https://cdn.poltio.com/banner.png")
    }

    func testResolvedImageUrlForRelativeAndAbsolutePaths() {
        let relativeOptions = PoltioOverlayOptions(floatingImg: "widget/box-default.png")
        XCTAssertEqual(
            relativeOptions.resolvedImageUrl()?.absoluteString,
            "https://cdn.poltio.com/240x120/widget/box-default.png"
        )

        let leadingSlashOptions = PoltioOverlayOptions(floatingImg: "/custom/img.png")
        XCTAssertEqual(
            leadingSlashOptions.resolvedImageUrl()?.absoluteString,
            "https://cdn.poltio.com/240x120/custom/img.png"
        )

        let absoluteOptions = PoltioOverlayOptions(floatingImg: "https://example.com/image.jpg")
        XCTAssertEqual(
            absoluteOptions.resolvedImageUrl()?.absoluteString,
            "https://example.com/image.jpg"
        )

        let emptySvgFallbackOptions = PoltioOverlayOptions(
            floatingImg: "widget/box-default.png",
            floatingSvg: ""
        )
        XCTAssertEqual(
            emptySvgFallbackOptions.resolvedImageUrl()?.absoluteString,
            "https://cdn.poltio.com/240x120/widget/box-default.png"
        )

        let whitespaceSvgFallbackOptions = PoltioOverlayOptions(
            floatingImg: "widget/box-default.png",
            floatingSvg: "   "
        )
        XCTAssertEqual(
            whitespaceSvgFallbackOptions.resolvedImageUrl()?.absoluteString,
            "https://cdn.poltio.com/240x120/widget/box-default.png"
        )

        let emptyOptions = PoltioOverlayOptions(floatingImg: "")
        XCTAssertNil(emptyOptions.resolvedImageUrl())

        let nilOptions = PoltioOverlayOptions(floatingImg: nil)
        XCTAssertNil(nilOptions.resolvedImageUrl())
    }

    func testTrackViewEventTriggersAPIWithoutCrashingOnServerError() {
        let mockSession = createMockSession()
        let sdk = PoltioSDK.shared
        PoltioSDK.configure(clientKey: "pk_test_key_999")

        let client = PoltioAPIClient(session: mockSession)
        sdk.apiClient = client

        let expectation = expectation(description: "API call handled safely on 500 error")

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            expectation.fulfill()
            return (response, Data("Internal Server Error".utf8))
        }

        // Tracking view event should trigger API call and handle 500 error gracefully
        PoltioSDK.track(event: "view", params: ["url": "pdp"])

        waitForExpectations(timeout: 2.0)
    }

    func testConcurrentAPIClientAccess() {
        let sdk = PoltioSDK.shared
        PoltioSDK.configure(clientKey: "pk_test_concurrent")

        let group = DispatchGroup()
        for i in 0 ..< 50 {
            group.enter()
            DispatchQueue.global().async {
                if i % 2 == 0 {
                    _ = sdk.apiClient
                } else {
                    sdk.apiClient = PoltioAPIClient()
                }
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 3.0)
        XCTAssertEqual(result, .success, "Concurrent access to apiClient should finish without deadlocking or racing")
    }

    func testPoltioWidgetResponsePillTriggerWithSvgDecoding() throws {
        let json = """
        {
          "public_id": "6c964c1d-6eb4-4c19-ad16-342bd59bdac3",
          "overlay_options": {
            "trigger-type": "pill",
            "floating-initial-position": "active",
            "floating-svg": "widget/PoltioSpark.svg"
          }
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(PoltioWidgetResponse.self, from: data)

        XCTAssertEqual(decoded.publicId, "6c964c1d-6eb4-4c19-ad16-342bd59bdac3")
        XCTAssertEqual(decoded.overlayOptions.triggerType, "pill")
        XCTAssertTrue(decoded.overlayOptions.isPillTrigger)
        XCTAssertFalse(decoded.overlayOptions.isBoxTrigger)
        XCTAssertEqual(decoded.overlayOptions.floatingSvg, "widget/PoltioSpark.svg")
        XCTAssertTrue(decoded.overlayOptions.isInitialActive)
        XCTAssertEqual(
            decoded.overlayOptions.resolvedImageUrl()?.absoluteString,
            "https://cdn.poltio.com/40x40/widget/PoltioSpark.svg"
        )
    }

    func testDynamicWidgetResolutionWithMockSession() {
        let mockSession = createMockSession()
        let client = PoltioAPIClient(session: mockSession)

        let homeExpectation = expectation(description: "Mock resolves Box for home")
        let phonesExpectation = expectation(description: "Mock resolves Pill for phones")
        let tvsExpectation = expectation(description: "Mock returns 404 for TVs")

        MockURLProtocol.requestHandler = { request in
            guard let bodyData = request.httpBody ?? request.httpBodyStreamData(),
                  let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: String],
                  let targetURL = json["url"]
            else {
                let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }

            if targetURL == "example://home" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                {
                  "public_id": "6c964c1d-6eb4-4c19-ad16-342bd59bdac3",
                  "overlay_options": {
                    "trigger-type": "box",
                    "floating-box-text-first": "Product Finder",
                    "floating-box-text-second": "Product Finder",
                    "floating-img": "widget/box-default.png",
                    "floating-initial-position": "active"
                  }
                }
                """
                return (response, Data(body.utf8))
            } else if targetURL == "example://plp/phones" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                {
                  "public_id": "6c964c1d-6eb4-4c19-ad16-342bd59bdac3",
                  "overlay_options": {
                    "trigger-type": "pill",
                    "floating-svg": "widget/1787042301.079.svg",
                    "floating-initial-position": "active"
                  }
                }
                """
                return (response, Data(body.utf8))
            } else {
                let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (response, Data("Not Found".utf8))
            }
        }

        client.resolveMobileWidget(
            clientKey: "pk_live_test_123",
            deviceId: "demo_device",
            targetURL: "example://home"
        ) { result in
            if case let .success(widget) = result {
                XCTAssertTrue(widget.overlayOptions.isBoxTrigger)
                XCTAssertEqual(widget.overlayOptions.floatingBoxTextFirst, "Product Finder")
            } else {
                XCTFail("Expected box widget for example://home")
            }
            homeExpectation.fulfill()
        }

        client.resolveMobileWidget(
            clientKey: "pk_live_test_123",
            deviceId: "demo_device",
            targetURL: "example://plp/phones"
        ) { result in
            if case let .success(widget) = result {
                XCTAssertTrue(widget.overlayOptions.isPillTrigger)
                XCTAssertEqual(widget.overlayOptions.floatingSvg, "widget/1787042301.079.svg")
                XCTAssertTrue(widget.overlayOptions.isInitialActive)
            } else {
                XCTFail("Expected pill widget for example://plp/phones")
            }
            phonesExpectation.fulfill()
        }

        client.resolveMobileWidget(
            clientKey: "pk_live_test_123",
            deviceId: "demo_device",
            targetURL: "example://plp/tvs"
        ) { result in
            if case .failure = result {
                // Expected 404
            } else {
                XCTFail("Expected failure/404 for unconfigured URL example://plp/tvs")
            }
            tvsExpectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }

    #if canImport(UIKit)
        func testBuildWidgetURLWithAndWithoutPUID() {
            let urlWithoutPuid = PoltioWebViewController.buildWidgetURL(publicId: "6c964c1d-6eb4-4c19-ad16-342bd59bdac3", puid: nil)
            XCTAssertEqual(urlWithoutPuid?.absoluteString, "https://www.poltio.com/widget/6c964c1d-6eb4-4c19-ad16-342bd59bdac3?disclaimer=off")

            let urlWithEmptyPuid = PoltioWebViewController.buildWidgetURL(publicId: "6c964c1d-6eb4-4c19-ad16-342bd59bdac3", puid: "   ")
            XCTAssertEqual(urlWithEmptyPuid?.absoluteString, "https://www.poltio.com/widget/6c964c1d-6eb4-4c19-ad16-342bd59bdac3?disclaimer=off")

            let urlWithPuid = PoltioWebViewController.buildWidgetURL(publicId: "6c964c1d-6eb4-4c19-ad16-342bd59bdac3", puid: "usr_123")
            XCTAssertEqual(urlWithPuid?.absoluteString, "https://www.poltio.com/widget/6c964c1d-6eb4-4c19-ad16-342bd59bdac3?puid=usr_123&disclaimer=off")
        }

        func testFloatingPillTriggerViewLifecycleAndStateTransitions() {
            let widget = PoltioWidgetResponse(
                publicId: "test-pill-widget",
                overlayOptions: PoltioOverlayOptions(
                    triggerType: "pill",
                    floatingBoxTextFirst: "Try our",
                    floatingBoxTextSecond: "PRODUCT FINDER",
                    floatingInitialPosition: "collapsed"
                )
            )

            var didOpenWidget = false
            let pillView = PoltioFloatingPillTriggerView(widget: widget) {
                didOpenWidget = true
            }

            XCTAssertEqual(pillView.currentState, .collapsed)

            // Test transition to expanded
            pillView.setState(.expanded, animated: false)
            XCTAssertEqual(pillView.currentState, .expanded)

            // Test resetToCollapsed
            pillView.resetToCollapsed(animated: false)
            XCTAssertEqual(pillView.currentState, .collapsed)
            XCTAssertFalse(didOpenWidget)
        }

        func testFloatingPillTriggerInitialActiveState() {
            let widget = PoltioWidgetResponse(
                publicId: "test-pill-active-widget",
                overlayOptions: PoltioOverlayOptions(
                    triggerType: "pill",
                    floatingBoxTextFirst: "Try our",
                    floatingBoxTextSecond: "PRODUCT FINDER",
                    floatingInitialPosition: "active"
                )
            )

            let pillView = PoltioFloatingPillTriggerView(widget: widget) {}
            XCTAssertEqual(pillView.currentState, .expanded)
        }

        func testSparklePathGeneration() {
            let rect = CGRect(x: 0, y: 0, width: 20, height: 20)
            let path = PoltioSparkleIconView.createSparklePath(in: rect)
            XCTAssertFalse(path.isEmpty)
            XCTAssertTrue(path.bounds.width > 0)
            XCTAssertTrue(path.bounds.height > 0)
        }

        func testPassthroughWindowHitTestingAndNotification() {
            let window = PoltioPassthroughWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
            let rootVC = PoltioOverlayRootViewController()
            window.rootViewController = rootVC
            rootVC.view.frame = window.bounds
            window.isHidden = false

            let triggerButton = UIButton(frame: CGRect(x: 200, y: 500, width: 100, height: 50))
            rootVC.view.addSubview(triggerButton)

            var notificationCount = 0
            let observer = NotificationCenter.default.addObserver(
                forName: PoltioFloatingPillTriggerView.didScrollNotification,
                object: nil,
                queue: .main
            ) { _ in
                notificationCount += 1
            }

            // Hit test directly on the trigger button
            let hitTrigger = window.hitTest(CGPoint(x: 250, y: 525), with: nil)
            XCTAssertEqual(hitTrigger, triggerButton)
            XCTAssertEqual(notificationCount, 0)

            // Hit test outside on empty window background (first time)
            let hitOutside = window.hitTest(CGPoint(x: 50, y: 50), with: nil)
            XCTAssertNil(hitOutside)
            XCTAssertEqual(notificationCount, 1)

            // Immediate second hit test outside should be throttled (within 0.1s)
            let hitOutsideRapid = window.hitTest(CGPoint(x: 50, y: 50), with: nil)
            XCTAssertNil(hitOutsideRapid)
            XCTAssertEqual(notificationCount, 1)

            NotificationCenter.default.removeObserver(observer)
        }

        func testPillTriggerSwipeGesturesConfiguration() {
            let widget = PoltioWidgetResponse(
                publicId: "test-pill-swipes",
                overlayOptions: PoltioOverlayOptions(triggerType: "pill")
            )
            let pillView = PoltioFloatingPillTriggerView(widget: widget) {}

            let swipeRecognizers = pillView.subviews
                .flatMap { $0.gestureRecognizers ?? [] }
                .compactMap { $0 as? UISwipeGestureRecognizer }

            XCTAssertEqual(swipeRecognizers.count, 2)
            XCTAssertTrue(swipeRecognizers.contains(where: { $0.direction == .right }))
            XCTAssertTrue(swipeRecognizers.contains(where: { $0.direction == .left }))
        }
    #endif

    func testLogLevelOrderingAndConfiguration() {
        XCTAssertTrue(PoltioLogLevel.none < PoltioLogLevel.error)
        XCTAssertTrue(PoltioLogLevel.error < PoltioLogLevel.warning)
        XCTAssertTrue(PoltioLogLevel.warning < PoltioLogLevel.info)
        XCTAssertTrue(PoltioLogLevel.info < PoltioLogLevel.debug)

        PoltioSDK.configure(clientKey: "pk_test_log_level", logLevel: .error)
        XCTAssertEqual(PoltioSDK.logLevel, .error)

        PoltioSDK.logLevel = .none
        XCTAssertEqual(PoltioSDK.logLevel, .none)

        PoltioSDK.logLevel = .debug
        XCTAssertEqual(PoltioSDK.logLevel, .debug)
    }

    func testInFlightRequestCancellationOnSubsequentView() {
        let mockSession = createMockSession()
        let client = PoltioAPIClient(session: mockSession)

        let cancelExpectation = expectation(description: "First request cancelled")

        let task = client.resolveMobileWidget(
            clientKey: "pk_test_cancel",
            deviceId: "dev_123",
            targetURL: "https://app.poltio.com/first"
        ) { result in
            switch result {
            case .success:
                XCTFail("Should have been cancelled")
            case let .failure(error):
                let nsError = error as NSError
                XCTAssertEqual(nsError.code, NSURLErrorCancelled)
                cancelExpectation.fulfill()
            }
        }

        XCTAssertNotNil(task)
        task?.cancel()

        waitForExpectations(timeout: 2.0)
    }
}

private extension URLRequest {
    func httpBodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        stream.open()
        defer { stream.close() }

        var data = Data()
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }
}
