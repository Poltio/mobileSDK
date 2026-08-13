import XCTest
@testable import PoltioSDK

final class PoltioSDKTests: XCTestCase {
    
    override func tearDown() {
        super.tearDown()
        PoltioSDK.shared.reset()
    }
    
    func testConfigureWithValidKey() {
        let sdk = PoltioSDK.shared
        PoltioSDK.configure(clientKey: "poltio_test_pk_12345")
        
        XCTAssertTrue(sdk.isInitialized)
        XCTAssertEqual(sdk.clientKey, "poltio_test_pk_12345")
    }
    
    func testConfigureWithEmptyKeyFails() {
        let sdk = PoltioSDK()
        sdk.configure(clientKey: "   ")
        
        XCTAssertFalse(sdk.isInitialized)
        XCTAssertNil(sdk.clientKey)
    }
    
    func testTrackEventWhenConfigured() {
        PoltioSDK.configure(clientKey: "poltio_test_pk_12345")
        
        // Should not throw or crash
        PoltioSDK.track(event: "ViewContent", params: ["url": "app://home"])
    }
    
    func testTrackEmptyEventNameSafelyHandles() {
        PoltioSDK.configure(clientKey: "poltio_test_pk_12345")
        
        // Empty or whitespace event names should be safely ignored
        PoltioSDK.track(event: "   ", params: ["url": "app://home"])
    }
    
    func testTrackEventWhenNotConfigured() {
        let unconfiguredSDK = PoltioSDK()
        
        // Calling track before configure should safely warn and not crash
        unconfiguredSDK.track(event: "ViewContent", params: ["url": "app://home"])
        XCTAssertFalse(unconfiguredSDK.isInitialized)
    }
}
