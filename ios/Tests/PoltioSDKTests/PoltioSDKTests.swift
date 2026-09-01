@testable import PoltioSDK
import XCTest

/// Helper mock URLProtocol for testing network requests without hitting live servers.
final class MockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var _requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _requestHandler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _requestHandler = newValue
        }
    }

    private var isStopped = false

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard !isStopped else { return }

        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(
                self,
                didFailWithError: NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorCancelled,
                    userInfo: [NSLocalizedDescriptionKey: "Handler is not set."]
                )
            )
            return
        }

        do {
            let (response, data) = try handler(request)
            guard !isStopped else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            guard !isStopped else { return }
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        isStopped = true
    }
}

final class PoltioSDKTests: XCTestCase {
    private var activeSessions: [URLSession] = []

    override func tearDown() {
        super.tearDown()
        PoltioSDK.shared.reset()
        MockURLProtocol.requestHandler = nil
        for session in activeSessions {
            session.invalidateAndCancel()
        }
        activeSessions.removeAll()
    }

    private func createMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        activeSessions.append(session)
        return session
    }

    func testConfigureWithValidKey() {
        let sdk = PoltioSDK.shared
        PoltioSDK.configure(clientKey: "poltio_test_pk_12345")

        XCTAssertTrue(sdk.isInitialized)
        XCTAssertEqual(sdk.clientKey, "poltio_test_pk_12345")
        XCTAssertFalse(sdk.sdkId.isEmpty)
    }

    func testConfigureAutoDetectsEnvironmentMatchingBuildConfiguration() {
        // With no `useStage` override, the resolved base URL must match automatic detection for
        // whatever build configuration is executing this test (Debug vs. Release).
        let sdk = PoltioSDK()
        sdk.configure(clientKey: "pk_test_auto_env")

        #if DEBUG
            XCTAssertEqual(sdk.apiClient.baseURLForTesting, PoltioAPIClient.stageBaseURL)
        #else
            XCTAssertEqual(sdk.apiClient.baseURLForTesting, PoltioAPIClient.productionBaseURL)
        #endif
    }

    func testConfigureWithUseStageFalseForcesProduction() {
        let sdk = PoltioSDK()
        sdk.configure(clientKey: "pk_test_force_prod", useStage: false)

        XCTAssertEqual(sdk.apiClient.baseURLForTesting, PoltioAPIClient.productionBaseURL)
    }

    func testConfigureWithUseStageTrueForcesStage() {
        let sdk = PoltioSDK()
        sdk.configure(clientKey: "pk_test_force_stage", useStage: true)

        XCTAssertEqual(sdk.apiClient.baseURLForTesting, PoltioAPIClient.stageBaseURL)
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
        let requestStartedExpectation = expectation(description: "Request started loading in mock protocol")
        let cancelSemaphore = DispatchSemaphore(value: 0)

        MockURLProtocol.requestHandler = { _ in
            requestStartedExpectation.fulfill()
            _ = cancelSemaphore.wait(timeout: .now() + 1.0)
            let response = HTTPURLResponse(
                url: URL(string: "https://app.poltio.com/first")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

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
        wait(for: [requestStartedExpectation], timeout: 2.0)
        task?.cancel()
        cancelSemaphore.signal()

        wait(for: [cancelExpectation], timeout: 2.0)
    }

    func testWidgetCacheHitAndAvoidsAPIRequest() {
        let mockSession = createMockSession()
        let sdk = PoltioSDK.shared
        PoltioSDK.configure(clientKey: "pk_test_cache_hit")
        sdk.apiClient = PoltioAPIClient(session: mockSession)

        var requestCount = 0
        let requestLock = NSLock()
        let firstExpectation = expectation(description: "First network request fulfilled")

        MockURLProtocol.requestHandler = { request in
            requestLock.lock()
            requestCount += 1
            let count = requestCount
            requestLock.unlock()

            if count == 1 {
                firstExpectation.fulfill()
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let jsonString = """
            {
              "public_id": "cache-test-public-id",
              "overlay_options": {
                "trigger-type": "box",
                "floating-box-text-first": "Cached Widget"
              }
            }
            """
            return (response, Data(jsonString.utf8))
        }

        // First track call -> triggers network request
        PoltioSDK.track(event: "view", params: ["url": "https://example.com/shop/item1"])
        wait(for: [firstExpectation], timeout: 2.0)

        let populatedExp = expectation(description: "Wait for cache populated")
        let startTime = Date()
        func pollCache() {
            if sdk.widgetCache.get(for: "https://example.com/shop/item1") != nil {
                populatedExp.fulfill()
            } else if Date().timeIntervalSince(startTime) < 2.0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) {
                    pollCache()
                }
            }
        }
        pollCache()
        wait(for: [populatedExp], timeout: 2.0)

        requestLock.lock()
        XCTAssertEqual(requestCount, 1)
        requestLock.unlock()

        // Second track call to same URL -> should hit cache and NOT trigger network request
        PoltioSDK.track(event: "view", params: ["url": "https://example.com/shop/item1"])

        // Small delay to ensure no asynchronous task was dispatched
        let exp = expectation(description: "Wait after second call")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        requestLock.lock()
        XCTAssertEqual(requestCount, 1, "Second visit to same URL within 5 minutes must use cache and not make API call")
        requestLock.unlock()
    }

    func testWidgetCacheExpirationTTL() {
        let cache = PoltioWidgetCache(defaultTTL: 0.05, countLimit: 10)
        let response = PoltioWidgetResponse(
            publicId: "expiring-widget",
            overlayOptions: PoltioOverlayOptions(triggerType: "box")
        )

        cache.set(result: .widget(response), for: "https://example.com/expiring")

        // Immediately should be present
        guard case let .widget(cached) = cache.get(for: "https://example.com/expiring") else {
            XCTFail("Expected widget in cache immediately")
            return
        }
        XCTAssertEqual(cached.publicId, "expiring-widget")

        // Wait for TTL (0.05s) to expire
        Thread.sleep(forTimeInterval: 0.07)

        // After TTL expiry, cache lookup should return nil
        XCTAssertNil(cache.get(for: "https://example.com/expiring"), "Expired cache entry should return nil")
    }

    func testWidgetCacheNegativeResult404() {
        let mockSession = createMockSession()
        let sdk = PoltioSDK.shared
        PoltioSDK.configure(clientKey: "pk_test_404_cache")
        sdk.apiClient = PoltioAPIClient(session: mockSession)

        var requestCount = 0
        let requestLock = NSLock()
        let firstExpectation = expectation(description: "First 404 request completed")

        MockURLProtocol.requestHandler = { request in
            requestLock.lock()
            requestCount += 1
            let count = requestCount
            requestLock.unlock()

            if count == 1 {
                firstExpectation.fulfill()
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("Not Found".utf8))
        }

        // First track call -> triggers 404 from server
        PoltioSDK.track(event: "view", params: ["url": "https://example.com/no-widget-page"])
        wait(for: [firstExpectation], timeout: 2.0)

        let populated404Exp = expectation(description: "Wait for 404 cache populated")
        let startTime404 = Date()
        func poll404Cache() {
            if sdk.widgetCache.get(for: "https://example.com/no-widget-page") == .noWidget {
                populated404Exp.fulfill()
            } else if Date().timeIntervalSince(startTime404) < 2.0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) {
                    poll404Cache()
                }
            }
        }
        poll404Cache()
        wait(for: [populated404Exp], timeout: 2.0)

        requestLock.lock()
        XCTAssertEqual(requestCount, 1)
        requestLock.unlock()

        // Second track call for same 404 page -> should use cached negative result
        PoltioSDK.track(event: "view", params: ["url": "https://example.com/no-widget-page"])

        let exp = expectation(description: "Wait after second 404 call")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        requestLock.lock()
        XCTAssertEqual(requestCount, 1, "Repeated navigation to 404 page within 5 minutes should not re-query server")
        requestLock.unlock()
    }

    func testWidgetCacheCountLimit() {
        let cache = PoltioWidgetCache(defaultTTL: 300.0, countLimit: 2)
        let response1 = PoltioWidgetResponse(
            publicId: "widget-1",
            overlayOptions: PoltioOverlayOptions(triggerType: "box")
        )
        let response2 = PoltioWidgetResponse(
            publicId: "widget-2",
            overlayOptions: PoltioOverlayOptions(triggerType: "box")
        )
        let response3 = PoltioWidgetResponse(
            publicId: "widget-3",
            overlayOptions: PoltioOverlayOptions(triggerType: "box")
        )

        cache.set(result: .widget(response1), for: "https://example.com/1")
        cache.set(result: .widget(response2), for: "https://example.com/2")
        cache.set(result: .widget(response3), for: "https://example.com/3")

        XCTAssertNotNil(cache.get(for: "https://example.com/3"))
    }

    func testWidgetCacheTransientErrorNotCached() {
        let mockSession = createMockSession()
        let sdk = PoltioSDK.shared
        PoltioSDK.configure(clientKey: "pk_test_500_not_cached")
        sdk.apiClient = PoltioAPIClient(session: mockSession)

        var requestCount = 0
        let requestLock = NSLock()
        let firstExp = expectation(description: "First 500 error completed")
        let secondExp = expectation(description: "Second request completed on retry")

        MockURLProtocol.requestHandler = { request in
            requestLock.lock()
            requestCount += 1
            let count = requestCount
            requestLock.unlock()

            if count == 1 {
                firstExp.fulfill()
                let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (response, Data("Server Error".utf8))
            } else {
                secondExp.fulfill()
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let json = """
                {"public_id":"recovered_id","overlay_options":{"trigger-type":"box"}}
                """
                return (response, Data(json.utf8))
            }
        }

        PoltioSDK.track(event: "view", params: ["url": "https://example.com/flaky"])
        wait(for: [firstExp], timeout: 2.0)

        // Second call should retry because 500 error was NOT cached
        PoltioSDK.track(event: "view", params: ["url": "https://example.com/flaky"])
        wait(for: [secondExp], timeout: 2.0)

        requestLock.lock()
        XCTAssertEqual(requestCount, 2, "Transient 500 server error should not be cached")
        requestLock.unlock()
    }

    func testClearCacheAndCustomTTLAndLimit() {
        let sdk = PoltioSDK.shared
        PoltioSDK.configure(clientKey: "pk_test_cache_config")

        XCTAssertEqual(PoltioSDK.cacheTTL, 300.0)
        XCTAssertEqual(PoltioSDK.cacheLimit, 100)

        PoltioSDK.cacheTTL = 120.0
        XCTAssertEqual(PoltioSDK.cacheTTL, 120.0)

        PoltioSDK.cacheLimit = 50
        XCTAssertEqual(PoltioSDK.cacheLimit, 50)

        PoltioSDK.clearCache()

        // Test with cacheTTL = 0 (disabled cache)
        let mockSession = createMockSession()
        sdk.apiClient = PoltioAPIClient(session: mockSession)
        PoltioSDK.cacheTTL = 0

        var requestCount = 0
        let requestLock = NSLock()
        let req1Exp = expectation(description: "Req 1")
        let req2Exp = expectation(description: "Req 2")

        MockURLProtocol.requestHandler = { request in
            requestLock.lock()
            requestCount += 1
            let count = requestCount
            requestLock.unlock()

            if count == 1 {
                req1Exp.fulfill()
            } else if count == 2 {
                req2Exp.fulfill()
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"public_id\":\"test\",\"overlay_options\":{}}".utf8))
        }

        PoltioSDK.track(event: "view", params: ["url": "https://example.com/no-cache"])
        wait(for: [req1Exp], timeout: 2.0)

        PoltioSDK.track(event: "view", params: ["url": "https://example.com/no-cache"])
        wait(for: [req2Exp], timeout: 2.0)

        requestLock.lock()
        XCTAssertEqual(requestCount, 2, "When cacheTTL is 0, cache is disabled and every track triggers network request")
        requestLock.unlock()
    }

    func testConcurrentCacheOperations() {
        let cache = PoltioWidgetCache(defaultTTL: 300.0, countLimit: 100)
        let group = DispatchGroup()

        for i in 0 ..< 100 {
            group.enter()
            DispatchQueue.global().async {
                let url = "https://example.com/page/\(i % 10)"
                if i % 3 == 0 {
                    let dummyWidget = PoltioWidgetResponse(
                        publicId: "widget_\(i)",
                        overlayOptions: PoltioOverlayOptions(triggerType: "box")
                    )
                    cache.set(result: .widget(dummyWidget), for: url)
                } else if i % 3 == 1 {
                    cache.set(result: .noWidget, for: url)
                } else {
                    _ = cache.get(for: url)
                }

                if i % 25 == 0 {
                    cache.clear()
                }
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 3.0)
        XCTAssertEqual(result, .success, "Concurrent cache operations must finish safely without deadlocking")
    }

    func testCardTriggerResponseDecodingWithLivePayload() throws {
        let json = """
        {
          "id": 401,
          "public_id": "6c964c1d-6eb4-4c19-ad16-342bd59bdac3",
          "overlay_options": {
            "floating-bar-text-button": "Get Started",
            "floating-bar-text-color-button": "black",
            "floating-bar-text-color-first": "white",
            "floating-bar-text-color-second": "white",
            "floating-bar-text-first": "Try Our",
            "floating-bar-text-second": "Product Finder",
            "floating-bgcolor": "rgb(174, 174, 209)",
            "floating-box-bg-color-first": "white",
            "floating-box-bg-color-second": "white",
            "floating-box-close-remember-duration": "48",
            "floating-box-full-image-mode": "false",
            "floating-box-open-on-scroll": "true",
            "floating-box-resize": "1",
            "floating-box-show-close-button": "false",
            "floating-box-start-mode": "closed",
            "floating-box-text-align-first": "flex-start",
            "floating-box-text-align-second": "flex-start",
            "floating-box-text-color-first": "black",
            "floating-box-text-color-second": "black",
            "floating-box-text-first-font-size": "1rem",
            "floating-box-text-first-font-weight": "700",
            "floating-box-text-second-font-size": "1.25rem",
            "floating-box-text-second-font-weight": "700",
            "floating-buttontext": "Start Now",
            "floating-desc": "Let's find your perfect new TV together",
            "floating-design-type": "2025-01",
            "floating-display-type": "slideover",
            "floating-hide-button": "false",
            "floating-icon-color": "#1E3D54",
            "floating-initial-position": "collapsed",
            "floating-mobile-top-border-radius": "1.75em",
            "floating-pill-close-remember-duration": "48",
            "floating-pill-show-close-button": "false",
            "floating-pill-start-mode": "closed",
            "floating-position": "bottom-right",
            "floating-product-card-enabled": "false",
            "floating-pulsate-color": "white",
            "floating-show-pulsate": "true",
            "floating-text-color-first": "white",
            "floating-text-color-second": "white",
            "floating-text-color-third": "#CA9B6F",
            "floating-text-first": "Try our",
            "floating-text-second": "PRODUCT",
            "floating-text-third": "FINDER",
            "floating-textcolor": "white",
            "floating-title": "TV Finder",
            "floating-widget-icon-color": "#1E3D54",
            "floating-zindex": "100",
            "widget-bgcolor": "white",
            "widget-disclaimer": "off"
          }
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(PoltioWidgetResponse.self, from: data)

        XCTAssertEqual(decoded.publicId, "6c964c1d-6eb4-4c19-ad16-342bd59bdac3")
        XCTAssertTrue(decoded.overlayOptions.isCardTrigger, "Should detect card / slideover trigger")
        XCTAssertFalse(decoded.overlayOptions.isBoxTrigger, "Should not be box trigger")
        XCTAssertFalse(decoded.overlayOptions.isPillTrigger, "Should not be pill trigger")
        XCTAssertEqual(decoded.overlayOptions.triggerType, "card")
        XCTAssertEqual(decoded.overlayOptions.floatingTitle, "TV Finder")
        XCTAssertEqual(decoded.overlayOptions.floatingDesc, "Let's find your perfect new TV together")
        XCTAssertEqual(decoded.overlayOptions.floatingButtonText, "Start Now")
        XCTAssertEqual(decoded.overlayOptions.floatingDesignType, "2025-01")
        XCTAssertEqual(decoded.overlayOptions.floatingDisplayType, "slideover")
        XCTAssertEqual(decoded.overlayOptions.floatingBgColor, "rgb(174, 174, 209)")
        XCTAssertEqual(decoded.overlayOptions.floatingTextColor, "white")
        XCTAssertEqual(decoded.overlayOptions.floatingIconColor, "#1E3D54")
        XCTAssertEqual(decoded.overlayOptions.floatingPosition, "bottom-right")
        XCTAssertEqual(decoded.overlayOptions.floatingMobileTopBorderRadius, "1.75em")
        XCTAssertFalse(decoded.overlayOptions.isInitialActive)

        #if canImport(UIKit)
            let bgColor = decoded.overlayOptions.resolvedBgColor
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            bgColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            XCTAssertEqual(round(r * 255), 174)
            XCTAssertEqual(round(g * 255), 174)
            XCTAssertEqual(round(b * 255), 209)

            let iconColor = decoded.overlayOptions.resolvedIconColor
            iconColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            XCTAssertEqual(round(r * 255), 0x1E)
            XCTAssertEqual(round(g * 255), 0x3D)
            XCTAssertEqual(round(b * 255), 0x54)

            let textColor = decoded.overlayOptions.resolvedTextColor
            textColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            XCTAssertEqual(round(r * 255), 255)
            XCTAssertEqual(round(g * 255), 255)
            XCTAssertEqual(round(b * 255), 255)
        #endif
    }

    #if canImport(UIKit)
        func testColorParser() {
            // Hex tests
            let hex6 = PoltioColorParser.parse("#00A3FF")
            XCTAssertNotNil(hex6)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            hex6?.getRed(&r, green: &g, blue: &b, alpha: &a)
            XCTAssertEqual(round(r * 255), 0)
            XCTAssertEqual(round(g * 255), 163)
            XCTAssertEqual(round(b * 255), 255)

            let hex3 = PoltioColorParser.parse("#FFF")
            XCTAssertNotNil(hex3)
            hex3?.getRed(&r, green: &g, blue: &b, alpha: &a)
            XCTAssertEqual(round(r * 255), 255)
            XCTAssertEqual(round(g * 255), 255)
            XCTAssertEqual(round(b * 255), 255)

            // 8-digit hex follows CSS Color Module Level 4: #RRGGBBAA
            let hex8 = PoltioColorParser.parse("#00A3FF80")
            XCTAssertNotNil(hex8)
            hex8?.getRed(&r, green: &g, blue: &b, alpha: &a)
            XCTAssertEqual(round(r * 255), 0)
            XCTAssertEqual(round(g * 255), 163)
            XCTAssertEqual(round(b * 255), 255)
            XCTAssertEqual(round(a * 255), 128)

            // RGB / RGBA tests
            let rgb = PoltioColorParser.parse("rgb(100, 150, 200)")
            XCTAssertNotNil(rgb)
            rgb?.getRed(&r, green: &g, blue: &b, alpha: &a)
            XCTAssertEqual(round(r * 255), 100)
            XCTAssertEqual(round(g * 255), 150)
            XCTAssertEqual(round(b * 255), 200)

            let rgba = PoltioColorParser.parse("rgba(100, 150, 200, 0.5)")
            XCTAssertNotNil(rgba)
            rgba?.getRed(&r, green: &g, blue: &b, alpha: &a)
            XCTAssertEqual(a, 0.5, accuracy: 0.01)

            // Named colors
            let white = PoltioColorParser.parse("white")
            XCTAssertEqual(white, UIColor.white)
            let black = PoltioColorParser.parse("black")
            XCTAssertEqual(black, UIColor.black)

            // Invalid string
            let invalid = PoltioColorParser.parse("not_a_valid_color_string")
            XCTAssertNil(invalid)
        }

        func testFloatingCardTriggerViewInteractions() {
            let options = PoltioOverlayOptions(
                floatingTitle: "Custom Title",
                floatingDesc: "Custom Description",
                floatingButtonText: "Let's Go",
                floatingBgColor: "#00A3FF",
                floatingTextColor: "white",
                floatingIconColor: "#1E3D54",
                floatingDesignType: "2025-01",
                floatingDisplayType: "slideover"
            )
            let widget = PoltioWidgetResponse(
                publicId: "card_widget_123",
                overlayOptions: options
            )

            var openCount = 0
            let cardView = PoltioFloatingCardTriggerView(
                widget: widget,
                onOpenWidget: {
                    openCount += 1
                }
            )

            XCTAssertEqual(cardView.currentState, .collapsed)

            // Expand
            cardView.setState(.expanded, animated: false)
            XCTAssertEqual(cardView.currentState, .expanded)

            // Reset to collapsed
            cardView.resetToCollapsed(animated: false)
            XCTAssertEqual(cardView.currentState, .collapsed)

            // Test initial active option
            let activeOptions = PoltioOverlayOptions(
                floatingTitle: "Active Title",
                floatingInitialPosition: "active",
                floatingDesignType: "2025-01"
            )
            let activeWidget = PoltioWidgetResponse(publicId: "active_1", overlayOptions: activeOptions)
            let activeCardView = PoltioFloatingCardTriggerView(widget: activeWidget, onOpenWidget: {})
            XCTAssertEqual(activeCardView.currentState, .expanded)
        }

        func testOverlayManagerCardTriggerPresentation() {
            let options = PoltioOverlayOptions(
                floatingTitle: "TV Finder",
                floatingDesc: "Let's find your perfect new TV together",
                floatingButtonText: "Start Now",
                floatingBgColor: "rgb(174, 174, 209)",
                floatingDesignType: "2025-01",
                floatingDisplayType: "slideover"
            )
            let widget = PoltioWidgetResponse(
                publicId: "tv_widget_401",
                overlayOptions: options
            )

            let overlayManager = PoltioOverlayManager.shared
            overlayManager.showTrigger(widget: widget, puid: "test_puid_tv")

            let exp = expectation(description: "Wait for overlay manager async dispatch")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                overlayManager.hideTrigger()
                exp.fulfill()
            }
            wait(for: [exp], timeout: 1.0)
        }
    #endif
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
