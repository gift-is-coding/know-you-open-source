import XCTest
@testable import KnowYou

final class UpdateServiceTests: XCTestCase {
    func test_versionComparison_treatsNewerPatchAsAvailable() {
        XCTAssertTrue(AppVersion("1.2.4") > AppVersion("1.2.3"))
    }

    func test_versionComparison_treatsSameVersionAsNotAvailable() {
        XCTAssertFalse(AppVersion("1.2.3") > AppVersion("1.2.3"))
    }

    func test_fetchOffer_returnsInstallInAppForDirectChannel() async throws {
        let session = URLSession.stubbedUpdateJSON(
            """
            {
              "version": "1.4.0",
              "summary": "Bug fixes and update pill",
              "downloadURL": "https://knowyou.example.com/download",
              "appStoreURL": "https://apps.apple.com/app/id123"
            }
            """
        )
        let service = UpdateService(
            session: session,
            resolver: UpdateChannelResolver(buildChannelOverride: "direct"),
            metadataURL: URL(string: "https://example.com/update.json")!,
            currentVersion: "1.3.0"
        )

        let offer = try await service.fetchOffer()

        XCTAssertEqual(offer?.actionKind, .installInApp)
        XCTAssertEqual(offer?.availableVersion, "1.4.0")
        XCTAssertEqual(offer?.downloadURL?.absoluteString, "https://knowyou.example.com/download")
    }

    func test_fetchOffer_returnsOpenAppStoreForAppStoreChannel() async throws {
        let session = URLSession.stubbedUpdateJSON(
            """
            {
              "version": "1.4.0",
              "summary": "Bug fixes and update pill",
              "downloadURL": "https://knowyou.example.com/download",
              "appStoreURL": "https://apps.apple.com/app/id123"
            }
            """
        )
        let service = UpdateService(
            session: session,
            resolver: UpdateChannelResolver(buildChannelOverride: "app-store"),
            metadataURL: URL(string: "https://example.com/update.json")!,
            currentVersion: "1.3.0"
        )

        let offer = try await service.fetchOffer()

        XCTAssertEqual(offer?.actionKind, .openAppStore)
    }

    func test_fetchOffer_returnsNilWhenRemoteVersionIsNotNewer() async throws {
        let session = URLSession.stubbedUpdateJSON(
            """
            {
              "version": "1.3.0",
              "summary": "Same version"
            }
            """
        )
        let service = UpdateService(
            session: session,
            resolver: UpdateChannelResolver(buildChannelOverride: "direct"),
            metadataURL: URL(string: "https://example.com/update.json")!,
            currentVersion: "1.3.0"
        )

        let offer = try await service.fetchOffer()

        XCTAssertNil(offer)
    }

    func test_fetchOffer_throwsForMalformedPayload() async {
        let session = URLSession.stubbedUpdateJSON("{\"bad\":true}")
        let service = UpdateService(
            session: session,
            resolver: UpdateChannelResolver(buildChannelOverride: "direct"),
            metadataURL: URL(string: "https://example.com/update.json")!,
            currentVersion: "1.3.0"
        )

        do {
            _ = try await service.fetchOffer()
            XCTFail("Expected fetchOffer to throw for malformed payload")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }
}

private final class UpdateServiceStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLSession {
    static func stubbedUpdateJSON(_ body: String) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateServiceStubURLProtocol.self]
        UpdateServiceStubURLProtocol.responseData = Data(body.utf8)
        return URLSession(configuration: configuration)
    }
}
