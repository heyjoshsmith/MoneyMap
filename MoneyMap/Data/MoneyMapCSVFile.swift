import Combine
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Owns a copy of a provider's short-lived file until the receiving review closes.
final class MoneyMapCSVFile: Transferable, Sendable {
    let url: URL
    private let directory: URL

    private init(url: URL, directory: URL) {
        self.url = url
        self.directory = directory
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .commaSeparatedText) { received in
            try stage(received.file)
        }
    }

    static func stage(_ source: URL) throws -> MoneyMapCSVFile {
        guard source.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoneyMapCSVDrops", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = source.pathExtension.lowercased() == "csv"
            ? source.lastPathComponent : source.lastPathComponent + ".csv"
        let destination = directory.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return MoneyMapCSVFile(url: destination, directory: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Scene-owned presentation state. Accepting a drop never imports transactions.
@MainActor
final class MoneyMapCSVReview: ObservableObject {
    @Published private(set) var urls: [URL] = []
    @Published var isPresented = false
    private var files: [MoneyMapCSVFile] = []

    var canAccept: Bool { !isPresented && urls.isEmpty }

    @discardableResult
    func accept(_ files: [MoneyMapCSVFile]) -> Bool {
        guard canAccept, !files.isEmpty else { return false }
        self.files = files
        urls = files.map(\.url)
        isPresented = true
        return true
    }

    @discardableResult
    func accept(url: URL) -> Bool {
        guard canAccept else { return false }
        urls = [url]
        isPresented = true
        return true
    }

    func didDismiss() {
        isPresented = false
        urls = []
        files = []
    }
}
