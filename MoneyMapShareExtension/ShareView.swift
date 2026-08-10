//
//  ShareView.swift
//  MoneyMapShareExtension
//
//  Created by Josh Smith on 4/30/25.
//

import SwiftUI
import UniformTypeIdentifiers
import SwiftData
import MoneyMapShared
import UIKit

private enum ShareDesign {
    static var groupedBackground: Color { MoneyMapSharedDesign.groupedBackground }
    static var surfaceBackground: Color { MoneyMapSharedDesign.surfaceBackground }
    static var controlBackground: Color { MoneyMapSharedDesign.controlBackground }
    static var accent: Color { MoneyMapSharedDesign.calmGreen }
    static var attention: Color { MoneyMapSharedDesign.attentionRed }
    static var separator: Color { MoneyMapSharedDesign.separator }
    static let cornerRadius = MoneyMapSharedDesign.cornerRadius
    static let controlCornerRadius = MoneyMapSharedDesign.controlCornerRadius
}

struct ShareView: View {
    // 1️⃣ Receive the context from the parent controller
    let context: NSExtensionContext

    @Environment(\.modelContext) private var modelContext
    @State private var existingGoals: [Goal] = []
    @State private var targetAmount: Double?
    @State private var selectedGoal: Goal?
    @State private var pageURL: URL?
    @State private var nameText = ""
    @State private var selectedDeadline = Date()
    @State private var priorityWeight: Double = 1.0
    @State private var previewImage: UIImage?
    @State private var allImageURLs: [URL] = []
    @State private var allImages: [UIImage] = []
    @State private var selectedImage: UIImage?
    @State private var pageTitle: String?

    @State private var csvURLs: [URL] = []
    @State private var isResolvingSharedContent = true
    @State private var didStartResolvingSharedContent = false
    @State private var sharedContentErrorMessage: String?
    
    var body: some View {
        Group {
            if isResolvingSharedContent {
                NavigationStack {
                    sharedContentLoadingView
                }
            } else if !csvURLs.isEmpty {
                TransactionCSVImportGuideView(
                    csvURLs: csvURLs,
                    onFinished: { _ in
                        context.completeRequest(returningItems: nil, completionHandler: nil)
                    },
                    onCancel: {
                        context.cancelRequest(withError: NSError(domain: "UserCancelled", code: 0))
                    }
                )
            } else {
                NavigationStack {
                    urlImporter
                }
            }
        }
        .tint(ShareDesign.accent)
        .onAppear {
            startResolvingSharedContent()
        }
    }

