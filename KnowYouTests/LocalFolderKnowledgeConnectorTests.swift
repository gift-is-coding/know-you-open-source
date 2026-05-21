import XCTest
@testable import KnowYou

final class LocalFolderKnowledgeConnectorTests: XCTestCase {
    func testFetchSnapshotsImportsSupportedFilesRecursivelySkippingHiddenAndUnsupportedInRemoteIDOrder() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let alphaDate = Date(timeIntervalSince1970: 1_778_200_100)
        let betaDate = Date(timeIntervalSince1970: 1_778_200_200)
        let zetaDate = Date(timeIntervalSince1970: 1_778_200_300)
        let alphaURL = try writeFile("Alpha text", at: "alpha.txt", in: root, modifiedAt: alphaDate)
        let betaURL = try writeFile("# Beta", at: "notes/beta.markdown", in: root, modifiedAt: betaDate)
        let zetaURL = try writeFile("# Zeta", at: "zeta.md", in: root, modifiedAt: zetaDate)
        _ = try writeFile("# Hidden", at: ".hidden.md", in: root)
        _ = try writeFile("# Hidden directory", at: ".obsidian/config.md", in: root)
        _ = try writeFile("{}", at: "notes/metadata.json", in: root)

        let connector = LocalFolderKnowledgeConnector(
            connectorInstanceID: "local-main",
            rootURL: root
        )

        let snapshots = try await connector.fetchSnapshots()

        XCTAssertEqual(snapshots.map(\.remoteID), ["alpha.txt", "notes/beta.markdown", "zeta.md"])
        XCTAssertTrue(snapshots.allSatisfy { $0.connectorInstanceID == "local-main" })
        XCTAssertTrue(snapshots.allSatisfy { $0.connectorID == .localFolderImport })
        XCTAssertTrue(snapshots.allSatisfy { $0.originKind == "local-file" })

        let alpha = try XCTUnwrap(snapshots.first { $0.remoteID == "alpha.txt" })
        XCTAssertEqual(alpha.title, "alpha")
        XCTAssertEqual(alpha.sourcePath, alphaURL.path)
        XCTAssertEqual(alpha.remoteURL, nil)
        XCTAssertEqual(alpha.mimeType, "text/plain")
        XCTAssertEqual(alpha.contentMarkdown, "Alpha text")
        XCTAssertEqual(alpha.remoteUpdatedAt, alphaDate)

        let beta = try XCTUnwrap(snapshots.first { $0.remoteID == "notes/beta.markdown" })
        XCTAssertEqual(beta.title, "beta")
        XCTAssertEqual(beta.sourcePath, betaURL.path)
        XCTAssertEqual(beta.mimeType, "text/markdown")
        XCTAssertEqual(beta.contentMarkdown, "# Beta")
        XCTAssertEqual(beta.remoteUpdatedAt, betaDate)

        let zeta = try XCTUnwrap(snapshots.first { $0.remoteID == "zeta.md" })
        XCTAssertEqual(zeta.sourcePath, zetaURL.path)
        XCTAssertEqual(zeta.mimeType, "text/markdown")
        XCTAssertEqual(zeta.remoteUpdatedAt, zetaDate)
    }

    func testFetchSnapshotsThrowsUnavailableWhenRootCannotBeEnumerated() async throws {
        let root = try makeTemporaryDirectory()
        try FileManager.default.removeItem(at: root)
        let connector = LocalFolderKnowledgeConnector(
            connectorInstanceID: "missing-local",
            rootURL: root
        )

        do {
            _ = try await connector.fetchSnapshots()
            XCTFail("Expected fetchSnapshots to throw")
        } catch let error as KnowledgeImportConnectorError {
            guard case .unavailable = error else {
                return XCTFail("Expected unavailable error, got \(error)")
            }
        }
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "KnowYouTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@discardableResult
private func writeFile(
    _ contents: String,
    at relativePath: String,
    in root: URL,
    modifiedAt: Date = Date(timeIntervalSince1970: 1_778_200_000)
) throws -> URL {
    let url = relativePath
        .split(separator: "/")
        .reduce(root) { $0.appending(path: String($1)) }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
    return url
}
