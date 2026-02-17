#if os(macOS)
import AppKit
import SwiftUI

public struct MacLogListView: View {
    private let manager: LogManager

    @State private var logFiles: [URL] = []
    @State private var selectedFile: URL?
    @State private var logContent: String = ""
    @State private var displayedString: String = ""
    @State private var searchText: String = ""
    @State private var isFilterMode: Bool = false
    @State private var currentMatchIndex: Int = 0
    @State private var matches: [NSRange] = []
    @State private var errorText: String?

    public init(manager: LogManager = .shared) {
        self.manager = manager
    }

    public var body: some View {
        HStack(spacing: 0) {
            fileListPanel
            Divider()
            contentPanel
        }
        .onAppear(perform: loadLogFiles)
    }

    private var fileListPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Logs")
                .font(.headline)
                .padding(12)

            Divider()

            List(logFiles, id: \.self) { file in
                Button(action: { selectFile(file) }) {
                    LogFileRow(file: file, isSelected: selectedFile == file)
                }
                .buttonStyle(PlainButtonStyle())
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            .listStyle(SidebarListStyle())
        }
        .frame(width: 240)
    }

    private var contentPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selectedFile {
                headerView(for: selectedFile)
                Divider()
                searchBar
                Divider()
                LogTextView(text: displayedString, matches: matches, currentMatchIndex: currentMatchIndex)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText {
                Text(errorText)
                    .foregroundColor(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: 8) {
                    Text("Select a log file")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func headerView(for file: URL) -> some View {
        HStack(spacing: 10) {
            Text(file.lastPathComponent)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            Button(action: { loadLogContent(from: file) }) {
                Text("Refresh")
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: { NSWorkspace.shared.activateFileViewerSelecting([file]) }) {
                Text("Reveal")
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Text("Search:")
                .foregroundColor(.secondary)

            TextField("Search logs", text: searchTextBinding, onCommit: nextMatch)

            if !searchText.isEmpty {
                Text("\(matches.isEmpty ? 0 : currentMatchIndex + 1)/\(matches.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: prevMatch) {
                    Text("Prev")
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(matches.isEmpty)

                Button(action: nextMatch) {
                    Text("Next")
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(matches.isEmpty)

                Button(action: {
                    searchText = ""
                    updateMatches()
                }) {
                    Text("Clear")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Divider()
                .frame(height: 16)

            Toggle("Filter", isOn: filterModeBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { searchText },
            set: { newValue in
                searchText = newValue
                updateMatches()
            }
        )
    }

    private var filterModeBinding: Binding<Bool> {
        Binding(
            get: { isFilterMode },
            set: { newValue in
                isFilterMode = newValue
                updateMatches()
            }
        )
    }

    private func loadLogFiles() {
        do {
            logFiles = try manager
                .existingLogFiles()
                .sorted { $0.lastPathComponent > $1.lastPathComponent }

            errorText = nil

            guard !logFiles.isEmpty else {
                selectedFile = nil
                logContent = ""
                displayedString = ""
                matches = []
                return
            }

            if let selectedFile, logFiles.contains(selectedFile) {
                loadLogContent(from: selectedFile)
            } else if let latestFile = logFiles.first {
                selectFile(latestFile)
            }
        } catch {
            selectedFile = nil
            logFiles = []
            logContent = ""
            displayedString = ""
            matches = []
            errorText = "Failed to load log files: \(error.localizedDescription)"
        }
    }

    private func selectFile(_ file: URL) {
        selectedFile = file
        loadLogContent(from: file)
    }

    private func loadLogContent(from file: URL) {
        do {
            logContent = try String(contentsOf: file, encoding: .utf8)
            errorText = nil
            updateMatches()
        } catch {
            logContent = ""
            displayedString = ""
            matches = []
            errorText = "Failed to read log file: \(error.localizedDescription)"
        }
    }

    private func updateMatches() {
        if isFilterMode, !searchText.isEmpty {
            let lines = logContent.components(separatedBy: .newlines)
            displayedString = lines
                .filter { $0.localizedCaseInsensitiveContains(searchText) }
                .joined(separator: "\n")
        } else {
            displayedString = logContent
        }

        guard !searchText.isEmpty else {
            matches = []
            currentMatchIndex = 0
            return
        }

        let nsText = displayedString as NSString
        var searchRange = NSRange(location: 0, length: nsText.length)
        var foundMatches: [NSRange] = []

        while searchRange.location < nsText.length {
            searchRange.length = nsText.length - searchRange.location
            let found = nsText.range(of: searchText, options: .caseInsensitive, range: searchRange)
            if found.location == NSNotFound {
                break
            }

            foundMatches.append(found)
            searchRange.location = found.location + found.length
        }

        matches = foundMatches
        currentMatchIndex = 0
    }

    private func nextMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
    }

    private func prevMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
    }
}

private struct LogTextView: NSViewRepresentable {
    let text: String
    let matches: [NSRange]
    let currentMatchIndex: Int

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        guard let textStorage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.setAttributes(
            [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ],
            range: fullRange
        )

        guard !matches.isEmpty else { return }

        for range in matches where NSMaxRange(range) <= textStorage.length {
            textStorage.addAttribute(
                .backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.25),
                range: range
            )
        }

        if currentMatchIndex < matches.count {
            let current = matches[currentMatchIndex]
            if NSMaxRange(current) <= textStorage.length {
                textStorage.addAttribute(
                    .backgroundColor,
                    value: NSColor.systemOrange.withAlphaComponent(0.5),
                    range: current
                )
                textView.scrollRangeToVisible(current)
            }
        }
    }
}

private struct LogFileRow: View {
    let file: URL
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(file.lastPathComponent)
                .lineLimit(1)
                .foregroundColor(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}
#endif
