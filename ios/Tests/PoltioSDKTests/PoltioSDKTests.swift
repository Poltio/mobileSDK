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
        
        // Initial state
        XCTAssertNil(sdk.puid)
        
        // Identify with valid PUID
        PoltioSDK.identify(puid: "user_puid_98765")
        XCTAssertEqual(sdk.puid, "user_puid_98765")
        
        // Identify with whitespace trimmed
        PoltioSDK.identify(puid: "   user_puid_54321   ")
        XCTAssertEqual(sdk.puid, "user_puid_54321")
        
        // Identify with nil or empty clears PUID
        PoltioSDK.identify(puid: "")
        XCTAssertNil(sdk.puid)
        
        PoltioSDK.identify(puid: "user_puid_123")
        XCTAssertEqual(sdk.puid, "user_puid_123")
        
        PoltioSDK.identify(puid: nil)
        XCTAssertNil(sdk.puid)
    }
    
    func testTrackEventWhenConfigured() {
        PoltioSDK.configure(clientKey: "poltio_test_pk_12345")
        PoltioSDK.identify(puid: "user_test_123")
        
        // Should not throw or crash and attaches sdk_id and puid
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

