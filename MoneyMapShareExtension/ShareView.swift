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

@main
struct ShareExtensionApp: App {
    let container: ModelContainer

    init() {
        let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.heyjoshsmith.MoneyMap")!
        let storeURL = containerURL.appendingPathComponent("shared.sqlite")
        
//        deleteAndPrintStoreURL()
        let schema = Schema([Goal.self, PaydayConfig.self, Bill.self])
        do {
            if let container = try? ModelContainer(
                for: schema,
                configurations: [
                    ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .private("iCloud.com.heyjoshsmith.MoneyMap"))
                ]
            ) {
                self.container = container
            } else {
                self.container = try ModelContainer(
                    for: schema,
                    configurations: [
                        ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
                    ]
                )
            }
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        
        do {
          let bills = try container.mainContext.fetch(FetchDescriptor<Bill>())
          print("Diagnostics - Bills count: \(bills.count)")
          for bill in bills {
            print("Bill - id: \(bill.id), name: \(bill.name), category: \(bill.category), dueDate: \(bill.dueDate)")
          }

          let goals = try container.mainContext.fetch(FetchDescriptor<Goal>())
          print("Diagnostics - Goals count: \(goals.count)")
          for goal in goals {
            print("Goal - id: \(goal.id), name: \(goal.name)")
          }
        } catch {
          print("Error during diagnostics fetch: \(error)")
        }
        
    }

    var body: some Scene {
        WindowGroup {
            ShareView(context: .init())
                .environment(\.modelContext, container.mainContext)
                .modelContainer(container)
        }
    }
}

struct ShareView: View {
    // 1️⃣ Receive the context from the parent controller
    let context: NSExtensionContext

    @Environment(\.modelContext) private var modelContext
    @State private var existingGoals: [Goal] = []
    @State private var targetAmount: Double?
    @State private var selectedGoal: Goal?
    @State private var saveToNewGoal = true

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
    
    @State private var allBills: [Bill] = []
    @State private var creditCards: [Bill] = []
    @State private var isImporting = false
    @State private var importErrorMessage: String?
    @State private var fetchCreditCardsStatus: String? = nil

    var body: some View {
        NavigationView {
            if !csvURLs.isEmpty {
                // Present CSV import UI with credit card picker
                csvImporter
            } else {
                urlImporter
            }
        }
        .onAppear {
            loadURL()
            loadCSVURLs()
            fetchModels()
        }
    }
    
