import Foundation

public protocol LogSourceRepresentable: Sendable {
    var logSource: String { get }
}

extension String: LogSourceRepresentable {
    public var logSource: String {
        self
    }
}
