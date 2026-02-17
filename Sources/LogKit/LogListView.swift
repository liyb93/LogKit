#if os(iOS)
import SwiftUI
import UIKit

public struct LogListView: View {
    @Environment(\.presentationMode) private var presentationMode

    private let manager: LogManager

    public init(manager: LogManager = .shared) {
        self.manager = manager
    }

    public var body: some View {
        NavigationView {
            List {
                Section(header: Text("Tools")) {
                    NavigationLink(destination: LogFilesPage(manager: manager)) {
                        Text("Logs")
                    }
                }
            }
            .listStyle(GroupedListStyle())
            .navigationBarTitle("Debug", displayMode: .inline)
            .navigationBarItems(leading: closeButton)
        }
    }

    private var closeButton: some View {
        Button(action: {
            presentationMode.wrappedValue.dismiss()
        }) {
            Image(systemName: "xmark")
        }
    }
}

private struct LogFilesPage: View {
    private let manager: LogManager

    @State private var logFiles: [URL] = []
    @State private var selectedFile: URL?
    @State private var content: String = ""
    @State private var lines: [String] = []
    @State private var query: String = ""
    @State private var isFilterMode: Bool = false
    @State private var matchLineIndices: [Int] = []
    @State private var currentMatchIndex: Int = 0
    @State private var errorText: String?

    init(manager: LogManager) {
        self.manager = manager
    }

    var body: some View {
        VStack(spacing: 0) {
            fileSelector
            controls
            Divider()
            contentView
        }
        .navigationBarTitle("Logs", displayMode: .inline)
        .navigationBarItems(trailing: Button(action: loadLogs) {
            Image(systemName: "arrow.clockwise")
        })
        .onAppear(perform: loadLogs)
    }

    private var fileSelector: some View {
        Group {
            if logFiles.isEmpty {
                Text("No log files")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(logFiles, id: \.self) { fileURL in
                            Button(action: { selectFile(fileURL) }) {
                                Text(fileURL.lastPathComponent)
                                    .font(.footnote)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(selectedFile == fileURL ? Color.accentColor.opacity(0.2) : Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .foregroundColor(.primary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField(isFilterMode ? "Filter" : "Search", text: queryBinding)
                .disableAutocorrection(true)
                .autocapitalization(.none)

            Text("\(matchLineIndices.isEmpty ? 0 : currentMatchIndex + 1)/\(matchLineIndices.count)")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: { moveMatch(-1) }) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(matchLineIndices.isEmpty)

            Button(action: { moveMatch(1) }) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(matchLineIndices.isEmpty)

            Button(action: {
                query = ""
                rebuildMatches()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(query.isEmpty)

            Toggle("Filter", isOn: filterBinding)
                .labelsHidden()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var contentView: some View {
        Group {
            if let errorText {
                Text(errorText)
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if logFiles.isEmpty {
                Text("No log files")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if displayedLines.isEmpty {
                Text(query.isEmpty ? "No log lines" : "No matching lines")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(displayedLines.indices, id: \.self) { index in
                            Text(displayedLines[index])
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(backgroundColor(for: index))
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var displayedLines: [String] {
        if query.isEmpty { return lines }
        if !isFilterMode { return lines }
        return lines.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { query },
            set: { newValue in
                query = newValue
                rebuildMatches()
            }
        )
    }

    private var filterBinding: Binding<Bool> {
        Binding(
            get: { isFilterMode },
            set: { newValue in
                isFilterMode = newValue
                rebuildMatches()
            }
        )
    }

    private func backgroundColor(for index: Int) -> Color {
        guard !query.isEmpty else { return Color.clear }
        guard let matchPosition = matchLineIndices.firstIndex(of: index) else { return Color.clear }

        if matchPosition == currentMatchIndex {
            return Color.orange.opacity(0.25)
        }
        return Color.yellow.opacity(0.18)
    }

    private func loadLogs() {
        do {
            logFiles = try manager
                .existingLogFiles()
                .sorted { $0.lastPathComponent > $1.lastPathComponent }

            errorText = nil

            guard !logFiles.isEmpty else {
                selectedFile = nil
                content = ""
                lines = []
                matchLineIndices = []
                return
            }

            if let selectedFile, logFiles.contains(selectedFile) {
                loadFile(selectedFile)
            } else if let latestFile = logFiles.first {
                selectFile(latestFile)
            }
        } catch {
            logFiles = []
            selectedFile = nil
            content = ""
            lines = []
            matchLineIndices = []
            errorText = "Failed to load log files: \(error.localizedDescription)"
        }
    }

    private func selectFile(_ fileURL: URL) {
        selectedFile = fileURL
        loadFile(fileURL)
    }

    private func loadFile(_ fileURL: URL) {
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
            lines = content.components(separatedBy: .newlines)
            errorText = nil
            rebuildMatches()
        } catch {
            content = ""
            lines = []
            matchLineIndices = []
            errorText = "Failed to read log file: \(error.localizedDescription)"
        }
    }

    private func rebuildMatches() {
        currentMatchIndex = 0

        guard !query.isEmpty else {
            matchLineIndices = []
            return
        }

        let sourceLines = displayedLines
        matchLineIndices = sourceLines.indices.filter { index in
            sourceLines[index].localizedCaseInsensitiveContains(query)
        }
    }

    private func moveMatch(_ delta: Int) {
        guard !matchLineIndices.isEmpty else { return }
        let total = matchLineIndices.count
        currentMatchIndex = (currentMatchIndex + delta + total) % total
    }
}
#endif
