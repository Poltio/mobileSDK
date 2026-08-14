import XCTest
@testable import PoltioSDK

/// Helper mock URLProtocol for testing network requests without hitting live servers.
final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    override class func canInit(with request: URLRequest) -> Bool {
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
        
        // Bare paths or names should be formatted with scheme and host
        XCTAssertEqual(PoltioSDK.sanitizeOrFormatURL("pdp"), "https://app.poltio.com/pdp")
        XCTAssertEqual(PoltioSDK.sanitizeOrFormatURL("/home/screen/"), "https://app.poltio.com/home/screen")
        XCTAssertEqual(PoltioSDK.sanitizeOrFormatURL(""), "https://app.poltio.com/default")
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
               let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: String] {
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
            return (response, Data("{}".utf8))
        }
        
        client.resolveMobileWidget(
            clientKey: "pk_test_key_123",
            deviceId: "device_abc_123",
            targetURL: "https://www.poltio.com/pdp"
        ) { result in
            if case .success(let httpResp) = result {
                XCTAssertEqual(httpResp.statusCode, 200)
            } else {
                XCTFail("Expected success but got failure")
            }
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0)
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
