import XCTest
@testable import KnowYou

final class MyWikiSourceLibraryTests: XCTestCase {
    func testLoadSourcesMarksRawFilesWithWikiSummariesAsIndexed() throws {
        let root = try makeProjectRoot()
        try writeRawSource(root: root, name: "a.md")
        try writeRawSource(root: root, name: "b.md")
        try writeWikiSource(root: root, name: "a.md")

        let sources = try MyWikiSourceLibrary().loadSources(projectRoot: root)

        XCTAssertEqual(sources.map(\.fileName), ["a.md", "b.md"])
        XCTAssertEqual(sources.map(\.status), [.indexed, .pending])
        XCTAssertEqual(sources.first?.summaryURL?.lastPathComponent, "a.md")
    }

    func testImportFilesCopiesMarkdownAndTextFilesIntoRawSources() throws {
        let root = try makeProjectRoot()
        let sourceFolder = root.appending(path: "external", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let markdown = sourceFolder.appending(path: "meeting.md")
        let text = sourceFolder.appending(path: "note.txt")
        let ignored = sourceFolder.appending(path: "image.png")
        try "# Meeting".write(to: markdown, atomically: true, encoding: .utf8)
        try "Note".write(to: text, atomically: true, encoding: .utf8)
        try Data([0]).write(to: ignored)

        let result = try MyWikiSourceLibrary().importFiles([markdown, text, ignored], projectRoot: root)

        XCTAssertEqual(result.importedFileNames.sorted(), ["meeting.md", "note.txt"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "raw/sources/Manual Imports/meeting.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "raw/sources/Manual Imports/note.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "raw/sources/Manual Imports/image.png").path))
    }

    func testImportFilesAvoidsOverwritingExistingRawSources() throws {
        let root = try makeProjectRoot()
        try writeRawSource(root: root, name: "meeting.md", contents: "Existing")
        let external = root.appending(path: "meeting.md")
        try "New".write(to: external, atomically: true, encoding: .utf8)

        let result = try MyWikiSourceLibrary().importFiles([external], projectRoot: root)

        XCTAssertEqual(result.importedFileNames, ["meeting-2.md"])
        XCTAssertEqual(
            try String(contentsOf: root.appending(path: "raw/sources/Manual Imports/meeting.md"), encoding: .utf8),
            "Existing"
        )
        XCTAssertEqual(
            try String(contentsOf: root.appending(path: "raw/sources/Manual Imports/meeting-2.md"), encoding: .utf8),
            "New"
        )
    }

    func testImportFolderImportsSupportedFilesFromFolderOnly() throws {
        let root = try makeProjectRoot()
        let folder = root.appending(path: "folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "# One".write(to: folder.appending(path: "one.md"), atomically: true, encoding: .utf8)
        try "Two".write(to: folder.appending(path: "two.txt"), atomically: true, encoding: .utf8)

        let result = try MyWikiSourceLibrary().importFolder(folder, projectRoot: root)

        XCTAssertEqual(result.importedFileNames.sorted(), ["one.md", "two.txt"])
    }

    private func makeProjectRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeRawSource(root: URL, name: String, contents: String = "# Source") throws {
        let rawSources = root.appending(path: "raw/sources/Manual Imports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rawSources, withIntermediateDirectories: true)
        try contents.write(to: rawSources.appending(path: name), atomically: true, encoding: .utf8)
    }

    private func writeWikiSource(root: URL, name: String) throws {
        let wikiSources = root.appending(path: "wiki/sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: wikiSources, withIntermediateDirectories: true)
        try "# Indexed".write(to: wikiSources.appending(path: name), atomically: true, encoding: .utf8)
    }
}
