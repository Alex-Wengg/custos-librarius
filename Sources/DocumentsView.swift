import SwiftUI
import UniformTypeIdentifiers

struct DocumentsView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("\(appState.documents.count) documents")
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    appState.showAddDocumentSheet = true
                } label: {
                    Label("Add Documents", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Document list or drop zone
            if appState.documents.isEmpty {
                DropZone(isTargeted: $isDropTargeted) { urls in
                    addDocuments(urls)
                }
            } else {
                List(appState.documents, selection: $appState.selectedDocument) { doc in
                    DocumentRow(document: doc)
                        .contextMenu {
                            Button("Show in Finder") {
                                NSWorkspace.shared.selectFile(doc.path.path, inFileViewerRootedAtPath: "")
                            }
                            Divider()
                            Button("Remove", role: .destructive) {
                                removeDocument(doc)
                            }
                        }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Documents")
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    func addDocuments(_ urls: [URL]) {
        guard let project = appState.currentProject else { return }
        let docsDir = project.path.appendingPathComponent("documents")

        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ["pdf", "txt", "md", "epub"].contains(ext) else { continue }

            let dest = docsDir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.copyItem(at: url, to: dest)

            appState.documents.append(Document(name: url.lastPathComponent, path: dest))
        }
    }

    func removeDocument(_ doc: Document) {
        try? FileManager.default.removeItem(at: doc.path)
        appState.documents.removeAll { $0.id == doc.id }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        addDocuments([url])
                    }
                }
            }
        }
        return true
    }
}

struct DocumentRow: View {
    let document: Document

    var body: some View {
        HStack {
            Image(systemName: iconForExtension(document.path.pathExtension))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading) {
                Text(document.name)
                    .fontWeight(.medium)

                if let size = fileSize(document.path) {
                    Text(size)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    func iconForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "doc.fill"
        case "epub": return "book.fill"
        case "txt", "md": return "doc.text.fill"
        default: return "doc"
        }
    }

    func fileSize(_ url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return nil }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

struct DropZone: View {
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 48))
                .foregroundColor(isTargeted ? .accentColor : .secondary)

            Text("Drop PDF, EPUB, TXT, or MD files here")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("or click Add Documents above")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.5))
        )
        .padding()
    }
}

struct AddDocumentSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Documents")
                .font(.title2)
                .fontWeight(.bold)

            Text("Select PDF, EPUB, TXT, or Markdown files to add to your project.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Choose Files...") {
                    selectFiles()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(width: 400)
    }

    func selectFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.pdf, .plainText, .epub]

        if panel.runModal() == .OK {
            guard let project = appState.currentProject else { return }
            let docsDir = project.path.appendingPathComponent("documents")

            for url in panel.urls {
                let dest = docsDir.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: dest)
                appState.documents.append(Document(name: url.lastPathComponent, path: dest))
            }

            dismiss()
        }
    }
}
