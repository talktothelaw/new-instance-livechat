import XCTest
@testable import LiveAndAiChat

final class HeaderGradientTests: XCTestCase {

    private let vectors: [(base: String, glow: String, deep: String)] = [
        ("#5b54a0", "#8882dd", "#372e72"),
        ("#9333ea", "#b584f6", "#60179e"),
        ("#ffd84d", "#fef8e5", "#b59617"),
        ("#0f766e", "#40a89e", "#0c4944"),
        ("#d9480f", "#fd8560", "#8d3111"),
        ("#111111", "#3a3a3a", "#0c0c0c"),
        ("#ffffff", "#ffffff", "#e8e8e8"),
        ("#000000", "#141414", "#000000"),
        ("#2563eb", "#6e9cf6", "#0739a8"),
    ]

    func testEveryVectorWithinOneUnitPerChannel() throws {
        for vector in vectors {
            let stops = HeaderGradient.stops(hex: vector.base)
            assertClose(stops.glow, vector.glow, "glow of \(vector.base)")
            assertClose(stops.deep, vector.deep, "deep of \(vector.base)")
        }
    }

    func testNonSixDigitInputIsFlat() {
        for input in ["#fff", "9333ea", "#ff9333ea", "purple", ""] {
            let stops = HeaderGradient.stops(hex: input)
            XCTAssertEqual(stops.glow, input)
            XCTAssertEqual(stops.deep, input)
        }
    }

    func testMixWeightsTheFirstColor() {
        let mixed = RGB.mix(RGB(r: 255, g: 0, b: 100), RGB(r: 0, g: 255, b: 200), 0.2)
        XCTAssertEqual(mixed, RGB(r: 51, g: 204, b: 180))
    }

    private func assertClose(_ actual: String, _ expected: String, _ label: String) {
        guard let a = RGB(hex: actual), let e = RGB(hex: expected) else {
            return XCTFail("\(label): unparsable \(actual) or \(expected)")
        }
        XCTAssertLessThanOrEqual(abs(a.r - e.r), 1, "\(label): \(actual) vs \(expected)")
        XCTAssertLessThanOrEqual(abs(a.g - e.g), 1, "\(label): \(actual) vs \(expected)")
        XCTAssertLessThanOrEqual(abs(a.b - e.b), 1, "\(label): \(actual) vs \(expected)")
    }
}

final class WaitingCopyTests: XCTestCase {

    func testDetailShowsQueueAndWholeMinutes() {
        XCTAssertEqual(WaitingCopy.detail(queuePosition: 2, estimatedWaitSeconds: 600), "Position in queue: 2 · Estimated wait: 10 min")
        XCTAssertEqual(WaitingCopy.detail(queuePosition: nil, estimatedWaitSeconds: 61), "Estimated wait: 2 min")
        XCTAssertEqual(WaitingCopy.detail(queuePosition: nil, estimatedWaitSeconds: 0), "Estimated wait: 1 min")
        XCTAssertEqual(WaitingCopy.detail(queuePosition: 3, estimatedWaitSeconds: nil), "Position in queue: 3")
    }

    func testDetailIsAbsentWithoutData() {
        XCTAssertNil(WaitingCopy.detail(queuePosition: nil, estimatedWaitSeconds: nil))
        XCTAssertNil(WaitingCopy.detail(queuePosition: 0, estimatedWaitSeconds: nil))
    }
}
