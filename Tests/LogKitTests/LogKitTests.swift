import XCTest
@testable import LogKit

final class LogKitTests: XCTestCase {
    private final class OutputRecorder: @unchecked Sendable {
        var lines: [String] = []
    }

    private struct FeatureSource: LogSourceRepresentable {
        let feature: String

        var logSource: String {
            "Feature.\(feature)"
        }
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

        manager.log(
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

        manager.log("d1", level: .debug, source: "UnitTest", timestamp: day1)
        manager.log("d2", level: .debug, source: "UnitTest", timestamp: day2)

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

        manager.log("ignore", level: .info, source: "UnitTest", timestamp: date)
        manager.log("store", level: .error, source: "UnitTest", timestamp: date)

        let entries = try manager.readEntries(for: date)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.message, "store")
    }

    func testExportDailyAndAllLogs() throws {
        let (manager, _) = try makeLogManager()
        let day1 = makeDate(year: 2026, month: 2, day: 14)
        let day2 = makeDate(year: 2026, month: 2, day: 15)

        manager.log("a", level: .info, source: "UnitTest", timestamp: day1)
        manager.log("b", level: .info, source: "UnitTest", timestamp: day2)

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

        manager.log("hidden", level: .info, source: "UnitTest", timestamp: date)
        XCTAssertTrue(recorder.lines.isEmpty)

        manager.isConsoleOutputEnabled = true
        manager.log("visible", level: .warning, source: "UnitTest", metadata: ["k": "v"], timestamp: date)

        XCTAssertEqual(recorder.lines.count, 1)
        XCTAssertTrue(recorder.lines[0].contains("visible"))
        XCTAssertTrue(recorder.lines[0].contains("[WARNING]"))
        XCTAssertTrue(recorder.lines[0].contains("[UnitTest]"))
        XCTAssertTrue(recorder.lines[0].contains("k=v"))
    }

    func testConfigMethodSetsPropertiesInOneCall() throws {
        let (manager, _) = try makeLogManager()

        manager.config(minimumLevel: .error, isConsoleOutputEnabled: true)

        XCTAssertEqual(manager.minimumLevel, .error)
        XCTAssertTrue(manager.isConsoleOutputEnabled)
    }

    func testDefaultLevelIsInfoWhenNotSpecified() throws {
        let (manager, _) = try makeLogManager()
        let date = makeDate(year: 2026, month: 2, day: 17)

        manager.log("default-info", source: "UnitTest", timestamp: date)

        let entries = try manager.readEntries(for: date)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.level, .info)
    }

    func testCustomSourceTypeAndShortcutMethods() throws {
        let (manager, _) = try makeLogManager()
        let date = makeDate(year: 2026, month: 2, day: 18)
        let source = FeatureSource(feature: "Login")

        manager.d("debug", source: source, timestamp: date)
        manager.i("info", source: source, timestamp: date)
        manager.w("warn", source: source, timestamp: date)
        manager.e("error", source: source, timestamp: date)
        manager.c("critical", source: source, timestamp: date)

        let entries = try manager.readEntries(for: date)
        XCTAssertEqual(entries.map(\.level), [.debug, .info, .warning, .error, .critical])
        XCTAssertTrue(entries.allSatisfy { $0.source == "Feature.Login" })
    }
}
