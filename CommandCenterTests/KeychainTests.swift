import XCTest
@testable import Command_Center

final class KeychainTests: XCTestCase {
    func testSetGetDelete() {
        let key = "test.\(UUID().uuidString)"
        Keychain.set("secret-123", for: key)
        XCTAssertEqual(Keychain.get(key), "secret-123", "status: \(Keychain.lastStatus)")
        Keychain.set("secret-456", for: key)
        XCTAssertEqual(Keychain.get(key), "secret-456")
        Keychain.set(nil, for: key)
        XCTAssertNil(Keychain.get(key))
    }
}
