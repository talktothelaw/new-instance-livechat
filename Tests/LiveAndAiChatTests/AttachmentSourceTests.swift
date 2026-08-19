import XCTest
@testable import LiveAndAiChat

final class AttachmentSourceTests: XCTestCase {

    private let pngBase64 = Data((0..<64).map { UInt8($0) }).base64EncodedString()

    func testAutoDetectsEachStringSourceKind() {
        if case .dataUri = AttachmentSource.detect("data:image/png;base64,\(pngBase64)")! {} else { XCTFail("dataUri") }
        if case .filePath = AttachmentSource.detect("file:///tmp/receipt.pdf")! {} else { XCTFail("file url") }
        if case .filePath = AttachmentSource.detect("/tmp/receipt.pdf")! {} else { XCTFail("path") }
        if case .remoteUrl = AttachmentSource.detect("https://example.com/a.png")! {} else { XCTFail("url") }
        if case .base64 = AttachmentSource.detect(pngBase64)! {} else { XCTFail("base64") }
    }

    func testAutoRefusesGarbageAndEmpty() {
        XCTAssertNil(AttachmentSource.detect(""))
        XCTAssertNil(AttachmentSource.detect("   "))
        XCTAssertNil(AttachmentSource.detect("definitely not base64!!!"))
    }

    func testFromTypeNameMapsExplicitTypes() {
        if case .base64 = AttachmentSource.fromTypeName("base64", value: pngBase64)! {} else { XCTFail() }
        if case .filePath = AttachmentSource.fromTypeName("file", value: "/tmp/a.png")! {} else { XCTFail() }
        if case .remoteUrl = AttachmentSource.fromTypeName("url", value: "https://x.example/a.png")! {} else { XCTFail() }
        XCTAssertNil(AttachmentSource.fromTypeName("floppy", value: "whatever"))
    }

    func testBase64DecodingAcceptsBothAlphabetsAndRejectsInvalid() {
        let bytes = Data((0..<32).map { UInt8($0 * 7 % 256) })
        XCTAssertEqual(AttachmentSource.decodeBase64(bytes.base64EncodedString()), bytes)
        let urlSafe = bytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(AttachmentSource.decodeBase64(urlSafe), bytes)
        XCTAssertNil(AttachmentSource.decodeBase64("@@@nope@@@"))
        XCTAssertNil(AttachmentSource.decodeBase64(""))
    }

    func testDataUriParsing() {
        let parsed = AttachmentSourceResolver.parseDataUri("data:image/png;base64,\(pngBase64)")
        XCTAssertEqual(parsed?.mime, "image/png")
        XCTAssertEqual(parsed?.data.count, 64)
        XCTAssertNil(AttachmentSourceResolver.parseDataUri("data:image/png;base64"))
        XCTAssertNil(AttachmentSourceResolver.parseDataUri("data:image/png,plaintext"))
        XCTAssertNil(AttachmentSourceResolver.parseDataUri("https://example.com"))
    }

    func testMimeNormalizationAndExtensionMapping() {
        XCTAssertEqual(AttachmentSourceResolver.normalizeMime("image/jpg"), "image/jpeg")
        XCTAssertEqual(AttachmentSourceResolver.normalizeMime("IMAGE/PNG"), "image/png")
        XCTAssertNil(AttachmentSourceResolver.normalizeMime("  "))
        XCTAssertEqual(AttachmentSourceResolver.mimeFromName("receipt.PDF"), "application/pdf")
        XCTAssertEqual(AttachmentSourceResolver.mimeFromName("photo.jpg"), "image/jpeg")
        XCTAssertNil(AttachmentSourceResolver.mimeFromName("noextension"))
    }

    func testResolverValidatesBase64EndToEnd() async throws {
        let request = AttachmentRequest(
            source: .base64(pngBase64),
            name: "pixels.png",
            mimeType: "image/png"
        )
        let resolved = try await AttachmentSourceResolver.resolve(
            request: request, allowRemote: false,
            maxBytes: 25 * 1024 * 1024,
            allowedMime: ["image/png"]
        )
        XCTAssertEqual(resolved.data.count, 64)
        XCTAssertEqual(resolved.mimeType, "image/png")
    }

    func testResolverRejectsEmptyOversizedMismatchedAndRemote() async {
        func expectFailure(_ request: AttachmentRequest, allowRemote: Bool = false, allowedMime: Set<String> = ["image/png"], contains: String) async {
            do {
                _ = try await AttachmentSourceResolver.resolve(
                    request: request, allowRemote: allowRemote,
                    maxBytes: 100, allowedMime: allowedMime
                )
                XCTFail("expected failure: \(contains)")
            } catch let e as LiveAndAiChatError {
                XCTAssertTrue(e.message.contains(contains), "got: \(e.message)")
            } catch {
                XCTFail("unexpected error type")
            }
        }
        await expectFailure(.init(source: .bytes(Data()), name: "a.png", mimeType: "image/png"), contains: "empty")
        await expectFailure(.init(source: .bytes(Data(count: 200)), name: "a.png", mimeType: "image/png"), contains: "exceeds")
        await expectFailure(.init(source: .bytes(Data(count: 10)), name: "a.png", mimeType: "image/png", declaredSize: 99), contains: "mismatch")
        await expectFailure(.init(source: .bytes(Data(count: 10)), name: "a.pdf", mimeType: "application/pdf"), contains: "Unsupported")
        await expectFailure(.init(source: .remoteUrl("https://example.com/a.png"), name: "a.png", mimeType: "image/png"), contains: "disabled")
        await expectFailure(.init(source: .base64("@@@"), name: "a.png", mimeType: "image/png"), contains: "base64")
        await expectFailure(.init(source: .bytes(Data(count: 10)), name: "a.pdf", mimeType: "image/png"), allowedMime: ["image/png", "application/pdf"], contains: "does not match")
    }
}

final class CloseEmissionGuardTests: XCTestCase {

    func testClaimsExactlyOncePerArm() {
        let guardInstance = CloseEmissionGuard()
        XCTAssertFalse(guardInstance.tryClaim())
        guardInstance.arm()
        XCTAssertTrue(guardInstance.tryClaim())
        XCTAssertFalse(guardInstance.tryClaim())
        guardInstance.arm()
        XCTAssertTrue(guardInstance.tryClaim())
    }

    func testRearmingWhileArmedStaysSingleClaim() {
        let guardInstance = CloseEmissionGuard()
        guardInstance.arm()
        guardInstance.arm()
        XCTAssertTrue(guardInstance.tryClaim())
        XCTAssertFalse(guardInstance.tryClaim())
    }
}

final class ChatStoreDraftTests: XCTestCase {

    @MainActor
    func testDraftSurvivesUpdatesAndClearsOnReset() {
        let store = ChatStore()
        store.updateDraft("half-typed message")
        XCTAssertEqual(store.draftText, "half-typed message")
        store.reset()
        XCTAssertEqual(store.draftText, "")
    }
}
