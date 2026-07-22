//
//  MoneyMapDiagnostics.swift
//  MoneyMap
//
//  Created by Codex on 7/7/26.
//

import Foundation
import OSLog

enum MoneyMapDiagnostics {
    private static let logger = Logger(subsystem: "com.heyjoshsmith.MoneyMap", category: "Diagnostics")
    private static let queue = DispatchQueue(label: "com.heyjoshsmith.MoneyMap.diagnostics")
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func record(_ event: String, metadata: [String: String] = [:]) {
        let line = makeLine(event: event, metadata: metadata)
        logger.info("\(line, privacy: .public)")
        append(line)
    }

    static func record(_ event: String, error: Error, metadata: [String: String] = [:]) {
        var metadata = metadata
        metadata["error"] = error.localizedDescription
        let line = makeLine(event: event, metadata: metadata)
        logger.error("\(line, privacy: .public)")
        append(line)
    }

    @discardableResult
    static func measure<T>(_ event: String, metadata: [String: String] = [:], work: () throws -> T) rethrows -> T {
        let start = Date()
        record("\(event).begin", metadata: metadata)
        do {
            let value = try work()
            record("\(event).end", metadata: metadata.merging(["durationMs": durationMilliseconds(since: start)]) { _, new in new })
            return value
        } catch {
            record("\(event).failed", error: error, metadata: metadata.merging(["durationMs": durationMilliseconds(since: start)]) { _, new in new })
            throw error
        }
    }

    static func durationMilliseconds(since start: Date) -> String {
        String(Int(Date().timeIntervalSince(start) * 1_000))
    }

    private static func makeLine(event: String, metadata: [String: String]) -> String {
        var parts = [
            dateFormatter.string(from: Date()),
            event
        ]
        parts.append(contentsOf: metadata.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" })
        return parts.joined(separator: " | ")
    }

    private static func append(_ line: String) {
        queue.async {
            guard let url = diagnosticsFileURL() else { return }
            let data = Data((line + "\n").utf8)

            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: url, options: .atomic)
                }
            } catch {
                logger.error("diagnostics.write.failed \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func diagnosticsFileURL() -> URL? {
        let fileManager = FileManager.default
        let baseURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.heyjoshsmith.MoneyMap")
            ?? (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
        return baseURL?
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("MoneyMapRecurringDiagnostics.log")
    }
}
