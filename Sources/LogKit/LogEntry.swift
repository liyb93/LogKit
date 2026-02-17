import Foundation

public struct LogEntry: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let level: LogLevel
    public let source: String
    public let message: String
    public let metadata: [String: String]

    public init(
        timestamp: Date = Date(),
        level: LogLevel,
        source: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.level = level
        self.source = source
        self.message = message
        self.metadata = metadata
    }
}
