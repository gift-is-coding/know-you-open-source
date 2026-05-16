import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MyWikiSourceLibraryView: View {
    let projectRoot: URL
    var onDidChange: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var sources: [MyWikiSourceItem] = []
    @State private var statusMessage = "Sources are copied into My Wiki before indexing."
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            dropTarget
            sourceList
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 520)
        .background(Color.black)
        .foregroundStyle(.white)
        .onAppear(perform: reload)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Source Library")
                        .font(.system(size: 26, weight: .semibold))
                    Text(statusMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 10) {
                Button {
                    chooseFolder()
                } label: {
                    Label("Choose Folder", systemImage: "folder")
                }

                Button {
                    chooseFiles()
                } label: {
                    Label("Import Files", systemImage: "doc.badge.plus")
                }

                Spacer()

                Text("\(sources.count) sources")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
    }

    private var dropTarget: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 24, weight: .semibold))
            Text("Drop Markdown or text files here")
                .font(.system(size: 14, weight: .semibold))
            Text("Imported files become pending sources until the next My Wiki run.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDropTargeted ? Color.blue.opacity(0.18) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isDropTargeted ? Color.blue.opacity(0.7) : Color.white.opacity(0.12),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                )
        )
        .dropDestination(for: URL.self) { urls, _ in
            importFiles(urls)
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
    }

    private var sourceList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(sources) { source in
                    HStack(spacing: 10) {
                        Image(systemName: source.status == .indexed ? "checkmark.circle.fill" : "clock")
                            .foregroundStyle(color(for: source.status))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.fileName)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Text(source.status.rawValue)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.48))
                        }
                        Spacer()
                        if let summaryURL = source.summaryURL {
                            Button("Open") {
                                NSWorkspace.shared.open(summaryURL)
                            }
                            .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.045))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        if panel.runModal() == .OK, let folder = panel.url {
            do {
                let result = try MyWikiSourceLibrary().importFolder(folder, projectRoot: projectRoot)
                didImport(result)
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.allowedSourceContentTypes
        panel.prompt = "Import"
        if panel.runModal() == .OK {
            importFiles(panel.urls)
        }
    }

    private func importFiles(_ urls: [URL]) {
        do {
            let result = try MyWikiSourceLibrary().importFiles(urls, projectRoot: projectRoot)
            didImport(result)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func didImport(_ result: MyWikiSourceImportResult) {
        if result.importedFileNames.isEmpty {
            statusMessage = "No supported Markdown or text files were imported."
        } else {
            statusMessage = "Imported \(result.importedFileNames.count) source file(s). Run My Wiki to index them."
        }
        reload()
        onDidChange()
    }

    private func reload() {
        do {
            sources = try MyWikiSourceLibrary().loadSources(projectRoot: projectRoot)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func color(for status: MyWikiSourceStatus) -> Color {
        switch status {
        case .indexed:
            return .green
        case .processing:
            return .blue
        case .failed, .needsReview:
            return .orange
        case .pending:
            return .white.opacity(0.42)
        }
    }

    private static var allowedSourceContentTypes: [UTType] {
        [
            .plainText,
            .text,
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown")
        ].compactMap { $0 }
    }
}
