import XCTest
@testable import KituraBot

class KituraBotTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssertEqual(KituraBot().text, "Hello, World!")
    }


    static var allTests : [(String, (KituraBotTests) -> () throws -> Void)] {
        return [
            ("testExample", testExample),
        ]
    }
}
