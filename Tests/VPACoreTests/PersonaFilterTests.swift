import XCTest
import VPACore
import VPAResponse

final class PersonaFilterTests: XCTestCase {
    func testFailureResponseIsStable() {
        let filter = GLaDOSPersonaFilter()
        let response = Response(text: "That was... not useful audio. Try again.", type: .failure)
        XCTAssertEqual(filter.apply(to: response), "That was... not useful audio. Try again.")
    }
}
