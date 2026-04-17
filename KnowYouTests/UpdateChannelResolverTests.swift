import XCTest
@testable import KnowYou

final class UpdateChannelResolverTests: XCTestCase {
    func test_resolve_returnsDirectWhenBuildChannelIsDirect() {
        let resolver = UpdateChannelResolver(buildChannelOverride: "direct")

        XCTAssertEqual(resolver.resolve(), .direct)
    }

    func test_resolve_returnsAppStoreWhenBuildChannelIsAppStore() {
        let resolver = UpdateChannelResolver(buildChannelOverride: "app-store")

        XCTAssertEqual(resolver.resolve(), .appStore)
    }

    func test_resolve_returnsUnknownForUnsupportedValue() {
        let resolver = UpdateChannelResolver(buildChannelOverride: "beta-lab")

        XCTAssertEqual(resolver.resolve(), .unknown)
    }
}
