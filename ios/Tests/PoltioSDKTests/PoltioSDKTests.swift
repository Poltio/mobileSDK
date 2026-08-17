@testable import PoltioSDK
import XCTest

/// Helper mock URLProtocol for testing network requests without hitting live servers.
final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    override class func canInit(with _: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            XCTFail("Handler is not set.")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
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

    #if canImport(UIKit)
        func testBuildWidgetURLWithAndWithoutPUID() {
            let urlWithoutPuid = PoltioWebViewController.buildWidgetURL(publicId: "6c964c1d-6eb4-4c19-ad16-342bd59bdac3", puid: nil)
            XCTAssertEqual(urlWithoutPuid?.absoluteString, "https://www.poltio.com/widget/6c964c1d-6eb4-4c19-ad16-342bd59bdac3?disclaimer=off")

            let urlWithEmptyPuid = PoltioWebViewController.buildWidgetURL(publicId: "6c964c1d-6eb4-4c19-ad16-342bd59bdac3", puid: "   ")
            XCTAssertEqual(urlWithEmptyPuid?.absoluteString, "https://www.poltio.com/widget/6c964c1d-6eb4-4c19-ad16-342bd59bdac3?disclaimer=off")

            let urlWithPuid = PoltioWebViewController.buildWidgetURL(publicId: "6c964c1d-6eb4-4c19-ad16-342bd59bdac3", puid: "usr_123")
            XCTAssertEqual(urlWithPuid?.absoluteString, "https://www.poltio.com/widget/6c964c1d-6eb4-4c19-ad16-342bd59bdac3?puid=usr_123&disclaimer=off")
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