    var csvImporter: some View {
        Form {
            
            Section("Status") {
                HStack {
                    Text("Goals")
                    Spacer()
                    Text("\(existingGoals.count)")
                }
                HStack {
                    Text("Bills")
                    Spacer()
                    Text("\(allBills.count)")
                }
                HStack {
                    Text("Credit Cards")
                    Spacer()
                    Text("\(creditCards.count)")
                }
            }
            if creditCards.isEmpty && !isImporting {
                Section("CSV Import") {
                    Text("Found CSV files to import:")
                        .font(.headline)
                    ForEach(csvURLs, id: \.self) { csvURL in
                        Text(csvURL.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text("Loading credit cards...")
                        .foregroundColor(.secondary)
                    if let status = fetchCreditCardsStatus {
                        if status.starts(with: "Failed") {
                            Text(status)
                                .foregroundColor(.red)
                        } else {
                            Text(status)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else if !isImporting {
                Section("CSV Import") {
                    Text("Select a credit card to import CSV transactions:")
                        .font(.headline)
                    ForEach(creditCards) { bill in
                        Button {
                            importCSV(to: bill)
                        } label: {
                            HStack {
                                Text(bill.name ?? "Unnamed Card")
                                Spacer()
                            }
                        }
                    }
                    Button("Cancel CSV Import") {
                        csvURLs.removeAll()
                        fetchCreditCardsStatus = nil
                    }
                    .foregroundColor(.red)
                }
            }
            if isImporting {
                Section {
                    HStack {
                        ProgressView()
                        Text("Importing transactions...")
                    }
                }
            }
            if let error = importErrorMessage {
                Section {
                    Text("Import failed: \(error)")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Import CSV")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    context.cancelRequest(withError: NSError(domain: "UserCancelled", code: 0))
                }
            }
        }
    }
    
    var urlImporter: some View {
        Form {
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
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Section("Destination") {
                ScrollView(.horizontal) {
                    HStack {
                        Button {
                            withAnimation {
                                selectedGoal = nil
                            }
                        } label: {
                            VStack(spacing: 0) {
                                Image(systemName: "dollarsign.arrow.trianglehead.counterclockwise.rotate.90")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(30)
                                    .frame(height: 100)
                                Text("New Goal")
                                    .padding(5)
                            }
                            .foregroundStyle(selectedGoal == nil ? .white : Color(uiColor: .label))
                            .background(selectedGoal == nil ? .blue : Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(.rect(cornerRadius: 10))
                        }
                        ForEach(existingGoals) { goal in
                            Button {
                                withAnimation {
                                    selectedGoal = goal
                                }
                            } label: {
                                VStack(spacing: 0) {
                                    if let img = goal.uiImage {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 100)
                                            .clipShape(.rect(cornerRadius: 10))
                                            .padding([.horizontal, .top],5)
                                    } else {
                                        Text("Could not load image")
                                    }
                                    Text(goal.name ?? "Unnamed Goal")
                                        .padding(5)
                                }
                                .foregroundStyle(selectedGoal == goal ? .white : Color(uiColor: .label))
                                .background(selectedGoal == goal ? .blue : Color(uiColor: .secondarySystemGroupedBackground))
                                .clipShape(.rect(cornerRadius: 10))
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            
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
                                                    .strokeBorder(selectedImage == allImages[idx] ? .blue : Color(uiColor: .separator), lineWidth: 1)
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
            }
        }
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
        // Changed to use FetchDescriptor initialization to mirror existingGoals fetching pattern for maintainability
        do {
            
            let goalFetch = FetchDescriptor<Goal>()
            existingGoals = try modelContext.fetch(goalFetch)
            
            let billFetch = FetchDescriptor<Bill>()
            allBills = try modelContext.fetch(billFetch)
            creditCards = allBills.filter { $0.category == .creditCard }
            
            if creditCards.isEmpty {
                fetchCreditCardsStatus = "No credit cards found. Found \(allBills.count) bills."
            } else {
                fetchCreditCardsStatus = "Found \(allBills.count) bills, \(creditCards.count) credit cards."
            }
            print(fetchCreditCardsStatus!)
        } catch {
            fetchCreditCardsStatus = "Failed to fetch credit cards: \(error.localizedDescription)"
            print("❌ \(fetchCreditCardsStatus!)")
            creditCards = []
        }
    }
    
    private func importCSV(to bill: Bill) {
        isImporting = true
        importErrorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            for url in csvURLs {
                do {
                    try importTransactions(fromCSVAt: url, to: bill, context: modelContext)
                } catch {
                    DispatchQueue.main.async {
                        importErrorMessage = error.localizedDescription
                        isImporting = false
                    }
                    return
                }
            }
            
            do {
                try modelContext.save()
            } catch {
                DispatchQueue.main.async {
                    importErrorMessage = "Failed to save context: \(error.localizedDescription)"
                    isImporting = false
                }
                return
            }
            
            DispatchQueue.main.async {
                isImporting = false
                context.completeRequest(returningItems: nil, completionHandler: nil)
            }
        }
    }

    private func loadCSVURLs() {
        guard
            let item = context.inputItems.first as? NSExtensionItem,
            let providers = item.attachments
        else { return }

        let csvType = UTType.commaSeparatedText.identifier

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(csvType) {
                provider.loadItem(forTypeIdentifier: csvType, options: nil as [AnyHashable:Any]?) { data, error in
                    DispatchQueue.main.async {
                        if let url = data as? URL {
                            if !csvURLs.contains(url) {
                                csvURLs.append(url)
                            }
                        }
                    }
                }
            }
        }
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

        if saveToNewGoal {
            
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

// Stub for importTransactions to ensure compilation if not defined elsewhere
func importTransactions(fromCSVAt url: URL, to bill: Bill, context: ModelContext) throws {
    // Implement CSV parsing and transaction creation here.
    // Stub does nothing
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
            print("Temp image load error: \(error)")
            return nil
        }
    }
}

