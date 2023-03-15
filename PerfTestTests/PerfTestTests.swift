import XCTest

@testable import Statsig

final class PerfTestTests: XCTestCase {
    let env = DeviceEnvironment()

    override func setUpWithError() throws {
        let expectation = XCTestExpectation(description: "Statsig Initialize")
        Statsig.start(sdkKey: "client-aGDsuuCYcisVAtySPNj1NFNRtnvsIlxHFo6rtshBbyo",
                      user: StatsigUser(userID: env.deviceModel)) { err in
            if let err = err {
                fatalError(err)
            }

            expectation.fulfill()
        }

        self.wait(for: [expectation], timeout: 5)
    }

    override func tearDownWithError() throws {
        let expectation = XCTestExpectation(description: "Statsig Shutdown")
        Statsig.shutdown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            expectation.fulfill()
        }
        self.wait(for: [expectation], timeout: 5)
    }

    func testGatePerformance() throws {
        let (best, worst, average, metadata) = profile {
            _ = Statsig.checkGate("test_public")
        }

        Statsig.logEvent("check_gate_worst", value: worst, metadata: metadata)
        Statsig.logEvent("check_gate_best", value: best, metadata: metadata)
        Statsig.logEvent("check_gate_average", value: average, metadata: metadata)
    }

    func testConfigPerformance() throws {
        let (best, worst, average, metadata) = profile {
            let config = Statsig.getConfig("a_config")
            _ = config.getValue(forKey: "foo", defaultValue: "err")
        }

        Statsig.logEvent("get_config_worst", value: worst, metadata: metadata)
        Statsig.logEvent("get_config_best", value: best, metadata: metadata)
        Statsig.logEvent("get_config_average", value: average, metadata: metadata)
    }

    func testExperimentPerformance() throws {
        let (best, worst, average, metadata) = profile {
            let experiment = Statsig.getExperiment("an_experiment")
            _ = experiment.getValue(forKey: "a_param", defaultValue: "err")
        }

        Statsig.logEvent("get_experiment_worst", value: worst, metadata: metadata)
        Statsig.logEvent("get_experiment_best", value: best, metadata: metadata)
        Statsig.logEvent("get_experiment_average", value: average, metadata: metadata)
    }

    func testLayerPerformance() throws {
        let (best, worst, average, metadata) = profile {
            let layer = Statsig.getLayer("a_layer")
            _ = layer.getValue(forKey: "a_param", defaultValue: "err")
        }

        Statsig.logEvent("get_layer_worst", value: worst, metadata: metadata)
        Statsig.logEvent("get_layer_best", value: best, metadata: metadata)
        Statsig.logEvent("get_layer_average", value: average, metadata: metadata)
    }

    private func profile(_ task: () -> Void) -> (Double, Double, Double, [String: String]) {
        let iterations = 1000
        var best = CGFLOAT_MAX
        var worst = 0.0
        var sum = 0.0
        var samples: [Double] = []

        for _ in 0...iterations {
            let start = CFAbsoluteTimeGetCurrent()
            task()
            let end = CFAbsoluteTimeGetCurrent()

            let duration = (end - start) * 1000.0

            worst = max(worst, duration)
            best = min(best, duration)
            sum += duration
            samples.append(duration)
        }

        let average = sum / Double(iterations)

        let meta: [String: String] = [
            "iterations": "\(iterations)",
            "samples": "\(samples.sorted().reversed()[0...10])"
        ]

        return (best, worst, average, meta)
    }
}
