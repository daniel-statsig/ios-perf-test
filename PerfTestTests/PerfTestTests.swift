import XCTest

import Statsig

final class PerfTestTests: XCTestCase {

    override func setUpWithError() throws {
        let expectation = XCTestExpectation(description: "Statsig Initialize")
        Statsig.start(sdkKey: "client-aGDsuuCYcisVAtySPNj1NFNRtnvsIlxHFo6rtshBbyo") { err in
            if let err = err {
                fatalError(err)
            }

            expectation.fulfill()
        }

        self.wait(for: [expectation], timeout: 5)
    }

    func testGatePerformance() throws {
        let iterations = 1000
        var best = CGFLOAT_MAX
        var worst = 0.0
        var sum = 0.0

        for _ in 0...iterations {
            let start = CFAbsoluteTimeGetCurrent()
            _ = Statsig.checkGate("test_public")
            let end = CFAbsoluteTimeGetCurrent()

            let duration = (end - start) * 1000.0

            worst = max(worst, duration)
            best = min(best, duration)
            sum += duration
        }

        let average = sum / Double(iterations)

        XCTAssertLessThan(worst, 1)
        XCTAssertLessThan(best, 0.1)
        XCTAssertLessThan(average, 0.5)
    }
}
