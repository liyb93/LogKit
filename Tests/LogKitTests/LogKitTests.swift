import XCTest
@testable import LogKit

final class LogKitTests: XCTestCase {
    private final class OutputRecorder: @unchecked Sendable {
        var lines: [String] = []
    }

    private func makeLogManager() throws -> (LogManager, URL) {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let manager = LogManager(storageDirectory: baseURL)
        return (manager, baseURL)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 10) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = 0
        comps.second = 0

        return Calendar.current.date(from: comps)!
    }

    func testLogContainsLevelAndSourceAndMetadata() throws {
        let (manager, _) = try makeLogManager()
        let date = makeDate(year: 2026, month: 2, day: 10)

        try manager.log(
            "app started",
            level: .info,
            source: "AppLifecycle",
            metadata: ["scene": "main"],
            timestamp: date
        )

        let entries = try manager.readEntries(for: date)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.level, .info)
        XCTAssertEqual(entries.first?.source, "AppLifecycle")
        XCTAssertEqual(entries.first?.metadata["scene"], "main")
    }

    func testLogsAreSplitByDay() throws {
        let (manager, _) = try makeLogManager()
        let day1 = makeDate(year: 2026, month: 2, day: 11)
        let day2 = makeDate(year: 2026, month: 2, day: 12)

        try manager.log("d1", level: .debug, source: "UnitTest", timestamp: day1)
        try manager.log("d2", level: .debug, source: "UnitTest", timestamp: day2)

        let files = try manager.existingLogFiles()
        XCTAssertEqual(files.count, 2)

        let entriesDay1 = try manager.readEntries(for: day1)
        let entriesDay2 = try manager.readEntries(for: day2)
        XCTAssertEqual(entriesDay1.map(\.message), ["d1"])
        XCTAssertEqual(entriesDay2.map(\.message), ["d2"])
    }

    func testMinimumLevelFilter() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let manager = LogManager(storageDirectory: baseURL, minimumLevel: .warning)
        let date = makeDate(year: 2026, month: 2, day: 13)

        try manager.log("ignore", level: .info, source: "UnitTest", timestamp: date)
        try manager.log("store", level: .error, source: "UnitTest", timestamp: date)

        let entries = try manager.readEntries(for: date)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.message, "store")
    }

    func testExportDailyAndAllLogs() throws {
        let (manager, _) = try makeLogManager()
        let day1 = makeDate(year: 2026, month: 2, day: 14)
        let day2 = makeDate(year: 2026, month: 2, day: 15)

        try manager.log("a", level: .info, source: "UnitTest", timestamp: day1)
        try manager.log("b", level: .info, source: "UnitTest", timestamp: day2)

        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let single = try manager.exportLogFile(for: day1, to: exportDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: single.path))

        let all = try manager.exportAllLogs(to: exportDir)
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testSharedIsSingleton() {
        let first = LogManager.shared
        let second = LogManager.shared
        XCTAssertTrue(first === second)
    }

    func testConsoleOutputToggle() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let recorder = OutputRecorder()
        let manager = LogManager(
            storageDirectory: baseURL,
            isConsoleOutputEnabled: false,
            consoleWriter: { line in
                recorder.lines.append(line)
            }
        )

        let date = makeDate(year: 2026, month: 2, day: 16)

        try manager.log("hidden", level: .info, source: "UnitTest", timestamp: date)
        XCTAssertTrue(recorder.lines.isEmpty)

        manager.isConsoleOutputEnabled = true
        try manager.log("visible", level: .warning, source: "UnitTest", metadata: ["k": "v"], timestamp: date)

        XCTAssertEqual(recorder.lines.count, 1)
        XCTAssertTrue(recorder.lines[0].contains("visible"))
        XCTAssertTrue(recorder.lines[0].contains("[WARNING]"))
        XCTAssertTrue(recorder.lines[0].contains("[UnitTest]"))
        XCTAssertTrue(recorder.lines[0].contains("k=v"))
    }
}