    private var sharedContentLoadingView: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reading shared item")
                            .font(.headline)
                        Text("MoneyMap is checking for an Apple Card CSV.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listRowBackground(ShareDesign.surfaceBackground)

            if let sharedContentErrorMessage {
                Section {
                    Label(sharedContentErrorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(ShareDesign.attention)
                }
                .listRowBackground(ShareDesign.surfaceBackground)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ShareDesign.groupedBackground)
        .navigationTitle("Import")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    context.cancelRequest(withError: NSError(domain: "UserCancelled", code: 0))
                }
            }
        }
    }

    private func startResolvingSharedContent() {
        guard !didStartResolvingSharedContent else { return }
        didStartResolvingSharedContent = true

        loadURL()
        fetchModels()
        loadCSVURLs()
    }

    var csvImporter: some View {
        TransactionCSVImportGuideView(
            csvURLs: csvURLs,
            onFinished: { _ in
                context.completeRequest(returningItems: nil, completionHandler: nil)
            },
            onCancel: {
                context.cancelRequest(withError: NSError(domain: "UserCancelled", code: 0))
            }
        )
    }

    var urlImporter: some View {
        List {
            if let sharedContentErrorMessage {
                Section {
                    Label(sharedContentErrorMessage, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(ShareDesign.surfaceBackground)
            }

            Section {
                HStack(alignment: .center, spacing: 12) {
                    if let previewImage = previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if let pageTitle = pageTitle {
                            Text(pageTitle)
                                .font(.headline)
                                .lineLimit(1)
                        }
                        if let url = pageURL, let host = url.host {
                            Text(host)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listRowBackground(ShareDesign.surfaceBackground)
            
            Section("Destination") {
                Button {
                    withAnimation {
                        selectedGoal = nil
                    }
                } label: {
                    ShareDestinationRow(
                        title: "New Goal",
                        detail: "Create a goal from this link.",
                        systemImage: "target",
                        image: nil,
                        isSelected: selectedGoal == nil
                    )
                }
                .buttonStyle(.plain)

                ForEach(existingGoals) { goal in
                    Button {
                        withAnimation {
                            selectedGoal = goal
                        }
                    } label: {
                        ShareDestinationRow(
                            title: goal.name ?? "Unnamed Goal",
                            detail: "Save this link to an existing goal.",
                            systemImage: "target",
                            image: goal.uiImage,
                            isSelected: selectedGoal == goal
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(ShareDesign.surfaceBackground)
            
            if selectedGoal == nil {
                Section("New Goal Details") {
                    if allImages.isEmpty {
                        Button("Load All Images") {
                            if let url = pageURL {
                                loadAllImages(from: url)
                            }
                        }
                    } else {
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                ForEach(allImages.indices, id: \.self) { idx in
                                    Button {
                                        withAnimation {
                                            selectedImage = allImages[idx]
                                        }
                                    } label: {
                                        Image(uiImage: allImages[idx])
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .padding()
                                            .frame(width: 80, height: 80)
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .strokeBorder(selectedImage == allImages[idx] ? ShareDesign.accent : ShareDesign.separator, lineWidth: 1)
                                            )
                                            
                                    }
                                }
                            }
                            .padding()
                        }
                        .scrollIndicators(.hidden)
                        .listRowInsets(EdgeInsets())
                    }
                    HStack {
                        Text("Name")
                        TextField("iPhone", text: $nameText)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Target Amount")
                        TextField("$500", value: $targetAmount, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    Picker("Priority", selection: $priorityWeight) {
                        Text("Low").tag(0.5)
                        Text("Medium").tag(1.0)
                        Text("High").tag(2.0)
                    }
                    DatePicker("Deadline", selection: $selectedDeadline, displayedComponents: .date)
                }
                .listRowBackground(ShareDesign.surfaceBackground)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ShareDesign.groupedBackground)
        .navigationTitle("Save Link")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    context.cancelRequest(withError: NSError(domain: "UserCancelled", code: 0))
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveAndComplete()
                }
                .disabled(pageURL == nil || (selectedGoal == nil && (nameText.isEmpty || targetAmount == nil)))
            }
        }
    }

    private func fetchModels() {
        do {
            let goalFetch = FetchDescriptor<Goal>()
            existingGoals = try modelContext.fetch(goalFetch)
        } catch {
            sharedContentErrorMessage = "MoneyMap could not load saved goals: \(error.localizedDescription)"
        }
    }

    private func loadCSVURLs() {
        guard
            let item = context.inputItems.first as? NSExtensionItem,
            let providers = item.attachments
        else {
            isResolvingSharedContent = false
            return
        }

        let candidateProviders = providers.compactMap { provider -> (NSItemProvider, String)? in
            guard let identifier = preferredCSVTypeIdentifier(for: provider) else { return nil }
            return (provider, identifier)
        }

        guard !candidateProviders.isEmpty else {
            isResolvingSharedContent = false
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var loadedURLs: [URL] = []
        var errors: [String] = []

        for (provider, identifier) in candidateProviders {
            group.enter()
            loadCSV(from: provider, typeIdentifier: identifier) { result in
                lock.lock()
                switch result {
                case .success(let url):
                    if let url, !loadedURLs.contains(url) {
                        loadedURLs.append(url)
                    }
                case .failure(let error):
                    errors.append(error.localizedDescription)
                }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            csvURLs = loadedURLs
            if csvURLs.isEmpty, !errors.isEmpty {
                sharedContentErrorMessage = errors.joined(separator: "\n")
            }
            isResolvingSharedContent = false
        }
    }

    private func preferredCSVTypeIdentifier(for provider: NSItemProvider) -> String? {
        let preferredIdentifiers = [
            UTType.commaSeparatedText.identifier,
            "public.comma-separated-values-text",
            "public.delimited-values-text",
            UTType.plainText.identifier,
            UTType.text.identifier,
            "public.file-url",
            UTType.data.identifier
        ]

        for identifier in preferredIdentifiers where provider.hasItemConformingToTypeIdentifier(identifier) {
            return identifier
        }

        return provider.registeredTypeIdentifiers.first { identifier in
            guard identifier != UTType.url.identifier else { return false }
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .commaSeparatedText)
                || type.conforms(to: .plainText)
                || type.conforms(to: .text)
                || type.conforms(to: .data)
        }
    }

    private func loadCSV(
        from provider: NSItemProvider,
        typeIdentifier: String,
        completion: @escaping (Result<URL?, Error>) -> Void
    ) {
        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { fileURL, _ in
            if let fileURL {
                do {
                    completion(.success(try copySharedCSVFile(at: fileURL, suggestedName: provider.suggestedName)))
                } catch {
                    completion(.failure(error))
                }
                return
            }

            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil as [AnyHashable:Any]?) { item, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                do {
                    if let url = item as? URL, url.isFileURL {
                        completion(.success(try copySharedCSVFile(at: url, suggestedName: provider.suggestedName)))
                    } else if let data = item as? Data {
                        completion(.success(try copySharedCSVData(data, suggestedName: provider.suggestedName)))
                    } else if let text = item as? String, let data = text.data(using: .utf8) {
                        completion(.success(try copySharedCSVData(data, suggestedName: provider.suggestedName)))
                    } else {
                        completion(.success(nil))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    private func copySharedCSVFile(at sourceURL: URL, suggestedName: String?) throws -> URL? {
        let data = try Data(contentsOf: sourceURL)
        let name = suggestedName ?? sourceURL.lastPathComponent
        return try copySharedCSVData(data, suggestedName: name)
    }

    private func copySharedCSVData(_ data: Data, suggestedName: String?) throws -> URL? {
        guard isLikelyCSV(data: data, suggestedName: suggestedName) else { return nil }

        let destination = try uniqueImportDestination(suggestedName: suggestedName)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private func isLikelyCSV(data: Data, suggestedName: String?) -> Bool {
        if suggestedName?.lowercased().hasSuffix(".csv") == true {
            return true
        }

        let prefix = data.prefix(4096)
        guard let text = String(data: prefix, encoding: .utf8)?.lowercased() else { return false }
        return text.contains("transaction date")
            && text.contains("amount (usd)")
            && text.contains(",")
    }

    private func uniqueImportDestination(suggestedName: String?) throws -> URL {
        let directory = try importInboxDirectory()
        let baseName = sanitizedCSVBaseName(suggestedName)
        var destination = directory.appendingPathComponent(baseName).appendingPathExtension("csv")
        var index = 2

        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory
                .appendingPathComponent("\(baseName) \(index)")
                .appendingPathExtension("csv")
            index += 1
        }

        return destination
    }

    private func importInboxDirectory() throws -> URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.heyjoshsmith.MoneyMap")
            ?? fileManager.temporaryDirectory
        let directory = baseURL.appendingPathComponent("Shared CSV Imports", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func sanitizedCSVBaseName(_ suggestedName: String?) -> String {
        let rawName = suggestedName?.isEmpty == false ? suggestedName ?? "" : "Apple Card Transactions"
        let withoutExtension = (rawName as NSString).deletingPathExtension
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let cleaned = withoutExtension
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : " " }
            .reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Apple Card Transactions" : cleaned
    }

    public func loadURL() {
        guard
            let item = context.inputItems.first as? NSExtensionItem,
            let provider = item.attachments?.first(where: {
                $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
            })
        else { return }

        // 2️⃣ Give the compiler a hint for the options dictionary
        provider.loadItem(
            forTypeIdentifier: UTType.url.identifier,
            options: nil as [AnyHashable:Any]?
        ) { data, error in
            DispatchQueue.main.async {
                if let url = data as? URL {
                    self.pageURL = url
                    self.loadPreviewImage(from: url)
                    self.loadAllImages(from: url)
                    self.loadPageTitle(from: url)
                }
            }
        }
    }

    public func saveAndComplete() {
        guard let url = pageURL else { return }

        if selectedGoal == nil {
            let imageData = selectedImage?.jpegData(compressionQuality: 0.8)
            let goal = Goal(nameText, targetAmount: targetAmount ?? 0, deadline: selectedDeadline, weight: priorityWeight, paydaysUntil: 1, imageData: imageData)
            goal.addURL(url.absoluteString)
            modelContext.insert(goal)
        } else if let goal = selectedGoal {
            goal.addURL(url.absoluteString)
        }

        try? modelContext.save()
        context.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func loadPreviewImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let htmlData = data,
                  let html = String(data: htmlData, encoding: .utf8),
                  let ogRange = html.range(of: "<meta property=\"og:image\" content=\"") else { return }
            let substring = html[ogRange.upperBound...]
            guard let endQuote = substring.firstIndex(of: "\"") else { return }
            let imgURLString = String(substring[..<endQuote])
            guard let imgURL = URL(string: imgURLString) else { return }
            URLSession.shared.dataTask(with: imgURL) { imgData, _, _ in
                if let imgData = imgData, let uiImage = UIImage(data: imgData) {
                    DispatchQueue.main.async {
                        self.previewImage = uiImage
                    }
                }
            }.resume()
        }.resume()
    }

    private func loadAllImages(from url: URL) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let htmlData = data,
                  let html = String(data: htmlData, encoding: .utf8) else { return }
            let pattern = "<img[^>]+src=\"([^\"]+)\""
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
            let nsHTML = html as NSString
            let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length))
            let urls = matches.compactMap { match -> URL? in
                let imgURLString = nsHTML.substring(with: match.range(at: 1))
                // Try absolute URL first
                if let absolute = URL(string: imgURLString) {
                    return absolute
                }
                // Fallback to relative URL based on page URL
                if let relative = URL(string: imgURLString, relativeTo: url)?.absoluteURL {
                    return relative
                }
                return nil
            }
            DispatchQueue.main.async {
                self.allImageURLs = urls
                self.allImages = []
                for imgURL in urls {
                    URLSession.shared.dataTask(with: imgURL) { imgData, _, _ in
                        if let imgData = imgData, let uiImage = UIImage(data: imgData) {
                            DispatchQueue.main.async {
                                self.allImages.append(uiImage)
                            }
                        }
                    }.resume()
                }
            }
        }.resume()
    }

    private func loadPageTitle(from url: URL) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let html = String(data: data, encoding: .utf8),
                  let start = html.range(of: "<title>"),
                  let end = html.range(of: "</title>") else { return }
            let titleText = String(html[start.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                self.pageTitle = titleText
            }
        }.resume()
    }
}

private struct ShareStatusRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(ShareDesign.accent)
                .frame(width: 28)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ShareDestinationRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let image: UIImage?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: systemImage)
                        .font(.headline)
                        .foregroundStyle(ShareDesign.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(ShareDesign.controlBackground)
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: ShareDesign.cornerRadius))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ShareDesign.accent)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

extension Goal {
    /// Copies the image file into the extension sandbox and returns a UIImage.
    /// - Warning: Deprecated. Use imageData/uiImage for synced images. This method is only for migration/legacy support.
    @available(*, deprecated, message: "Use imageData/uiImage for synced images. This method is only for migration/legacy support.")
    func tempImage() -> UIImage? {
        if let data = imageData {
            return UIImage(data: data)
        }
        guard let srcURL = imageURL else { return nil }
        let tmpURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(srcURL.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: tmpURL.path) {
                try FileManager.default.removeItem(at: tmpURL)
            }
            try FileManager.default.copyItem(at: srcURL, to: tmpURL)
            let data = try Data(contentsOf: tmpURL)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
