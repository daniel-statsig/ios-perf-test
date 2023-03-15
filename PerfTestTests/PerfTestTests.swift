import XCTest

import Statsig

final class PerfTestTests: XCTestCase {
    func testFoo() throws {
        Statsig.start(sdkKey: "client-key")
    }
}
