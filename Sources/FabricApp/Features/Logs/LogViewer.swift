import AppKit
import FabricCore
import SwiftUI

struct LogViewer: View {
    @Environment(\.dismiss) private var dismiss
    let presentation: LogPresentation

    @State private var selectedFileID: String
    @State private var content = "Loading log…"
    @State private var isLoading = false

    init(presentation: LogPresentation) {
        self.presentation = presentation
        _selectedFileID = State(initialValue: presentation.files[0].id)
    }

    private var selectedFile: LogFileReference {
        presentation.files.first { $0.id == selectedFileID } ?? presentation.files[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(presentation.service.instance.name) Logs")
                        .font(.headline)
                    Text(selectedFile.url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Picker("Log", selection: $selectedFileID) {
                    ForEach(presentation.files) { file in
                        Text(file.label).tag(file.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([selectedFile.url])
                } label: {
                    Label("Reveal", systemImage: "folder")
                }

                Button {
                    Task { await loadLog() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
            .padding(14)
            .background(.bar)

            Divider()

            ScrollView(.vertical) {
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            HStack {
                Text("Showing up to the final 1 MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 820, height: 520)
        .task { await loadLog() }
        .onChange(of: selectedFileID) { _, _ in
            Task { await loadLog() }
        }
    }

    private func loadLog() async {
        isLoading = true
        let url = selectedFile.url
        content = await Task.detached(priority: .utility) {
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }

                let end = try handle.seekToEnd()
                let maximumBytes: UInt64 = 1_024 * 1_024
                let offset = end > maximumBytes ? end - maximumBytes : 0
                try handle.seek(toOffset: offset)
                let data = try handle.readToEnd() ?? Data()
                let text = String(decoding: data, as: UTF8.self)
                return text.isEmpty ? "The log file is empty." : text
            } catch {
                return "Could not read the log file:\n\n\(error.localizedDescription)"
            }
        }.value
        isLoading = false
    }
}
