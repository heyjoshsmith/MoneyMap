//
//  BillView.swift
//  MoneyMap
//
//  Created by Josh Smith on 3/26/25.
//

import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers
import ImagePlayground

struct BillView: View {
    
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @Environment(\.modelContext) private var modelContext
    
    var bill: Bill
    
    @State private var animate = false
    @State private var editingLimit = false
    @State private var selectedImage: UIImage? = nil
    @State private var imagePickerSource: ImagePickerSource? = nil
    @State private var cardLimit = ""
    @State private var creatingImage: Bool = false
    @State private var showingImporter = false
    @State private var importErrorAlert = false
    @State private var importErrorMessage: String = ""
    @State private var selectedCategory: String? = nil
    @State private var searchText = ""
    
    @State private var showingFriendlyNamePrompt = false
    @State private var pendingFriendlyName = ""
    @State private var transactionForFriendlyName: Transaction? = nil
    @State private var matchPrefix = false
    @State private var prefixSearchText = ""
    
    enum TransactionSortField: String, CaseIterable, Identifiable {
        case date = "Date"
        case amount = "Amount"
        case merchant = "Merchant"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .date: return "calendar"
            case .amount: return "dollarsign.circle"
            case .merchant: return "building.2"
            }
        }
    }
    enum SortOrder: String, CaseIterable, Identifiable {
        case ascending = "Ascending"
        case descending = "Descending"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .ascending: return "arrow.up"
            case .descending: return "arrow.down"
            }
        }
    }
    @State private var transactionSortField: TransactionSortField = .date
    @State private var transactionSortOrder: SortOrder = .descending
    
    private var dueDateValue: Date? {
        bill.dueDate
    }
    
    var allCategories: [String] {
        Set((bill.transactions ?? []).compactMap { $0.category }).sorted()
    }
    
    var transactionView: some View {
        return VStack(alignment: .leading, spacing: 8) {
            
            NavigationLink(destination: transactionList) {
                HStack(spacing: 4) {
                    Text("Transactions")
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.primary)
                .contentShape(.rect)
            }
            
            if (bill.transactions ?? []).isEmpty {
                Text("No transactions available.")
                    .foregroundStyle(.secondary)
                    .padding(.leading)
            } else {
                ForEach(filteredAndSortedTransactions[0...2], id: \.self) { transaction in
                    TransactionRow(transaction: transaction, onSetFriendlyName: { selected in
                        pendingFriendlyName = ""
                        transactionForFriendlyName = selected
                        prefixSearchText = selected.merchant ?? ""
                        showingFriendlyNamePrompt = true
                    })
                    .padding(.vertical, 6)
                }
                if filteredAndSortedTransactions.count > 3 {
                    Text("+ \(filteredAndSortedTransactions.count - 3) more")
                        .foregroundStyle(.secondary)
                }
            }
            
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 15))
        .padding(.top)
    }
    
    var searchedTransactions: [Transaction] {
        if searchText.isEmpty { return filteredAndSortedTransactions }
        return filteredAndSortedTransactions.filter { tx in
            (tx.friendlyName?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (tx.merchant?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (tx.category?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var transactionList: some View {
        List {
            ForEach(searchedTransactions, id: \.self) { transaction in
                TransactionRow(transaction: transaction, onSetFriendlyName: { selected in
                    pendingFriendlyName = ""
                    transactionForFriendlyName = selected
                    prefixSearchText = selected.merchant ?? ""
                    showingFriendlyNamePrompt = true
                })
            }
        }
        .searchable(text: $searchText)
        .navigationTitle("Transactions")
        .toolbar {
            Menu("Options", systemImage: "ellipsis.circle") {
                Menu("Filter", systemImage: "line.horizontal.3.decrease.circle") {
                    Picker("Category", selection: $selectedCategory) {
                        Label("All", systemImage: "line.3.horizontal.decrease.circle").tag(String?.none)
                        ForEach(allCategories, id: \.self) { category in
                            Label(category, systemImage: "tag").tag(category as String?)
                        }
                    }
                }
                Menu("Sort", systemImage: "arrow.up.arrow.down") {
                    Picker("Sort by", selection: $transactionSortField) {
                        ForEach(TransactionSortField.allCases) { field in
                            Label(field.rawValue, systemImage: field.icon).tag(field)
                        }
                    }
                    Picker("Order", selection: $transactionSortOrder) {
                        ForEach(SortOrder.allCases) { order in
                            Label(order.rawValue, systemImage: order.icon).tag(order)
                        }
                    }
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    (bill.transactions ?? []).forEach { transaction in
                        modelContext.delete(transaction)
                    }
                }
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                billHeaderSection
                
                VStack(spacing: 10) {
                    
                    // Credit Card Details (if applicable)
                    creditCardDetailsSection
                    
                    // Recurrence
                    recurrenceSection
                    
                    transactionView
                    
                }
                .padding()
            }
        }
        .navigationTitle("Bill Details")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section("Add Image") {
                        ForEach(ImagePickerSource.allCases, id: \.self) { source in
                            Button {
                                if source == .playground {
                                    creatingImage = true
                                } else {
                                    imagePickerSource = source
                                }
                            } label: {
                                Label(source.title, systemImage: source.systemImage)
                                    .foregroundStyle(source.color)
                            }
                        }
                    }
                    Section {
                        Button("Import Transactions") {
                            showingImporter = true
                        }
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis")
                }
            }
        }
        .alert("Card Limit", isPresented: $editingLimit) {
            TextField("New Limit", text: $cardLimit)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let newLimit = Double(cardLimit) {
                    // TODO: Update card limit via binding or callback. Cannot mutate bill here.
                    print(newLimit)
                }
            }
        } message: {
            if let details = bill.creditCardDetails {
                Text("What is your new card limit? Your current limit is \(details.creditLimit, format: .currency(code: "USD"))")
            }
        }
        .alert("Import Error", isPresented: $importErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importErrorMessage.isEmpty ? "Failed to import transactions from selected file." : importErrorMessage)
        }
        .sheet(item: $imagePickerSource) { source in
            switch source {
            case .camera:
                ImagePicker(sourceType: .camera) { image in
                    selectedImage = image
                    imagePickerSource = nil
                    bill.setImage(image)
                }
            case .photoLibrary:
                ImagePicker(sourceType: .photoLibrary) { image in
                    selectedImage = image
                    imagePickerSource = nil
                    bill.setImage(image)
                }
            case .files:
                DocumentPicker { image in
                    selectedImage = image
                    imagePickerSource = nil
                    bill.setImage(image)
                }
            case .playground:
                // Present the official Image Playground UI via a dedicated view
                EmptyView()
            }
        }
        .imagePlaygroundSheet(isPresented: $creatingImage, onCompletion: { url in
            Task {
                if let data = try? Data(contentsOf: url),
                    let image = UIImage(data: data) {
                    selectedImage = image
                    bill.setImage(image)
                }
            }
        })
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.commaSeparatedText], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                var errorMessages: [String] = []
                for url in urls {
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        do {
                            _ = try importTransactions(fromCSVAt: url, to: bill, context: modelContext)
                        } catch {
                            errorMessages.append("\(url.lastPathComponent): \(error.localizedDescription)")
                        }
                    } else {
                        errorMessages.append("\(url.lastPathComponent): Unable to access the selected file due to system restrictions.")
                    }
                }
                if !errorMessages.isEmpty {
                    importErrorMessage = errorMessages.joined(separator: "\n")
                    importErrorAlert = true
                }
            case .failure(let error):
                importErrorMessage = error.localizedDescription
                importErrorAlert = true
            }
        }
        .sheet(isPresented: $showingFriendlyNamePrompt) {
            FriendlyNameSheet(
                isPresented: $showingFriendlyNamePrompt,
                friendlyName: $pendingFriendlyName,
                matchPrefix: $matchPrefix,
                prefixSearchText: $prefixSearchText
            ) { saved in
                if saved {
                    guard let transaction = transactionForFriendlyName,
                          let merchant = transaction.merchant else {
                        transactionForFriendlyName = nil
                        pendingFriendlyName = ""
                        matchPrefix = false
                        prefixSearchText = ""
                        return
                    }
                    
                    if matchPrefix {
                        let prefix = prefixSearchText.trimmingCharacters(in: .whitespaces)
                        print("[DEBUG] Prefix to match (trimmed, lowercased): '\(prefix)'")
                        let allMerchants = (bill.transactions ?? []).compactMap { $0.merchant }
                        for merchantName in allMerchants { print("[DEBUG] Candidate merchant: '\(merchantName)'") }
                        if prefix.isEmpty {
                            // If prefix is empty when matchPrefix enabled, do not make changes
                            transactionForFriendlyName = nil
                            pendingFriendlyName = ""
                            matchPrefix = false
                            prefixSearchText = ""
                            return
                        }
                        for tx in (bill.transactions ?? []) {
                            let merchantName = tx.merchant ?? "<nil>"
                            let isMatch = merchantName.lowercased().hasPrefix(prefix.lowercased())
                            print("[DEBUG] '\(merchantName)' matches prefix '\(prefix)'? \(isMatch)")
                        }
                        let matchingTransactions = (bill.transactions ?? []).filter {
                            guard let merchantName = $0.merchant else { return false }
                            return merchantName.lowercased().hasPrefix(prefix.lowercased())
                        }
                        print("[DEBUG] Matched transactions count: \(matchingTransactions.count)")
                        print("[DEBUG] Matched merchants: \(matchingTransactions.compactMap { $0.merchant })")
                        for tx in matchingTransactions {
                            tx.friendlyName = pendingFriendlyName
                        }
                    } else {
                        let matchingTransactions = (bill.transactions ?? []).filter {
                            $0.merchant == merchant
                        }
                        for tx in matchingTransactions {
                            tx.friendlyName = pendingFriendlyName
                        }
                    }
                    do {
                        try modelContext.save()
                    } catch {
                        // Handle save error if needed
                    }
                }
                transactionForFriendlyName = nil
                pendingFriendlyName = ""
                matchPrefix = false
                prefixSearchText = ""
            }
        }
    }
    
    private func sortMenuIcon(for field: TransactionSortField, order: SortOrder) -> String {
        switch field {
        case .date:
            return order == .ascending ? "calendar.badge.plus" : "calendar.badge.minus"
        case .amount:
            return order == .ascending ? "arrow.up.circle" : "arrow.down.circle"
        case .merchant:
            return order == .ascending ? "textformat.abc" : "textformat"
        }
    }
    
    private var sortedTransactions: [Transaction] {
        let transactions = bill.transactions ?? []
        let sorted: [Transaction]
        switch transactionSortField {
        case .date:
            sorted = transactions.sorted { lhs, rhs in
                let lhsDate = lhs.transactionDate ?? .distantPast
                let rhsDate = rhs.transactionDate ?? .distantPast
                if transactionSortOrder == .ascending {
                    return lhsDate < rhsDate
                } else {
                    return lhsDate > rhsDate
                }
            }
        case .amount:
            sorted = transactions.sorted { lhs, rhs in
                let lhsAmt = lhs.amountUSD ?? 0
                let rhsAmt = rhs.amountUSD ?? 0
                if transactionSortOrder == .ascending {
                    return lhsAmt < rhsAmt
                } else {
                    return lhsAmt > rhsAmt
                }
            }
        case .merchant:
            sorted = transactions.sorted { lhs, rhs in
                let lhsM = lhs.merchant ?? ""
                let rhsM = rhs.merchant ?? ""
                if transactionSortOrder == .ascending {
                    return lhsM.localizedCaseInsensitiveCompare(rhsM) == .orderedAscending
                } else {
                    return lhsM.localizedCaseInsensitiveCompare(rhsM) == .orderedDescending
                }
            }
        }
        return sorted
    }
    
    private var filteredAndSortedTransactions: [Transaction] {
        guard let selected = selectedCategory, !selected.isEmpty else { return sortedTransactions }
        return sortedTransactions.filter { $0.category == selected }
    }
    
    static func createTransaction(from dict: [String: String]) -> Transaction? {
        return Transaction(
            transactionDate: dict["Transaction Date"]?.replacingOccurrences(of: "\"", with: ""),
            clearingDate: dict["Clearing Date"]?.replacingOccurrences(of: "\"", with: ""),
            transactionDescription: dict["Description"]?.replacingOccurrences(of: "\"", with: ""),
            merchant: dict["Merchant"]?.replacingOccurrences(of: "\"", with: ""),
            category: dict["Category"]?.replacingOccurrences(of: "\"", with: ""),
            type: dict["Type"]?.replacingOccurrences(of: "\"", with: ""),
            amountUSD: Double(dict["Amount (USD)"]?.replacingOccurrences(of: "\"", with: "") ?? ""),
            purchasedBy: dict["Purchased By"]?.replacingOccurrences(of: "\"", with: "")
        )
    }
    
    private var billHeaderSection: some View {
        ZStack {
            if let billImage = bill.image {
                billImage
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: 300)
                    .clipped()
                    .overlay(
                        Rectangle()
                            .fill(Color.black.opacity(0.4))
                    )
            } else {
                Rectangle()
                    .fill(bill.category?.color.gradient ?? Color.gray.gradient)
            }

            VStack(spacing: 10) {
                if bill.category != .creditCard {
                    Text(bill.amount ?? 0, format: .currency(code: "USD"))
                        .font(.title.weight(.medium))
                }
                Label(bill.name ?? "Untitled", systemImage: bill.category?.icon ?? "questionmark.circle")
                    .font(.largeTitle.weight(.semibold))
                if let dueDate = dueDateValue {
                    Text(dueDate, style: .date)
                        .opacity(0.7)
                } else {
                    Text(Date(), style: .date)
                        .opacity(0.7)
                }
            }
            .scaleEffect(animate ? 1.0 : 0.75)
            .opacity(animate ? 1.0 : 0.0)
            .foregroundStyle(.white)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animate = true
            }
        }
        .frame(maxWidth: .infinity, idealHeight: 300)
    }
    
    private var creditCardDetailsSection: some View {
        Group {
            if bill.category == .creditCard, let details = bill.creditCardDetails {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Card Balance")
                            .font(.title3.weight(.medium))
                        Text("\(details.cardBalance.abbreviatedCurrency) of \(details.creditLimit.abbreviatedCurrency)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Gauge(value: details.cardBalance, in: 0...details.creditLimit) {
                        Text(details.utilization, format: .percent.precision(.fractionLength(0)))
                            .font(.callout.weight(.medium))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(aboveMax ? .red : .green)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 15))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 5)
                .padding(.bottom)
                
                HStack {
                    Text("Max Usage")
                    Spacer()
                    Text(details.creditLimit * 0.3, format: .currency(code: "USD"))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                
                if let recommendedPayment {
                    HStack {
                        Text("Recommended Payment")
                        Spacer()
                        Text(recommendedPayment, format: .currency(code: "USD"))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    private var recurrenceSection: some View {
        HStack {
            Text("Recurrence")
            Spacer()
            Text("Every \(bill.recurrenceInterval ?? 1) \(bill.recurrenceUnit?.rawValue ?? "")\((bill.recurrenceInterval ?? 1) > 1 ? "s" : "")")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }
    
    var recommendedPayment: Double? {
        
        guard let details = bill.creditCardDetails else {
            return nil
        }
        
        let payment = details.cardBalance - (details.creditLimit * 0.3)
        
        if payment < 0 {
            return nil
        } else {
            return payment
        }
    }
    
    var aboveMax: Bool {
        if let creditCardDetails = bill.creditCardDetails {
            
            return (creditCardDetails.cardBalance / creditCardDetails.creditLimit) >= 0.3
            
        }
        
        return false
    }
    
    var utilizationIcon: some View {
        HStack {
            if let creditCardDetails = bill.creditCardDetails {
                
                let above = (creditCardDetails.cardBalance / creditCardDetails.creditLimit) >= 0.3
                
                if above {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                
                Text((creditCardDetails.cardBalance / creditCardDetails.creditLimit), format: .percent.precision(.fractionLength(0)))
                
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .foregroundStyle(.gray)
                Text("N/A")
            }
        }
    }
}

/// A sheet view used for setting friendly name and match prefix option.
/// Now includes prefixSearchText binding for user input when match prefix is enabled.
struct FriendlyNameSheet: View {
    @Binding var isPresented: Bool
    @Binding var friendlyName: String
    @Binding var matchPrefix: Bool
    @Binding var prefixSearchText: String
    var onComplete: (Bool) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Friendly Name", text: $friendlyName)
                    Toggle("Match all transactions that begin with this text", isOn: $matchPrefix)
                    if matchPrefix {
                        TextField("Prefix to match", text: $prefixSearchText)
                    }
                }
            }
            .navigationTitle("Set Friendly Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem {
                    Button("Save", systemImage: "checkmark", role: .confirm) {
                        print("Saving friendly name \(friendlyName) and match prefix \(matchPrefix)")
                        onComplete(true)
                        isPresented = false
                    }
                    .disabled(friendlyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

enum ImagePickerSource: Int, Identifiable, CaseIterable {
    case camera, photoLibrary, files, playground
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .camera: return "Camera"
        case .photoLibrary: return "Photos"
        case .files: return "Files"
        case .playground: return "Playground"
        }
    }
    
    var systemImage: String {
        switch self {
        case .camera: return "camera"
        case .photoLibrary: return "photo.on.rectangle"
        case .files: return "doc"
        case .playground: return "paintpalette"
        }
    }
    
    var color: Color {
        switch self {
        case .camera: return .blue
        case .photoLibrary: return .orange
        case .files: return .purple
        case .playground: return .green
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }

    var sourceType: UIImagePickerController.SourceType
    var onImagePicked: (UIImage) -> Void

    @Environment(\.presentationMode) private var presentationMode

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.presentationMode.wrappedValue.dismiss()
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                parent.presentationMode.wrappedValue.dismiss()
                return
            }
            
            if let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                parent.onImagePicked(image)
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }

    var onImagePicked: (UIImage) -> Void

    @Environment(\.presentationMode) private var presentationMode

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types = [UTType.image]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

func importTransactions(fromCSVAt url: URL, to bill: Bill, context: ModelContext) throws -> Int {
    let content = try String(contentsOf: url, encoding: .utf8)
    let rows = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    guard rows.count > 1 else { return 0 }
    let header = rows[0].components(separatedBy: ",")
    let dataRows = rows.dropFirst()
    var importedCount = 0
    
    print("Importing \(dataRows.count) Transactions...",dataRows)
    
    for row in dataRows {
        let columns = row.components(separatedBy: ",")
        if columns.count == header.count {
            var dict = [String: String]()
            for (index, key) in header.enumerated() {
                dict[key.trimmingCharacters(in: .whitespacesAndNewlines)] = columns[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let transaction = BillView.createTransaction(from: dict) {
                transaction.creditCard = bill
                if let merchant = transaction.merchant {
                    if let existingFriendly = (bill.transactions ?? []).first(where: { $0.merchant == merchant && ($0.friendlyName?.isEmpty == false) })?.friendlyName {
                        transaction.friendlyName = existingFriendly
                    }
                }
                context.insert(transaction)
                importedCount += 1
            }
        }
    }
    try context.save()
    return importedCount
}


#Preview {
    // Create a sample bill for preview purposes
    let sampleBill = Bill(name: "Sample Bill",
                          amount: 123.45,
                          dueDate: .distantPast,
                          category: .creditCard,
                          recurrenceInterval: 1,
                          recurrenceUnit: .month,
                          creditCardDetails: CreditCardDetails(creditLimit: 5000, cardBalance: 1200)
    )
    NavigationStack {
        BillView(bill: sampleBill)
    }
}
