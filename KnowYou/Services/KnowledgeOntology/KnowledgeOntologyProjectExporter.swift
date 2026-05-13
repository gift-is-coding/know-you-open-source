import Foundation

struct KnowledgeOntologySyncResult: Equatable {
    let projectRoot: URL
    let exportedFileNames: [String]
}

struct KnowledgeOntologyProjectExporter {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func syncDiaries(sourceVault: URL, projectRoot: URL) throws -> KnowledgeOntologySyncResult {
        let result = try MyWikiProjectExporter(fileManager: fileManager).syncDiaries(
            sourceVault: sourceVault,
            projectRoot: projectRoot
        )
        return KnowledgeOntologySyncResult(
            projectRoot: result.projectRoot,
            exportedFileNames: result.exportedFileNames
        )
    }

    func ensureProject(at projectRoot: URL) throws {
        try MyWikiProjectExporter(fileManager: fileManager).ensureProject(at: projectRoot)
    }
}
