import Foundation

public enum LogManagerError: Error, LocalizedError {
    case logFileNotFound(Date)

    public var errorDescription: String? {
        switch self {
        case .logFileNotFound(let date):
            return "Log file not found for date: \(date)"
        }
    }
}

public final class LogManager: @unchecked Sendable {
    public static let shared = LogManager()

    private let queue = DispatchQueue(label: "com.logkit.logmanager")
    private let fileManager: FileManager
    private let calendar: Calendar
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let consoleDateFormatter: ISO8601DateFormatter
    private let consoleWriter: @Sendable (String) -> Void

    public let storageDirectory: URL

    private var _minimumLevel: LogLevel
    private var _isConsoleOutputEnabled: Bool

    public var minimumLevel: LogLevel {
        get { queue.sync { _minimumLevel } }
        set { queue.sync { _minimumLevel = newValue } }
    }

    public var isConsoleOutputEnabled: Bool {
        get { queue.sync { _isConsoleOutputEnabled } }
        set { queue.sync { _isConsoleOutputEnabled = newValue } }
    }

    public init(
        storageDirectory: URL? = nil,
        minimumLevel: LogLevel = .debug,
        isConsoleOutputEnabled: Bool = false,
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        consoleWriter: @escaping @Sendable (String) -> Void = { line in
            Swift.print(line)
        }
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self._minimumLevel = minimumLevel
        self._isConsoleOutputEnabled = isConsoleOutputEnabled
        self.consoleWriter = consoleWriter

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.consoleDateFormatter = ISO8601DateFormatter()
        self.consoleDateFormatter.formatOptions = [.withInternetDateTime]

        if let storageDirectory {
            self.storageDirectory = storageDirectory
        } else {
            let baseDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
            self.storageDirectory = baseDirectory.appendingPathComponent("LogKitLogs", isDirectory: true)
        }

        queue.sync {
            try? fileManager.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
        }
    }

    public func log(
        _ message: String,
        level: LogLevel,
        source: String,
        metadata: [String: String] = [:],
        timestamp: Date = Date()
    ) throws {
        try queue.sync {
            guard level >= _minimumLevel else {
                return
            }

            let entry = LogEntry(
                timestamp: timestamp,
                level: level,
                source: source,
                message: message,
                metadata: metadata
            )

            let fileURL = logFileURL(for: timestamp)
            let data = try encoder.encode(entry)
            let lineData = data + Data([0x0A])

            if !fileManager.fileExists(atPath: fileURL.path) {
                fileManager.createFile(atPath: fileURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: fileURL)
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            handle.write(lineData)

            if _isConsoleOutputEnabled {
                consoleWriter(consoleLine(for: entry))
            }
        }
    }

    public func readEntries(for date: Date) throws -> [LogEntry] {
        try queue.sync {
            let fileURL = logFileURL(for: date)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return []
            }

            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else {
                return []
            }

            let lines = data.split(separator: 0x0A)
            return try lines.map { line in
                try decoder.decode(LogEntry.self, from: Data(line))
            }
        }
    }

    public func existingLogFiles() throws -> [URL] {
        try queue.sync {
            try existingLogFilesLocked()
        }
    }

    @discardableResult
    public func exportLogFile(for date: Date, to destinationDirectory: URL) throws -> URL {
        try queue.sync {
            let sourceFileURL = logFileURL(for: date)
            guard fileManager.fileExists(atPath: sourceFileURL.path) else {
                throw LogManagerError.logFileNotFound(date)
            }

            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            let destinationURL = destinationDirectory.appendingPathComponent(sourceFileURL.lastPathComponent)

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            try fileManager.copyItem(at: sourceFileURL, to: destinationURL)
            return destinationURL
        }
    }

    public func exportAllLogs(to destinationDirectory: URL) throws -> [URL] {
        try queue.sync {
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

            let sourceFiles = try existingLogFilesLocked()
            var exported: [URL] = []

            for sourceFileURL in sourceFiles {
                let destinationURL = destinationDirectory.appendingPathComponent(sourceFileURL.lastPathComponent)

                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }

                try fileManager.copyItem(at: sourceFileURL, to: destinationURL)
                exported.append(destinationURL)
            }

            return exported
        }
    }

    private func existingLogFilesLocked() throws -> [URL] {
        let items = try fileManager.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return items
            .filter { $0.pathExtension.lowercased() == "log" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func logFileURL(for date: Date) -> URL {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 0
        components.minute = 0
        components.second = 0

        let normalizedDate = calendar.date(from: components) ?? date
        let fileName = "\(dateKey(for: normalizedDate)).log"
        return storageDirectory.appendingPathComponent(fileName)
    }

    private func dateKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0

        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func consoleLine(for entry: LogEntry) -> String {
        let timestamp = consoleDateFormatter.string(from: entry.timestamp)
        let level = levelText(entry.level)
        let metadataText: String

        if entry.metadata.isEmpty {
            metadataText = ""
        } else {
            let pairs = entry.metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ",")
            metadataText = " | \(pairs)"
        }

        return "[\(timestamp)] [\(level)] [\(entry.source)] \(entry.message)\(metadataText)"
    }

    private func levelText(_ level: LogLevel) -> String {
        switch level {
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .warning:
            return "WARNING"
        case .error:
            return "ERROR"
        case .critical:
            return "CRITICAL"
        }
    }
}
