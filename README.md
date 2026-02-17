# LogKit

一个支持 `iOS`、`macOS`、`watchOS` 的 Swift 日志管理库，支持日志分级、来源标记、按天切分落盘和日志导出。

## 特性

- 支持平台：iOS 13+、macOS 10.15+、watchOS 6+
- 支持日志级别：`debug`、`info`、`warning`、`error`、`critical`
- 每条日志支持 `source`（协议扩展自定义类型）和 `metadata`
- 日志文件按天存储（`yyyy-MM-dd.log`）
- 支持导出单天日志文件和全部日志文件
- 支持开关控制日志是否同步输出到控制台
- 支持 `config(...)` 一次性配置
- 支持快捷日志方法：`d/i/w/e/c`
- 支持 Swift Package Manager

## 安装

```swift
.package(url: "https://your.git.repo/LogKit.git", from: "1.0.0")
```

## 快速开始

```swift
import LogKit

let logger = LogManager.shared
logger.config(
    minimumLevel: .debug,
    isConsoleOutputEnabled: true
)

struct NetworkSource: LogSourceRepresentable {
    let module: String
    var logSource: String { "Network.\(module)" }
}

let source = NetworkSource(module: "Auth")

logger.log(
    "Network request finished",
    source: source,
    metadata: ["status": "200"]
)

logger.d("request start", source: source)
logger.i("request success", source: source)
logger.w("retry once", source: source)
logger.e("request failed", source: source)
logger.c("fatal", source: source)

let todayEntries = try logger.readEntries(for: Date())
print(todayEntries.count)
```

## 导出日志

```swift
let exportDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("exports", isDirectory: true)

let dailyFile = try logger.exportLogFile(for: Date(), to: exportDirectory)
let allFiles = try logger.exportAllLogs(to: exportDirectory)
```
