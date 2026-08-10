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
import AppIntents

struct BillView: View {
    
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query(sort: \PaymentMethod.name) private var paymentMethods: [PaymentMethod]
    @Query private var allTransactions: [Transaction]
    
    var bill: Bill
    
    @State private var animate = false
    @State private var editingLimit = false
    @State private var selectedImage: UIImage? = nil
    @State private var imagePickerSource: ImagePickerSource? = nil
    @State private var cardLimit = ""
    @State private var creatingImage: Bool = false
    @State private var showingImporter = false
    @State private var showingImportGuide = false
    @State private var pendingImportURLs: [URL] = []
    @State private var importErrorAlert = false
    @State private var importErrorMessage: String = ""
    @State private var selectedCategory: String? = nil
    @State private var searchText = ""
    
    @State private var showingFriendlyNamePrompt = false
    @State private var pendingFriendlyName = ""
    @State private var transactionForFriendlyName: Transaction? = nil
    @State private var matchPrefix = false
    @State private var prefixSearchText = ""
    @State private var makingPayment = false
    @State private var paymentAmount = ""
    @State private var showMarkPaidConfirmation = false
    @State private var autopayEnabled = false
    @State private var paymentMode: BillPaymentMode = .manual
    @State private var autopaySource = ""
    @State private var selectedPaymentMethodID: UUID?
    @State private var gracePeriodDays = 0
    @State private var plaidUnavailable = false
    @State private var showingPaymentLinkSetup = false
    @State private var showingPaymentSettings = false
    @State private var showingPaymentMethodEditor = false
    @State private var showingPlaidPaymentMethodSelector = false
    @State private var showingScheduleManager = false
    @State private var showingTransactionLinker = false
    @State private var showingScheduleResume = false
    @State private var showingBillEditor = false
    @State private var showingCardDataSources = false
    @State private var showingDeleteBillConfirmation = false
    @State private var showingPaymentDateEditor = false
    @State private var showingClearPaymentConfirmation = false
    @State private var pendingSetupAction: BillSetupAction?
    @State private var billTransactions: [Transaction] = []
    
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

    init(bill: Bill, initialSetupAction: BillSetupAction? = nil) {
        self.bill = bill
        let billID = bill.id
        _allTransactions = Query(
            filter: #Predicate<Transaction> { transaction in
                transaction.linkedBillID == billID || transaction.creditCard?.id == billID
            },
            sort: \Transaction.transactionDate,
            order: .reverse
        )
        _paymentMode = State(initialValue: bill.paymentMode)
        _autopayEnabled = State(initialValue: bill.autopayEnabled)
        _autopaySource = State(initialValue: bill.autopaySource ?? "")
        _selectedPaymentMethodID = State(initialValue: bill.paymentMethodID)
        _gracePeriodDays = State(initialValue: bill.gracePeriodDays ?? 0)
        _plaidUnavailable = State(initialValue: bill.plaidUnavailable)
        _pendingSetupAction = State(initialValue: initialSetupAction)
    }
    
    private var dueDateValue: Date? {
        bill.dueDate
    }
    
    var allCategories: [String] {
        Set(displayTransactions.compactMap { $0.category }).sorted()
    }

    private var previewTransactions: [Transaction] {
        Array(filteredAndSortedTransactions.prefix(3))
    }
    
    var transactionView: some View {
        return VStack(alignment: .leading, spacing: 10) {
            
            NavigationLink(destination: transactionList) {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(.blue)
                        .frame(width: 26)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transaction History")
                            .font(.headline)
                        Text(transactionSummaryText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.primary)
                .contentShape(.rect)
            }
            
            if displayTransactions.isEmpty {
                Text("No matching transactions yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(previewTransactions, id: \.self) { transaction in
                    TransactionRow(transaction: transaction, onSetFriendlyName: { selected in
                        pendingFriendlyName = ""
                        transactionForFriendlyName = selected
                        prefixSearchText = rawTransactionName(for: selected) ?? selected.merchant ?? ""
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
        .background(MoneyMapDesign.surfaceBackground)
        .clipShape(.rect(cornerRadius: MoneyMapDesign.sectionCornerRadius))
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
                    prefixSearchText = rawTransactionName(for: selected) ?? selected.merchant ?? ""
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
                Button("Disconnect History", systemImage: "link.badge.minus") {
                    displayTransactions.forEach { transaction in
                        if transaction.linkedBillID == bill.id {
                            transaction.linkedBillID = nil
                        }
                        if transaction.creditCard?.id == bill.id {
                            transaction.creditCard = nil
                        }
                    }
                    saveLinkedTransactionChange()
                }
                .disabled(displayTransactions.isEmpty)
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MoneyMapDesign.sectionSpacing) {
                billHeaderSection

                if shouldShowNextStep {
                    billActionSection
                }

                creditCardDetailsSection
                paymentSummarySection
                scheduleSummarySection
                transactionSummarySection
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle(bill.name ?? "Bill")
        .navigationBarTitleDisplayMode(.inline)
        .background(MoneyMapDesign.groupedBackground)
        .userActivity("com.heyjoshsmith.MoneyMap.viewingBill") { activity in
            let entity = BillEntity(bill)
            activity.title = "Viewing \(entity.name)"
            activity.appEntityIdentifier = EntityIdentifier(for: entity)
        }
        .onAppear {
            MoneyMapIntentDonations.donateOpenBill(bill)
            refreshDisplayTransactions()
            loadBillMeta()
            presentPendingSetupActionIfNeeded()
        }
        .onChange(of: allTransactions.count) { _, _ in
            refreshDisplayTransactions()
        }
        .onDisappear {
            saveBillMeta()
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("Edit") {
                    showingBillEditor = true
                }

                Menu {
                    NavigationLink {
                        ActivityFeedView(
                            title: bill.category == .creditCard ? "Card History" : "Bill History",
                            entityID: bill.id,
                            entityTypes: [bill.category == .creditCard ? .creditCard : .bill]
                        )
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
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
                        Button(MoneyMapAction.importTransactions.title, systemImage: MoneyMapAction.importTransactions.systemImage) {
                            showingImporter = true
                        }
                    }
                    Section {
                        if bill.category == .creditCard {
                            Button(MoneyMapAction.makePayment.title, systemImage: MoneyMapAction.makePayment.systemImage) {
                                paymentAmount = ""
                                makingPayment = true
                            }
                        } else if canManuallyMarkPaid {
                            Button("Mark Paid", systemImage: "checkmark.circle") {
                                showMarkPaidConfirmation = true
                            }
                        }
                    }

                    if bill.category == .creditCard {
                        Section {
                            Button(MoneyMapAction.editCardLimit.title, systemImage: MoneyMapAction.editCardLimit.systemImage) {
                                cardLimit = bill.creditCardDetails?.creditLimit.formatted(.number) ?? ""
                                editingLimit = true
                            }
                        }
                    }

                    Section {
                        Button("Delete Bill", systemImage: "trash", role: .destructive) {
                            showingDeleteBillConfirmation = true
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
                let normalized = cardLimit.replacingOccurrences(of: ",", with: "")
                if let newLimit = Double(normalized), newLimit >= 0 {
                    bill.creditCardDetails?.creditLimit = newLimit
                    do {
                        try modelContext.save()
                    } catch {
                        importErrorMessage = "Could not update card limit: \(error.localizedDescription)"
                        importErrorAlert = true
                    }
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
        .alert(paymentAlertTitle, isPresented: $makingPayment) {
            TextField(paymentPlaceholder, text: $paymentAmount)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) { }
            Button("Done") {
                recordPayment()
            }
        } message: {
            Text("How much would you like to pay?")
        }
        .modifier(
            BillDetailConfirmationDialogs(
                billName: bill.name,
                showingMarkPaid: $showMarkPaidConfirmation,
                showingDeleteBill: $showingDeleteBillConfirmation,
                showingClearPayment: $showingClearPaymentConfirmation,
                markPaid: markPaid,
                deleteBill: deleteBill,
                clearPaymentDate: clearPaymentDate
            )
        )
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
        .sheet(isPresented: $showingPaymentLinkSetup) {
            PaymentLinkSetupView(bill: bill)
        }
        .sheet(isPresented: $showingPaymentSettings) {
            BillPaymentSettingsSheet(
                bill: bill,
                paymentSettingsContent: {
                    billMetaSection
                }
            )
        }
        .sheet(isPresented: $showingPaymentMethodEditor) {
            PaymentMethodEditor { paymentMethod in
                selectedPaymentMethodID = paymentMethod.id
                saveBillMeta()
            }
        }
        .sheet(isPresented: $showingPlaidPaymentMethodSelector) {
            PlaidPaymentMethodSelectorContainerView(
                existingPaymentMethodAccountIDs: Set(paymentMethods.compactMap(\.plaidAccountID)),
                createPaymentMethod: createPaymentMethodFromPlaidAccount
            )
        }
        .sheet(isPresented: $showingBillEditor) {
            BillEditor(bill: bill)
        }
        .sheet(isPresented: $showingCardDataSources) {
            CreditCardDataSourcesView(bill: bill)
        }
        .sheet(isPresented: $showingPaymentDateEditor) {
            BillPaymentDateSheet(
                bill: bill,
                defaultDate: bill.datePaid ?? .now,
                onSave: updatePaymentDate
            )
        }
        .sheet(isPresented: $showingScheduleResume) {
            BillDateActionSheet(
                title: "Resume",
                bill: bill,
                defaultDate: defaultScheduleDate,
                confirmTitle: "Resume",
                onConfirm: resumeBill
            )
        }
        .sheet(isPresented: $showingScheduleManager) {
            BillScheduleManagerSheet(
                bill: bill,
                recurrenceContent: {
                    recurrenceSection
                },
                delay: delayBill,
                skip: skipBill,
                pause: pauseBill,
                cancel: cancelBill,
                resume: presentScheduleResumeFromManager
            )
        }
        .sheet(isPresented: $showingTransactionLinker) {
            BillTransactionLinkingView(
                bill: bill,
                linkTransaction: linkTransactionToBill,
                unlinkTransaction: unlinkTransactionFromBill
            )
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
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .text, .plainText],
            allowsMultipleSelection: true
        ) { result in
            handleImportResult(result)
        }
        .sheet(isPresented: $showingImportGuide, onDismiss: {
            pendingImportURLs.removeAll()
        }) {
            TransactionCSVImportGuideView(
                csvURLs: pendingImportURLs,
                fixedBill: bill,
                onFinished: { _ in
                    pendingImportURLs.removeAll()
                    showingImportGuide = false
                },
                onCancel: {
                    pendingImportURLs.removeAll()
                    showingImportGuide = false
                }
            )
        }
        .sheet(isPresented: $showingFriendlyNamePrompt) {
            FriendlyNameSheet(
                isPresented: $showingFriendlyNamePrompt,
                friendlyName: $pendingFriendlyName,
                matchPrefix: $matchPrefix,
                prefixSearchText: $prefixSearchText
            ) { saved in
                handleFriendlyNameResult(saved: saved)
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
        let sorted: [Transaction]
        switch transactionSortField {
        case .date:
            sorted = displayTransactions.sorted { lhs, rhs in
                let lhsDate = lhs.transactionDate ?? .distantPast
                let rhsDate = rhs.transactionDate ?? .distantPast
                if transactionSortOrder == .ascending {
                    return lhsDate < rhsDate
                } else {
                    return lhsDate > rhsDate
                }
            }
        case .amount:
            sorted = displayTransactions.sorted { lhs, rhs in
                let lhsAmt = lhs.amountUSD ?? 0
                let rhsAmt = rhs.amountUSD ?? 0
                if transactionSortOrder == .ascending {
                    return lhsAmt < rhsAmt
                } else {
                    return lhsAmt > rhsAmt
                }
            }
        case .merchant:
            sorted = displayTransactions.sorted { lhs, rhs in
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

    private var displayTransactions: [Transaction] {
        billTransactions
    }

    private func refreshDisplayTransactions() {
        billTransactions = MoneyMapDiagnostics.measure(
            "bill.detail.transactions",
            metadata: [
                "bill": bill.id.uuidString,
                "candidateTransactions": "\(allTransactions.count)"
            ]
        ) {
            sortedDirectTransactions(BillPaymentMatcher.connectedTransactions(for: bill, in: allTransactions))
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if urls.isEmpty {
                importErrorMessage = "No CSV files were selected."
                importErrorAlert = true
                return
            }
            pendingImportURLs = urls
            showingImportGuide = true
        case .failure(let error):
            importErrorMessage = error.localizedDescription
            importErrorAlert = true
        }
    }

    private func handleFriendlyNameResult(saved: Bool) {
        defer {
            transactionForFriendlyName = nil
            pendingFriendlyName = ""
            matchPrefix = false
            prefixSearchText = ""
        }

        guard saved,
              let transaction = transactionForFriendlyName else {
            return
        }

        let normalizedFriendlyName = pendingFriendlyName.trimmingCharacters(in: .whitespacesAndNewlines)

        if matchPrefix {
            let prefix = prefixSearchText.trimmingCharacters(in: .whitespaces)
            guard !prefix.isEmpty else { return }

            let matchingTransactions = allTransactionsIncluding(transaction).filter {
                guard let rawName = rawTransactionName(for: $0) else { return false }
                return rawName.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil
            }
            for tx in matchingTransactions {
                tx.friendlyName = normalizedFriendlyName
            }
        } else {
            let matchingTransactions = transactionsMatchingRawName(of: transaction, in: allTransactionsIncluding(transaction))
            for tx in matchingTransactions {
                tx.friendlyName = normalizedFriendlyName
            }
        }

        try? modelContext.save()
    }

    private var billTitle: String {
        let trimmed = (bill.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Bill" : trimmed
    }

    private var categoryTitle: String {
        bill.category?.name ?? "Other"
    }

    private var dueDateText: String {
        bill.dueDate.map(MoneyMapFormatters.mediumDateString(for:)) ?? "No date"
    }

    private var amountMetricTitle: String {
        bill.category == .creditCard ? "Balance" : "Amount"
    }

    private var amountMetricValue: String {
        if bill.category == .creditCard, let details = bill.creditCardDetails {
            return MoneyMapFormatters.currencyString(for: details.cardBalance)
        }
        return MoneyMapFormatters.currencyString(for: bill.amount ?? 0)
    }

    private var amountMetricIcon: String {
        bill.category == .creditCard ? "creditcard" : "dollarsign.circle"
    }

    private var amountMetricColor: Color {
        if bill.category == .creditCard {
            return aboveMax ? .red : .green
        }
        return bill.category?.color ?? .accentColor
    }

    private var statusIcon: String {
        guard bill.lifecycleState == .active else {
            return bill.lifecycleState.icon
        }

        switch bill.status {
        case .paid:
            return "checkmark.circle.fill"
        case .overdue:
            return "exclamationmark.triangle.fill"
        case .upcoming:
            return "calendar.badge.clock"
        case nil:
            return "questionmark.circle"
        }
    }

    private var shouldShowNextStep: Bool {
        if bill.lifecycleState == .active,
           bill.category != .creditCard,
           (bill.paymentMode == .autopay || bill.paymentMode == .inPerson) {
            return false
        }

        return true
    }

    private var primaryActionIcon: String {
        if bill.paymentURL != nil {
            return "arrow.up.forward.app"
        }
        if bill.category == .creditCard {
            return MoneyMapAction.makePayment.systemImage
        }
        if bill.lifecycleState == .active && bill.status != .paid {
            return "checkmark.circle"
        }
        return statusIcon
    }

    private var primaryActionText: String {
        switch bill.lifecycleState {
        case .paused:
            return "Paused until you resume it with a new due date."
        case .canceled:
            return "Canceled and kept here for history."
        case .active:
            break
        }

        if bill.category == .creditCard {
            if aboveMax {
                return "Balance is above the 30% target. Record a payment when you make one."
            }
            return "Keep the balance, payment date, and payment link current."
        }

        if bill.status == .paid {
            return "Paid for this cycle. Adjust the payment date if the record is off."
        }

        if bill.paymentMode == .inPerson {
            return "MoneyMap will mark this paid when a matching synced transaction arrives."
        }

        if bill.paymentURL == nil {
            return "No payment link is saved for this bill."
        }

        if bill.status == .overdue {
            return "Overdue. Open the pay link, then mark it paid when you're done."
        }

        return "Open the pay link when you're ready, then mark it paid."
    }

    private var recurrenceText: String {
        guard let interval = bill.recurrenceInterval, let unit = bill.recurrenceUnit else {
            return "One-time"
        }
        return "Every \(interval) \(unit.rawValue)\(interval == 1 ? "" : "s")"
    }

    private var transactionSummaryText: String {
        let count = displayTransactions.count
        return "\(count) transaction\(count == 1 ? "" : "s")"
    }

    private func refreshBillStatusFromTransactions() {
        if BillPaymentMatcher.refreshStatuses(for: [bill], transactions: displayTransactions) {
            try? modelContext.save()
        }
    }

    private func sortedDirectTransactions(_ values: [Transaction]) -> [Transaction] {
        values
            .filter { BillPaymentMatcher.isConnected($0, to: bill) }
            .sorted {
                (BillPaymentMatcher.transactionDate(for: $0) ?? .distantPast) >
                    (BillPaymentMatcher.transactionDate(for: $1) ?? .distantPast)
            }
    }
    
    private var billHeaderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                billIconView

                VStack(alignment: .leading, spacing: 6) {
                    Text(billTitle)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            Label(categoryTitle, systemImage: bill.category?.icon ?? "questionmark.circle")
                            Label(bill.lifecycleState.title, systemImage: bill.lifecycleState.icon)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Label(categoryTitle, systemImage: bill.category?.icon ?? "questionmark.circle")
                            Label(bill.lifecycleState.title, systemImage: bill.lifecycleState.icon)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    BillHeaderMetric(
                        title: amountMetricTitle,
                        value: amountMetricValue,
                        systemImage: amountMetricIcon,
                        tint: amountMetricColor
                    )
                    BillHeaderMetric(
                        title: "Due",
                        value: dueDateText,
                        systemImage: "calendar",
                        tint: bill.displayStatusColor
                    )
                    BillHeaderMetric(
                        title: "Status",
                        value: bill.displayStatusName,
                        systemImage: statusIcon,
                        tint: bill.displayStatusColor
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    BillHeaderMetric(
                        title: amountMetricTitle,
                        value: amountMetricValue,
                        systemImage: amountMetricIcon,
                        tint: amountMetricColor
                    )
                    BillHeaderMetric(
                        title: "Due",
                        value: dueDateText,
                        systemImage: "calendar",
                        tint: bill.displayStatusColor
                    )
                    BillHeaderMetric(
                        title: "Status",
                        value: bill.displayStatusName,
                        systemImage: statusIcon,
                        tint: bill.displayStatusColor
                    )
                }
            }
        }
        .padding()
        .background(MoneyMapDesign.surfaceBackground)
        .clipShape(.rect(cornerRadius: MoneyMapDesign.sectionCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MoneyMapDesign.sectionCornerRadius)
                .stroke(MoneyMapDesign.separator.opacity(0.35), lineWidth: 0.5)
        }
        .scaleEffect(animate ? 1.0 : 0.98)
        .opacity(animate ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.28)) {
                animate = true
            }
        }
    }

    @ViewBuilder
    private var billIconView: some View {
        if let billImage = bill.image {
            billImage
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: MoneyMapDesign.cornerRadius))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: MoneyMapDesign.cornerRadius)
                    .fill((bill.category?.color ?? .gray).gradient)

                Image(systemName: bill.category?.icon ?? "questionmark.circle")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
        }
    }

    private var billActionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Label("Next Step", systemImage: primaryActionIcon)
                    .font(.headline)

                Spacer(minLength: 8)

                BillStatusPill(
                    title: bill.displayStatusName,
                    systemImage: statusIcon,
                    tint: bill.displayStatusColor
                )
            }

            Text(primaryActionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            primaryActionGrid

            if let datePaid = bill.datePaid {
                Divider()

                BillDetailRow(
                    title: "Payment Date",
                    value: MoneyMapFormatters.mediumDateString(for: datePaid),
                    systemImage: "calendar.badge.checkmark",
                    tint: .green
                )

                paymentDateActionGrid
            }
        }
        .padding()
        .background(MoneyMapDesign.surfaceBackground)
        .clipShape(.rect(cornerRadius: MoneyMapDesign.sectionCornerRadius))
    }

    private var actionGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8, alignment: .top)
        ]
    }

    private var primaryActionGrid: some View {
        LazyVGrid(columns: actionGridColumns, alignment: .leading, spacing: 8) {
            ForEach(primaryActions) { action in
                BillDetailActionButton(action: action)
            }
        }
    }

    private var paymentDateActionGrid: some View {
        LazyVGrid(columns: actionGridColumns, alignment: .leading, spacing: 8) {
            ForEach(paymentDateActions) { action in
                BillDetailActionButton(action: action)
            }
        }
    }

    private var primaryActions: [BillDetailAction] {
        var actions: [BillDetailAction] = []

        if let paymentURL = bill.paymentURL, bill.paymentMode == .payLink {
            actions.append(
                BillDetailAction(
                    title: "Open Pay Link",
                    detail: bill.paymentHost ?? "Website or app",
                    systemImage: "arrow.up.forward.app",
                    tint: .blue,
                    style: .prominent
                ) {
                    openURL(paymentURL)
                }
            )
        } else if bill.paymentMode == .payLink || bill.paymentMode == .manual {
            actions.append(
                BillDetailAction(
                    title: "Set Up Link",
                    detail: "Website or app link",
                    systemImage: "link.badge.plus",
                    tint: .blue
                ) {
                    showingPaymentLinkSetup = true
                }
            )
        }

        if bill.category == .creditCard {
            actions.append(
                BillDetailAction(
                    title: MoneyMapAction.makePayment.title,
                    detail: paymentActionDetail,
                    systemImage: MoneyMapAction.makePayment.systemImage,
                    tint: .green,
                    style: bill.paymentURL == nil ? .prominent : .secondary
                ) {
                    paymentAmount = ""
                    makingPayment = true
                }
            )
        } else if canManuallyMarkPaid {
            actions.append(
                BillDetailAction(
                    title: "Mark Paid",
                    detail: MoneyMapFormatters.currencyString(for: bill.amount ?? 0),
                    systemImage: "checkmark.circle",
                    tint: .green,
                    style: bill.paymentURL == nil ? .prominent : .secondary
                ) {
                    showMarkPaidConfirmation = true
                }
            )
        }

        return actions
    }

    private var paymentDateActions: [BillDetailAction] {
        [
            BillDetailAction(
                title: "Edit Date",
                detail: "Correct the paid date",
                systemImage: "calendar",
                tint: .blue
            ) {
                showingPaymentDateEditor = true
            },
            BillDetailAction(
                title: "Clear Date",
                detail: "Mark unpaid again",
                systemImage: "minus.circle",
                tint: .red,
                role: .destructive
            ) {
                showingClearPaymentConfirmation = true
            }
        ]
    }

    private var paymentActionDetail: String {
        if let payment = bill.creditCardDetails?.recommendedPayment, payment > 0 {
            return "Recommended \(MoneyMapFormatters.currencyString(for: payment))"
        }
        if let minimum = bill.creditCardDetails?.effectiveMinimumPayment, minimum > 0 {
            return "Minimum \(MoneyMapFormatters.currencyString(for: minimum))"
        }
        return "Record an amount"
    }
    
    private var creditCardDetailsSection: some View {
        Group {
            if bill.category == .creditCard, let details = bill.creditCardDetails {
                let gaugeMaximum = max(details.creditLimit, details.cardBalance, 1)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Card")
                                    .font(.headline)
                                Text("\(details.cardBalance.abbreviatedCurrency) of \(details.creditLimit.abbreviatedCurrency)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "creditcard")
                                .foregroundStyle(aboveMax ? .red : .green)
                        }

                        Spacer(minLength: 8)

                        Gauge(value: min(details.cardBalance, gaugeMaximum), in: 0...gaugeMaximum) {
                            Text(details.utilization, format: .percent.precision(.fractionLength(0)))
                                .font(.callout.weight(.medium))
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .tint(aboveMax ? .red : .green)
                    }

                    Divider()

                    BillDetailRow(
                        title: "Balance",
                        value: MoneyMapFormatters.currencyString(for: details.cardBalance),
                        systemImage: "dollarsign.circle",
                        tint: aboveMax ? .red : .green
                    )
                    BillDetailRow(
                        title: "Credit Limit",
                        value: MoneyMapFormatters.currencyString(for: details.creditLimit),
                        systemImage: "gauge.with.dots.needle.67percent",
                        tint: .blue
                    )
                    BillDetailRow(
                        title: "Max Usage",
                        value: MoneyMapFormatters.currencyString(for: details.creditLimit * 0.3),
                        systemImage: "target",
                        tint: .orange
                    )

                    if let recommendedPayment, recommendedPayment > 0 {
                        BillDetailRow(
                            title: "Recommended Payment",
                            value: MoneyMapFormatters.currencyString(for: recommendedPayment),
                            systemImage: "arrow.down.circle",
                            tint: .green
                        )
                    }

                    if let apr = details.annualPercentageRate {
                        BillDetailRow(
                            title: "APR",
                            value: apr.formatted(.percent.precision(.fractionLength(2))),
                            systemImage: "percent",
                            tint: .purple
                        )
                    }

                    if details.effectiveMinimumPayment > 0 {
                        BillDetailRow(
                            title: "Minimum Payment",
                            value: MoneyMapFormatters.currencyString(for: details.effectiveMinimumPayment),
                            systemImage: "creditcard.and.123",
                            tint: .blue
                        )
                    }

                    if let statementBalance = details.statementBalance {
                        BillDetailRow(
                            title: "Statement Balance",
                            value: MoneyMapFormatters.currencyString(for: statementBalance),
                            systemImage: "doc.text",
                            tint: .indigo
                        )
                    }

                    if let issuerName = details.issuerName, !issuerName.isEmpty {
                        BillDetailRow(
                            title: "Issuer",
                            value: issuerName,
                            systemImage: "building.columns",
                            tint: .secondary
                        )
                    }

                    if let lastFour = details.lastFourDigits, !lastFour.isEmpty {
                        BillDetailRow(
                            title: "Card",
                            value: "•••• \(lastFour)",
                            systemImage: "number",
                            tint: .secondary
                        )
                    }

                    if bill.plaidAccountID != nil {
                        Button {
                            showingCardDataSources = true
                        } label: {
                            BillDetailRow(
                                title: "Data Sources",
                                value: bankSyncDetailText,
                                systemImage: "link.circle.fill",
                                tint: MoneyMapDesign.calmGreen
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if let closingDate = details.statementClosingDate {
                        BillDetailRow(
                            title: "Statement Closes",
                            value: MoneyMapFormatters.mediumDateString(for: closingDate),
                            systemImage: "calendar",
                            tint: .orange
                        )
                    }

                    if let promoDate = details.promoAPRExpiration {
                        BillDetailRow(
                            title: "Promo APR Ends",
                            value: MoneyMapFormatters.mediumDateString(for: promoDate),
                            systemImage: "calendar.badge.exclamationmark",
                            tint: .red
                        )
                    }
                }
                .padding()
                .background(MoneyMapDesign.surfaceBackground)
                .clipShape(.rect(cornerRadius: MoneyMapDesign.sectionCornerRadius))
            }
        }
    }

    private var bankSyncDetailText: String {
        if let updatedAt = bill.plaidUpdatedAt {
            return "Linked \(updatedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Linked"
    }
    
    private var recurrenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Schedule", systemImage: "calendar")
                .font(.headline)

            Divider()

            BillDetailRow(
                title: "Due Date",
                value: dueDateText,
                systemImage: "calendar",
                tint: bill.displayStatusColor
            )
            BillDetailRow(
                title: "Recurrence",
                value: recurrenceText,
                systemImage: "repeat",
                tint: .blue
            )
        }
        .padding()
        .background(MoneyMapDesign.surfaceBackground)
        .clipShape(.rect(cornerRadius: MoneyMapDesign.sectionCornerRadius))
    }

    private var paymentSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BillSectionHeader(
                title: "Payment",
                systemImage: bill.paymentModeIcon,
                actionTitle: "Change",
                action: { showingPaymentSettings = true }
            )

            Divider()

            BillSummaryLine(
                title: bill.paymentModeTitle,
                value: paymentMethodSummaryText,
                systemImage: selectedPaymentMethod?.type.icon ?? "wallet.pass",
                tint: paymentMode == .autopay || paymentMode == .inPerson ? MoneyMapDesign.calmGreen : .secondary
            )

            BillSummaryLine(
                title: paymentTrackingTitle,
                value: paymentTrackingStatusText,
                systemImage: paymentTrackingIcon,
                tint: paymentTrackingTint
            )

            BillSummaryLine(
                title: "Grace Period",
                value: "\(gracePeriodDays) day\(gracePeriodDays == 1 ? "" : "s")",
                systemImage: "calendar.badge.clock",
                tint: MoneyMapDesign.warningGold
            )
        }
        .padding()
        .background(MoneyMapDesign.surfaceBackground)
        .clipShape(.rect(cornerRadius: MoneyMapDesign.sectionCornerRadius))
    }

    private var scheduleSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BillSectionHeader(
                title: "Schedule",
                systemImage: "calendar",
                actionTitle: "Manage",
                action: { showingScheduleManager = true }
            )

            Divider()

            BillSummaryLine(
                title: "Due",
                value: dueDateText,
                systemImage: "calendar",
                tint: bill.displayStatusColor
            )

            BillSummaryLine(
                title: "Repeats",
                value: recurrenceText,
                systemImage: "repeat",
                tint: .blue
            )

            BillSummaryLine(
                title: "Status",
                value: bill.lifecycleState.title,
                systemImage: bill.lifecycleState.icon,
                tint: bill.lifecycleState.color
            )
        }
        .padding()
        .background(MoneyMapDesign.surfaceBackground)
        .clipShape(.rect(cornerRadius: MoneyMapDesign.sectionCornerRadius))
    }

    private var transactionSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BillSectionHeader(
                title: "History",
                systemImage: "list.bullet.rectangle",
                actionTitle: "Connect",
                action: { showingTransactionLinker = true }
            )

            Divider()

            if displayTransactions.isEmpty {
                Text("No transactions are connected to this bill yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(previewTransactions, id: \.self) { transaction in
                    BillHistoryPreviewRow(transaction: transaction)
                }

                if filteredAndSortedTransactions.count > 3 {
                    Text("+ \(filteredAndSortedTransactions.count - 3) more")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                transactionList
            } label: {
                MoneyMapActionCardLabel(
                    title: "View History",
                    detail: transactionSummaryText,
                    systemImage: "clock.arrow.circlepath",
                    tint: .blue
                )
            }
            .buttonStyle(.plain)
            .disabled(displayTransactions.isEmpty)
        }
        .padding()
        .background(MoneyMapDesign.surfaceBackground)
        .clipShape(.rect(cornerRadius: MoneyMapDesign.sectionCornerRadius))
    }

    private var billMetaSection: some View {
        VStack(alignment: .leading, spacing: MoneyMapDesign.sectionSpacing) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Payment Settings", systemImage: "gearshape")
                    .font(.headline)

                Divider()

                Picker("Payment Type", selection: $paymentMode) {
                    ForEach(BillPaymentMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                .onChange(of: paymentMode) { _, mode in
                    autopayEnabled = mode == .autopay
                    if mode != .autopay {
                        autopaySource = ""
                        selectedPaymentMethodID = nil
                    }
                    saveBillMeta()
                }
                .padding(12)
                .background(MoneyMapDesign.controlBackground, in: RoundedRectangle(cornerRadius: MoneyMapDesign.controlCornerRadius, style: .continuous))

                if paymentMode == .autopay {
                    Menu {
                        Picker("Pay From", selection: $selectedPaymentMethodID) {
                            Text("No Payment Method").tag(Optional<UUID>.none)
                            ForEach(sortedPaymentMethods) { method in
                                Label(method.displayName, systemImage: method.type.icon)
                                    .tag(Optional(method.id))
                            }
                        }
                    } label: {
                        MoneyMapActionCardLabel(
                            title: selectedPaymentMethodTitle,
                            detail: selectedPaymentMethodDetail,
                            systemImage: selectedPaymentMethodIcon,
                            tint: selectedPaymentMethodTint,
                            trailingSystemImage: "chevron.up.chevron.down"
                        )
                    }
                    .onChange(of: selectedPaymentMethodID) { _, _ in
                        saveBillMeta()
                    }
                    .buttonStyle(.plain)

                    paymentMethodActionGrid

                    if selectedPaymentMethod == nil {
                        HStack {
                            Text("Autopay Source")
                            Spacer(minLength: 12)
                            TextField("Checking Account", text: $autopaySource)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                                .onSubmit(saveBillMeta)
                                .onChange(of: autopaySource) { _, _ in
                                    saveBillMeta()
                                }
                        }
                    }
                }

                Stepper(
                    "Grace Period: \(gracePeriodDays) day\(gracePeriodDays == 1 ? "" : "s")",
                    value: $gracePeriodDays,
                    in: 0...31
                )
                .padding(12)
                .background(MoneyMapDesign.controlBackground, in: RoundedRectangle(cornerRadius: MoneyMapDesign.controlCornerRadius, style: .continuous))
                .onChange(of: gracePeriodDays) { _, _ in
                    saveBillMeta()
                }

                if shouldShowPlaidUnavailableToggle {
                    Divider()

                    Toggle("Not Available in Plaid", isOn: $plaidUnavailable)
                        .onChange(of: plaidUnavailable) { _, _ in
                            saveBillMeta()
                        }

                    Text("MoneyMap will keep this card manual and skip upgrade prompts for it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(MoneyMapDesign.surfaceBackground)
            .clipShape(.rect(cornerRadius: MoneyMapDesign.sectionCornerRadius))

            if bill.paymentMode == .payLink {
                PaymentLinkSummaryCard(
                    bill: bill,
                    openPaymentLink: { url in
                        openURL(url)
                    },
                    configurePaymentLink: {
                        showingPaymentLinkSetup = true
                    }
                )
            }

            if let notes = bill.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(.headline)
                    Text(notes)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(MoneyMapDesign.surfaceBackground)
                .clipShape(.rect(cornerRadius: MoneyMapDesign.sectionCornerRadius))
            }
        }
        .onDisappear {
            saveBillMeta()
        }
    }

    private var paymentPlaceholder: String {
        if let payment = bill.creditCardDetails?.recommendedPayment {
            return "Recommended: \(payment.currency)"
        }
        return "Enter Payment"
    }

    private var paymentAlertTitle: String {
        bill.name ?? "Payment Amount"
    }

    private var defaultScheduleDate: Date {
        let calendar = Calendar.current
        return bill.nextOccurrenceDate(calendar: calendar) ??
            calendar.date(byAdding: .day, value: 7, to: bill.dueDate ?? .now) ??
            .now
    }

    private func recordPayment() {
        let normalized = paymentAmount.replacingOccurrences(of: ",", with: "")
        let amount = Double(normalized) ?? 0
        guard amount > 0 else {
            importErrorMessage = "Enter a valid payment amount greater than zero."
            importErrorAlert = true
            return
        }

        let previousBalance = bill.creditCardDetails?.cardBalance
        let previousDatePaid = bill.datePaid
        let previousDueDate = bill.dueDate
        let previousStatus = bill.status

        bill.makePayment(of: amount)
        AuditService.logBillPayment(
            bill: bill,
            previousBalance: previousBalance,
            previousDatePaid: previousDatePaid,
            previousDueDate: previousDueDate,
            previousStatus: previousStatus,
            amount: amount,
            context: modelContext
        )
        try? modelContext.save()
        AppRefreshEvents.notifyBillsDidChange()
        paymentAmount.removeAll()
    }

    private func markPaid() {
        let previousBalance = bill.creditCardDetails?.cardBalance
        let previousDatePaid = bill.datePaid
        let previousDueDate = bill.dueDate
        let previousStatus = bill.status

        bill.datePaid = .now
        bill.status = .paid
        bill.checkStatus()

        AuditService.logBillPayment(
            bill: bill,
            previousBalance: previousBalance,
            previousDatePaid: previousDatePaid,
            previousDueDate: previousDueDate,
            previousStatus: previousStatus,
            amount: bill.amount ?? 0,
            context: modelContext
        )
        try? modelContext.save()
        AppRefreshEvents.notifyBillsDidChange()
    }

    private func updatePaymentDate(_ date: Date) {
        bill.datePaid = date
        bill.status = .paid
        saveBillState()
    }

    private func clearPaymentDate() {
        bill.datePaid = nil
        bill.checkStatus()
        saveBillState()
    }

    private func deleteBill() {
        modelContext.delete(bill)
        do {
            try modelContext.save()
            AppRefreshEvents.notifyBillsDidChange()
            dismiss()
        } catch {
            importErrorMessage = "Could not delete this bill: \(error.localizedDescription)"
            importErrorAlert = true
        }
    }

    private func delayBill(to date: Date) {
        bill.delay(to: date)
        saveScheduleChange()
    }

    private func skipBill() {
        bill.skipNextOccurrence()
        saveScheduleChange()
    }

    private func pauseBill() {
        bill.pause()
        saveScheduleChange()
    }

    private func cancelBill() {
        bill.cancel()
        saveScheduleChange()
    }

    private func resumeBill(on date: Date) {
        bill.resume(nextDueDate: date)
        saveScheduleChange()
    }

    private func presentScheduleResumeFromManager() {
        showingScheduleManager = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showingScheduleResume = true
        }
    }

    private func saveScheduleChange() {
        do {
            try modelContext.save()
            AppRefreshEvents.notifyBillsDidChange()
        } catch {
            importErrorMessage = "Could not update this bill: \(error.localizedDescription)"
            importErrorAlert = true
        }
    }

    private func saveBillState() {
        do {
            try modelContext.save()
            AppRefreshEvents.notifyBillsDidChange()
        } catch {
            importErrorMessage = "Could not update this bill: \(error.localizedDescription)"
            importErrorAlert = true
        }
    }

    private var canManuallyMarkPaid: Bool {
        bill.lifecycleState == .active &&
            bill.status != .paid &&
            bill.paymentMode != .autopay &&
            bill.paymentMode != .inPerson
    }

    private func loadBillMeta() {
        paymentMode = bill.paymentMode
        autopayEnabled = bill.autopayEnabled
        autopaySource = bill.autopaySource ?? ""
        selectedPaymentMethodID = bill.paymentMethodID
        gracePeriodDays = bill.gracePeriodDays ?? 0
        plaidUnavailable = bill.plaidUnavailable
    }

    private func presentPendingSetupActionIfNeeded() {
        guard let action = pendingSetupAction else { return }
        pendingSetupAction = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            switch action {
            case .editBill:
                showingBillEditor = true
            case .paymentSettings:
                showingPaymentSettings = true
            case .paymentLink:
                showingPaymentLinkSetup = true
            case .transactionLinking:
                showingTransactionLinker = true
            case .recordPayment:
                if bill.category == .creditCard {
                    paymentAmount = ""
                    makingPayment = true
                } else if canManuallyMarkPaid {
                    showMarkPaidConfirmation = true
                }
            case .openPaymentLink:
                if let paymentURL = bill.paymentURL {
                    openURL(paymentURL)
                } else {
                    showingPaymentLinkSetup = true
                }
            }
        }
    }

    private func saveBillMeta() {
        let normalizedAutopaySource = autopaySource.trimmingCharacters(in: .whitespacesAndNewlines)
        bill.updatePaymentSettings(
            autopayEnabled: paymentMode == .autopay,
            paymentMethodID: paymentMode == .autopay ? selectedPaymentMethodID : nil,
            autopaySource: normalizedAutopaySourceForSave(fallback: normalizedAutopaySource),
            gracePeriodDays: gracePeriodDays,
            paymentMode: paymentMode
        )
        bill.plaidUnavailable = shouldShowPlaidUnavailableToggle && plaidUnavailable
        bill.checkStatus()
        do {
            try modelContext.save()
            AppRefreshEvents.notifyBillsDidChange()
        } catch {
            importErrorMessage = "Could not update bill settings: \(error.localizedDescription)"
            importErrorAlert = true
        }
    }

    private var sortedPaymentMethods: [PaymentMethod] {
        paymentMethods.sorted {
            if $0.type == $1.type {
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            return $0.type.name < $1.type.name
        }
    }

    private var selectedPaymentMethod: PaymentMethod? {
        guard let selectedPaymentMethodID else { return nil }
        return paymentMethods.first { $0.id == selectedPaymentMethodID }
    }

    private var selectedPaymentMethodTitle: String {
        selectedPaymentMethod?.displayName ?? "No Payment Method"
    }

    private var selectedPaymentMethodDetail: String {
        selectedPaymentMethod?.detailText ?? "Choose the account or method used to pay this bill."
    }

    private var selectedPaymentMethodIcon: String {
        selectedPaymentMethod?.type.icon ?? "wallet.pass"
    }

    private var selectedPaymentMethodTint: Color {
        selectedPaymentMethod?.type.color ?? .secondary
    }

    private var paymentMethodSummaryText: String {
        if paymentMode == .inPerson {
            return displayTransactions.isEmpty
                ? "Connect matching history to teach MoneyMap"
                : "Watching matching synced transactions"
        }

        if paymentMode == .payLink {
            return bill.paymentHost ?? "Website or app"
        }

        if let selectedPaymentMethod {
            return selectedPaymentMethod.detailText == selectedPaymentMethod.type.name
                ? selectedPaymentMethod.displayName
                : "\(selectedPaymentMethod.displayName) - \(selectedPaymentMethod.detailText)"
        }

        let trimmedSource = autopaySource.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSource.isEmpty ? "No payment method" : trimmedSource
    }

    private var paymentTrackingTitle: String {
        paymentMode == .inPerson ? "Transaction Match" : "Payment Link"
    }

    private var paymentTrackingStatusText: String {
        if paymentMode == .inPerson {
            return displayTransactions.isEmpty ? "Needs one connected transaction" : transactionSummaryText
        }

        return paymentLinkStatusText
    }

    private var paymentTrackingIcon: String {
        if paymentMode == .inPerson {
            return displayTransactions.isEmpty ? "link.badge.plus" : "checkmark.circle"
        }

        return bill.paymentURL == nil ? "link.badge.plus" : "link"
    }

    private var paymentTrackingTint: Color {
        if paymentMode == .inPerson {
            return displayTransactions.isEmpty ? MoneyMapDesign.warningGold : MoneyMapDesign.calmGreen
        }

        return bill.paymentURL == nil ? MoneyMapDesign.warningGold : .blue
    }

    private var paymentLinkStatusText: String {
        if bill.paymentURL != nil {
            return bill.paymentHost ?? "App link"
        }

        if let rawValue = bill.paymentURLString, !rawValue.isEmpty {
            return "Needs attention"
        }

        return "Not set"
    }

    private var paymentMethodActionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8, alignment: .top)], spacing: 8) {
            Button {
                showingPaymentMethodEditor = true
            } label: {
                MoneyMapActionCardLabel(
                    title: "Add Manual",
                    detail: "Create a saved payment method.",
                    systemImage: "plus.circle",
                    tint: MoneyMapDesign.calmGreen
                )
            }
            .buttonStyle(.plain)

            Button {
                showingPlaidPaymentMethodSelector = true
            } label: {
                MoneyMapActionCardLabel(
                    title: "Connect Plaid",
                    detail: "Use a synced bank account.",
                    systemImage: "link",
                    tint: .blue
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func createPaymentMethodFromPlaidAccount(_ account: PlaidAccountValue) {
        if let existing = paymentMethods.first(where: { $0.plaidAccountID == account.accountID }) {
            selectedPaymentMethodID = existing.id
            saveBillMeta()
            return
        }

        let paymentMethod = PaymentMethod(
            name: account.displayName,
            type: paymentMethodType(forPlaidAccount: account),
            institutionName: account.institutionName,
            lastFourDigits: account.mask,
            plaidAccountID: account.accountID,
            plaidItemID: account.itemID,
            plaidUpdatedAt: .now
        )
        modelContext.insert(paymentMethod)
        selectedPaymentMethodID = paymentMethod.id
        saveBillMeta()
    }

    private func linkTransactionToBill(_ transaction: Transaction) {
        let matchingTransactions = transactionsMatchingRawName(of: transaction, in: allTransactionsIncluding(transaction))
            .filter { isAvailableForBillConnection($0) || BillPaymentMatcher.isConnected($0, to: bill) }

        if matchingTransactions.isEmpty {
            connectTransactionToBill(transaction)
        } else {
            matchingTransactions.forEach(connectTransactionToBill)
        }

        saveLinkedTransactionChange()
    }

    private func connectTransactionToBill(_ transaction: Transaction) {
        if bill.category != .creditCard,
           transaction.creditCard?.category == .creditCard,
           transaction.creditCard?.id != bill.id {
            transaction.linkedBillID = bill.id
        } else {
            transaction.creditCard = bill
            transaction.linkedBillID = nil
        }
    }

    private func isAvailableForBillConnection(_ transaction: Transaction) -> Bool {
        if let linkedBillID = transaction.linkedBillID, linkedBillID != bill.id {
            return false
        }

        guard let owner = transaction.creditCard else {
            return true
        }

        return owner.id == bill.id || owner.category == .creditCard
    }

    private func allTransactionsIncluding(_ transaction: Transaction) -> [Transaction] {
        do {
            var fetchedTransactions = try modelContext.fetch(FetchDescriptor<Transaction>())
            let selectedKey = BillPaymentMatcher.identityKey(for: transaction)
            if !fetchedTransactions.contains(where: { BillPaymentMatcher.identityKey(for: $0) == selectedKey }) {
                fetchedTransactions.append(transaction)
            }
            return fetchedTransactions
        } catch {
            importErrorMessage = "Could not load matching transactions: \(error.localizedDescription)"
            importErrorAlert = true
            return [transaction]
        }
    }

    private func unlinkTransactionFromBill(_ transaction: Transaction) {
        guard BillPaymentMatcher.isConnected(transaction, to: bill) else { return }

        if transaction.linkedBillID == bill.id {
            transaction.linkedBillID = nil
        }
        if transaction.creditCard?.id == bill.id {
            transaction.creditCard = nil
        }

        saveLinkedTransactionChange()
    }

    private func saveLinkedTransactionChange() {
        do {
            try modelContext.save()
            refreshDisplayTransactions()
            refreshBillStatusFromTransactions()
            AppRefreshEvents.notifyBillsDidChange()
        } catch {
            importErrorMessage = "Could not update transaction history: \(error.localizedDescription)"
            importErrorAlert = true
        }
    }

    private func paymentMethodType(forPlaidAccount account: PlaidAccountValue) -> PaymentMethodType {
        switch account.subtype ?? account.type {
        case "credit card":
            return .creditCard
        case "savings", "money market":
            return .savings
        case "checking":
            return .checking
        default:
            switch account.type {
            case "credit":
                return .creditCard
            case "depository":
                return .checking
            default:
                return .other
            }
        }
    }

    private func normalizedAutopaySourceForSave(fallback: String) -> String? {
        guard paymentMode == .autopay else { return nil }
        if let selectedPaymentMethod {
            return selectedPaymentMethod.displayName
        }
        return fallback.isEmpty ? nil : fallback
    }

    private var shouldShowPlaidUnavailableToggle: Bool {
        bill.category == .creditCard && (bill.plaidAccountID ?? "").isEmpty
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
            return creditCardDetails.utilization >= 0.3
        }
        
        return false
    }
    
    var utilizationIcon: some View {
        HStack {
            if let creditCardDetails = bill.creditCardDetails {
                
                let above = creditCardDetails.utilization >= 0.3
                
                if above {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                
                Text(creditCardDetails.utilization, format: .percent.precision(.fractionLength(0)))
                
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .foregroundStyle(.gray)
                Text("N/A")
            }
        }
    }
}

private func rawTransactionName(for transaction: Transaction) -> String? {
    [
        transaction.transactionDescription,
        transaction.merchant
    ]
    .compactMap { value -> String? in
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
    .first
}

private func transactionsMatchingRawName(
    of transaction: Transaction,
    in transactions: [Transaction]
) -> [Transaction] {
    guard let rawName = rawTransactionName(for: transaction) else {
        return [transaction]
    }

    return transactions.filter {
        rawTransactionName(for: $0)?.caseInsensitiveCompare(rawName) == .orderedSame
    }
}

private struct BillDetailAction: Identifiable {
    enum Style: Equatable {
        case prominent
        case secondary
    }

    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    var style: Style = .secondary
    var role: ButtonRole?
    let handler: () -> Void

    var id: String {
        "\(title)-\(systemImage)"
    }
}

private struct BillDetailActionButton: View {
    let action: BillDetailAction

    var body: some View {
        Button(role: action.role) {
            action.handler()
        } label: {
            MoneyMapActionCardLabel(
                title: action.title,
                detail: action.detail,
                systemImage: action.systemImage,
                tint: action.tint,
                isProminent: action.style == .prominent
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

private struct BillHeaderMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct BillStatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private struct BillDetailRow: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

private struct BillSectionHeader: View {
    let title: String
    let systemImage: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            Spacer(minLength: 8)

            Button(actionTitle, action: action)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

private struct BillSummaryLine: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

private struct BillHistoryPreviewRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(MoneyMapDesign.calmGreen)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(transactionTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(transactionSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let amount = transaction.amountUSD {
                Text(MoneyMapFormatters.currencyString(for: amount))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var transactionTitle: String {
        transaction.friendlyName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ??
            transaction.merchant?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ??
            transaction.transactionDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ??
            "Transaction"
    }

    private var transactionSubtitle: String {
        [
            transaction.transactionDate.map(MoneyMapFormatters.mediumDateString(for:)),
            transaction.category?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
    }
}

private struct BillPaymentSettingsSheet<PaymentSettingsContent: View>: View {
    let bill: Bill
    let paymentSettingsContent: () -> PaymentSettingsContent

    @Environment(\.dismiss) private var dismiss

    init(
        bill: Bill,
        @ViewBuilder paymentSettingsContent: @escaping () -> PaymentSettingsContent
    ) {
        self.bill = bill
        self.paymentSettingsContent = paymentSettingsContent
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MoneyMapDesign.sectionSpacing) {
                    paymentSettingsContent()
                }
                .padding()
            }
            .background(MoneyMapDesign.groupedBackground)
            .navigationTitle("Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct BillScheduleManagerSheet<RecurrenceContent: View>: View {
    let bill: Bill
    let recurrenceContent: () -> RecurrenceContent
    let delay: (Date) -> Void
    let skip: () -> Void
    let pause: () -> Void
    let cancel: () -> Void
    let resume: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        bill: Bill,
        @ViewBuilder recurrenceContent: @escaping () -> RecurrenceContent,
        delay: @escaping (Date) -> Void,
        skip: @escaping () -> Void,
        pause: @escaping () -> Void,
        cancel: @escaping () -> Void,
        resume: @escaping () -> Void
    ) {
        self.bill = bill
        self.recurrenceContent = recurrenceContent
        self.delay = delay
        self.skip = skip
        self.pause = pause
        self.cancel = cancel
        self.resume = resume
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MoneyMapDesign.sectionSpacing) {
                    recurrenceContent()

                    if bill.category != .creditCard {
                        BillLifecycleCard(
                            bill: bill,
                            delay: delay,
                            skip: skip,
                            pause: pause,
                            cancel: cancel,
                            resume: resume
                        )
                    }
                }
                .padding()
            }
            .background(MoneyMapDesign.groupedBackground)
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct BillTransactionLinkingView: View {
    let bill: Bill
    let linkTransaction: (Transaction) -> Void
    let unlinkTransaction: (Transaction) -> Void
    private let plaidContainer: ModelContainer

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Transaction.transactionDate, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \PlaidAccountSnapshot.accountName) private var plaidAccounts: [PlaidAccountSnapshot]
    @State private var plaidAccountSnapshots: [PlaidAccountValue] = []
    @State private var searchText = ""
    @State private var selectedSourceFilterID: String?
    @State private var dateFilter: BillTransactionDateFilter = .any
    @State private var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customEndDate = Date()
    @State private var amountFilter: BillTransactionAmountFilter = .any
    @State private var minimumAmountText = ""
    @State private var maximumAmountText = ""
    @State private var sortField: BillTransactionLinkSortField = .date
    @State private var sortOrder: BillTransactionLinkSortOrder = .descending
    @State private var showingFilterSheet = false
    @State private var showingFriendlyNamePrompt = false
    @State private var pendingFriendlyName = ""
    @State private var transactionForFriendlyName: Transaction?
    @State private var matchPrefix = false
    @State private var prefixSearchText = ""

    init(
        bill: Bill,
        linkTransaction: @escaping (Transaction) -> Void,
        unlinkTransaction: @escaping (Transaction) -> Void
    ) {
        self.bill = bill
        self.linkTransaction = linkTransaction
        self.unlinkTransaction = unlinkTransaction

        do {
            plaidContainer = try PlaidSyncContainerFactory.make()
        } catch {
            plaidContainer = PlaidSyncContainerFactory.makeInMemory(fallbackReason: "Transaction filters could not open the Plaid sync store: \(error.localizedDescription)")
        }
    }

    private var linkedTransactions: [Transaction] {
        sorted(filtered(rawLinkedTransactions))
    }

    private var suggestedTransactions: [Transaction] {
        let linkedKeys = Set(rawLinkedTransactions.map(BillPaymentMatcher.identityKey(for:)))
        return BillPaymentMatcher.matchedHistoryTransactions(for: bill, in: transactions)
            .filter { isAvailableForBillConnection($0) }
            .filter { !BillPaymentMatcher.isConnected($0, to: bill) }
            .filter { !linkedKeys.contains(BillPaymentMatcher.identityKey(for: $0)) }
    }

    private var availableTransactions: [Transaction] {
        let excludedKeys = Set((rawLinkedTransactions + suggestedTransactions).map(BillPaymentMatcher.identityKey(for:)))
        return sorted(transactions)
            .filter { transaction in
                isAvailableForBillConnection(transaction) &&
                    !BillPaymentMatcher.isConnected(transaction, to: bill) &&
                    !excludedKeys.contains(BillPaymentMatcher.identityKey(for: transaction))
            }
            .filter(matchesFilters)
    }

    private var filteredSuggestedTransactions: [Transaction] {
        sorted(filtered(suggestedTransactions))
    }

    private var rawLinkedTransactions: [Transaction] {
        BillPaymentMatcher.connectedTransactions(for: bill, in: transactions)
    }

    private var allCandidateTransactions: [Transaction] {
        var seenKeys = Set<String>()
        return (rawLinkedTransactions + suggestedTransactions + rawAvailableTransactions)
            .filter { seenKeys.insert(BillPaymentMatcher.identityKey(for: $0)).inserted }
    }

    private var rawAvailableTransactions: [Transaction] {
        let excludedKeys = Set((rawLinkedTransactions + suggestedTransactions).map(BillPaymentMatcher.identityKey(for:)))
        return transactions.filter { transaction in
            isAvailableForBillConnection(transaction) &&
                !BillPaymentMatcher.isConnected(transaction, to: bill) &&
                !excludedKeys.contains(BillPaymentMatcher.identityKey(for: transaction))
        }
    }

    private var hasActiveFilters: Bool {
        selectedSourceFilterID != nil ||
            dateFilter != .any ||
            amountFilter != .any ||
            !minimumAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !maximumAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var activeFilterSummary: String {
        let parts = [
            sourceFilterSummary,
            dateFilter.summary(
                bill: bill,
                customStartDate: customStartDate,
                customEndDate: customEndDate
            ),
            amountFilter.summary(
                bill: bill,
                minimumAmount: parsedAmount(minimumAmountText),
                maximumAmount: parsedAmount(maximumAmountText)
            )
        ]
        .compactMap { $0 }

        return parts.isEmpty ? "No filters" : parts.joined(separator: " - ")
    }

    private var sourceFilterSummary: String? {
        guard let selectedSourceFilterID else { return nil }
        return sourceFilterOptions.first { $0.id == selectedSourceFilterID }?.title ?? "Selected Source"
    }

    private var sourceFilterOptions: [BillTransactionSourceFilterOption] {
        var options: [BillTransactionSourceFilterOption] = []
        let candidates = allCandidateTransactions

        let referencedAccountIDs = Set(candidates.compactMap { $0.plaidAccountID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty })
        let knownPlaidAccounts = allKnownPlaidAccounts
        options.append(contentsOf: knownPlaidAccounts.map { account in
            BillTransactionSourceFilterOption(
                id: "plaid:\(account.accountID)",
                title: accountFilterTitle(for: account),
                subtitle: accountFilterSubtitle(for: account),
                groupTitle: accountFilterGroupTitle(for: account),
                systemImage: accountSystemImage(for: account)
            )
        })

        let knownAccountIDs = Set(knownPlaidAccounts.map(\.accountID))
        let orphanAccountIDs = referencedAccountIDs.subtracting(knownAccountIDs)
        options.append(contentsOf: orphanAccountIDs.sorted().map { accountID in
            BillTransactionSourceFilterOption(
                id: "plaid:\(accountID)",
                title: orphanPlaidAccountTitle(for: accountID),
                subtitle: nil,
                groupTitle: "Bank Accounts",
                systemImage: "building.columns"
            )
        })

        let cardTransactions = transactions.compactMap { transaction -> Bill? in
            guard let card = transaction.creditCard, card.category == .creditCard else { return nil }
            return card
        }
        var seenCardIDs = Set<UUID>()
        options.append(contentsOf: cardTransactions
            .filter { seenCardIDs.insert($0.id).inserted }
            .sorted {
                ($0.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Card")
                    .localizedCaseInsensitiveCompare($1.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Card") == .orderedAscending
            }
            .map { card in
                BillTransactionSourceFilterOption(
                    id: "card:\(card.id.uuidString)",
                    title: card.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Card",
                    subtitle: card.creditCardDetails?.issuerName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    groupTitle: "Cards",
                    systemImage: "creditcard"
                )
            })

        let purchasedByValues = Set(candidates.compactMap { $0.purchasedBy?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty })
        options.append(contentsOf: purchasedByValues.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { value in
            BillTransactionSourceFilterOption(
                id: "source:\(value.lowercased())",
                title: value,
                subtitle: "Imported source",
                groupTitle: "Import Sources",
                systemImage: "wallet.pass"
            )
        })

        if candidates.contains(where: { $0.plaidAccountID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty == nil }) {
            options.append(
                BillTransactionSourceFilterOption(
                    id: "no-plaid-account",
                    title: "No Bank Account",
                    subtitle: nil,
                    groupTitle: "Other",
                    systemImage: "building.columns"
                )
            )
        }

        var seenIDs = Set<String>()
        return options.filter { seenIDs.insert($0.id).inserted }
    }

    var body: some View {
        NavigationStack {
            List {
                if hasActiveFilters {
                    Section {
                        Label {
                            Text(activeFilterSummary)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .foregroundStyle(MoneyMapDesign.calmGreen)
                        }
                    } header: {
                        Text("Active Filters")
                    }
                    .listRowBackground(MoneyMapDesign.surfaceBackground)
                }

                if linkedTransactions.isEmpty && filteredSuggestedTransactions.isEmpty && availableTransactions.isEmpty {
                    MoneyMapEmptyState(
                        title: allCandidateTransactions.isEmpty ? "No Transactions" : "No Matches",
                        message: allCandidateTransactions.isEmpty
                            ? "Import or sync transactions first, then connect the payments that belong to this bill."
                            : "No transactions match the selected filters.",
                        systemImage: "list.bullet.rectangle"
                    )
                    .listRowBackground(MoneyMapDesign.surfaceBackground)
                }

                if !linkedTransactions.isEmpty {
                    Section("Connected") {
                        ForEach(linkedTransactions, id: \.self) { transaction in
                            BillTransactionCandidateRow(
                                transaction: transaction,
                                state: .connected,
                                sourceDetail: sourceDetail(for: transaction),
                                action: {
                                    unlinkTransaction(transaction)
                                },
                                renameAction: {
                                    beginFriendlyNameEdit(for: transaction)
                                }
                            )
                        }
                    }
                    .listRowBackground(MoneyMapDesign.surfaceBackground)
                }

                if !filteredSuggestedTransactions.isEmpty {
                    Section("Suggested") {
                        ForEach(filteredSuggestedTransactions, id: \.self) { transaction in
                            BillTransactionCandidateRow(
                                transaction: transaction,
                                state: .suggested,
                                sourceDetail: sourceDetail(for: transaction),
                                action: {
                                    linkTransaction(transaction)
                                },
                                renameAction: {
                                    beginFriendlyNameEdit(for: transaction)
                                }
                            )
                        }
                    }
                    .listRowBackground(MoneyMapDesign.surfaceBackground)
                }

                if !availableTransactions.isEmpty {
                    Section("All Transactions") {
                        ForEach(availableTransactions, id: \.self) { transaction in
                            BillTransactionCandidateRow(
                                transaction: transaction,
                                state: .available,
                                sourceDetail: sourceDetail(for: transaction),
                                action: {
                                    linkTransaction(transaction)
                                },
                                renameAction: {
                                    beginFriendlyNameEdit(for: transaction)
                                }
                            )
                        }
                    }
                    .listRowBackground(MoneyMapDesign.surfaceBackground)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MoneyMapDesign.groupedBackground)
            .navigationTitle("Connect History")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search transactions")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort by", selection: $sortField) {
                            ForEach(BillTransactionLinkSortField.allCases) { field in
                                Label(field.title, systemImage: field.systemImage).tag(field)
                            }
                        }

                        Picker("Order", selection: $sortOrder) {
                            ForEach(BillTransactionLinkSortOrder.allCases) { order in
                                Label(order.title, systemImage: order.systemImage).tag(order)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }

                    Button {
                        showingFilterSheet = true
                    } label: {
                        Label("Filters", systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingFriendlyNamePrompt) {
                FriendlyNameSheet(
                    isPresented: $showingFriendlyNamePrompt,
                    friendlyName: $pendingFriendlyName,
                    matchPrefix: $matchPrefix,
                    prefixSearchText: $prefixSearchText
                ) { saved in
                    handleFriendlyNameResult(saved: saved)
                }
            }
            .sheet(isPresented: $showingFilterSheet) {
                BillTransactionLinkFilterSheet(
                    selectedSourceFilterID: $selectedSourceFilterID,
                    dateFilter: $dateFilter,
                    customStartDate: $customStartDate,
                    customEndDate: $customEndDate,
                    amountFilter: $amountFilter,
                    minimumAmountText: $minimumAmountText,
                    maximumAmountText: $maximumAmountText,
                    sourceOptions: sourceFilterOptions,
                    bill: bill,
                    hasActiveFilters: hasActiveFilters,
                    activeFilterSummary: activeFilterSummary,
                    clearFilters: clearFilters
                )
            }
            .task {
                loadPlaidAccountSnapshots()
            }
            .onChange(of: plaidAccounts.map(\.accountID)) { _, _ in
                loadPlaidAccountSnapshots()
            }
        }
    }

    private func sorted(_ values: [Transaction]) -> [Transaction] {
        values.sorted { lhs, rhs in
            let isAscending = sortOrder == .ascending

            switch sortField {
            case .date:
                let lhsDate = BillPaymentMatcher.transactionDate(for: lhs) ?? .distantPast
                let rhsDate = BillPaymentMatcher.transactionDate(for: rhs) ?? .distantPast
                return isAscending ? lhsDate < rhsDate : lhsDate > rhsDate
            case .amount:
                let lhsAmount = abs(lhs.amountUSD ?? 0)
                let rhsAmount = abs(rhs.amountUSD ?? 0)
                if lhsAmount == rhsAmount {
                    return tieBreak(lhs: lhs, rhs: rhs, ascending: isAscending)
                }
                return isAscending ? lhsAmount < rhsAmount : lhsAmount > rhsAmount
            case .merchant:
                let result = transactionTitle(for: lhs).localizedCaseInsensitiveCompare(transactionTitle(for: rhs))
                if result == .orderedSame {
                    return tieBreak(lhs: lhs, rhs: rhs, ascending: isAscending)
                }
                return isAscending ? result == .orderedAscending : result == .orderedDescending
            case .source:
                let result = (sourceDetail(for: lhs) ?? "").localizedCaseInsensitiveCompare(sourceDetail(for: rhs) ?? "")
                if result == .orderedSame {
                    return tieBreak(lhs: lhs, rhs: rhs, ascending: isAscending)
                }
                return isAscending ? result == .orderedAscending : result == .orderedDescending
            }
        }
    }

    private func filtered(_ values: [Transaction]) -> [Transaction] {
        values.filter(matchesFilters)
    }

    private func matchesFilters(_ transaction: Transaction) -> Bool {
        matchesSearch(transaction) &&
            matchesSource(transaction) &&
            matchesDate(transaction) &&
            matchesAmount(transaction)
    }

    private func matchesSearch(_ transaction: Transaction) -> Bool {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return true }
        return transactionSearchText(transaction)
            .localizedCaseInsensitiveContains(trimmedSearch)
    }

    private func isAvailableForBillConnection(_ transaction: Transaction) -> Bool {
        if let linkedBillID = transaction.linkedBillID, linkedBillID != bill.id {
            return false
        }

        guard let owner = transaction.creditCard else {
            return true
        }

        return owner.id == bill.id || owner.category == .creditCard
    }

    private func matchesSource(_ transaction: Transaction) -> Bool {
        guard let selectedSourceFilterID else { return true }

        if selectedSourceFilterID == "no-plaid-account" {
            return transaction.plaidAccountID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty == nil
        }

        if selectedSourceFilterID.hasPrefix("plaid:") {
            let accountID = String(selectedSourceFilterID.dropFirst("plaid:".count))
            return transaction.plaidAccountID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty == accountID
        }

        if selectedSourceFilterID.hasPrefix("card:") {
            let cardID = String(selectedSourceFilterID.dropFirst("card:".count))
            return transaction.creditCard?.id.uuidString == cardID
        }

        if selectedSourceFilterID.hasPrefix("source:") {
            let source = String(selectedSourceFilterID.dropFirst("source:".count))
            return transaction.purchasedBy?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == source
        }

        return true
    }

    private func matchesDate(_ transaction: Transaction) -> Bool {
        guard let date = BillPaymentMatcher.transactionDate(for: transaction) else {
            return dateFilter == .any
        }

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        switch dateFilter {
        case .any:
            return true
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: .now)) ?? .distantPast
            return day >= start
        case .last90Days:
            let start = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: .now)) ?? .distantPast
            return day >= start
        case .dueWindow:
            guard let dueDate = bill.dueDate else { return true }
            let dueDay = calendar.startOfDay(for: dueDate)
            let start = calendar.date(byAdding: .day, value: -7, to: dueDay) ?? dueDay
            let end = calendar.date(byAdding: .day, value: max(bill.gracePeriodDays ?? 0, 7), to: dueDay) ?? dueDay
            return day >= start && day <= end
        case .custom:
            let start = min(calendar.startOfDay(for: customStartDate), calendar.startOfDay(for: customEndDate))
            let endBase = max(calendar.startOfDay(for: customStartDate), calendar.startOfDay(for: customEndDate))
            let end = calendar.date(byAdding: .day, value: 1, to: endBase) ?? endBase
            return day >= start && day < end
        }
    }

    private func matchesAmount(_ transaction: Transaction) -> Bool {
        guard let amount = transaction.amountUSD.map(abs) else {
            return amountFilter == .any
        }

        switch amountFilter {
        case .any:
            return true
        case .nearBillAmount:
            guard let billAmount = bill.amount.map(abs), billAmount > 0 else { return true }
            let tolerance = max(1.0, billAmount * 0.08)
            return abs(amount - billAmount) <= tolerance
        case .custom:
            if let minimumAmount = parsedAmount(minimumAmountText), amount < minimumAmount {
                return false
            }
            if let maximumAmount = parsedAmount(maximumAmountText), amount > maximumAmount {
                return false
            }
            return true
        }
    }

    private func transactionSearchText(_ transaction: Transaction) -> String {
        [
            transaction.friendlyName,
            transaction.merchant,
            transaction.transactionDescription,
            transaction.category,
            transaction.type,
            sourceDetail(for: transaction),
            transaction.amountUSD.map(MoneyMapFormatters.currencyString(for:)),
            BillPaymentMatcher.transactionDate(for: transaction).map(MoneyMapFormatters.mediumDateString(for:))
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private func transactionTitle(for transaction: Transaction) -> String {
        transaction.friendlyName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ??
            transaction.merchant?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ??
            transaction.transactionDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ??
            "Transaction"
    }

    private func sourceDetail(for transaction: Transaction) -> String? {
        plaidAccountDisplayName(for: transaction) ??
            transaction.creditCard?.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ??
            transaction.purchasedBy?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func plaidAccountDisplayName(for transaction: Transaction) -> String? {
        guard let plaidAccountID = transaction.plaidAccountID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }

        return plaidAccountValue(for: plaidAccountID).map(accountFilterLabel(for:)) ?? orphanPlaidAccountTitle(for: plaidAccountID)
    }

    private func plaidAccountValue(for accountID: String) -> PlaidAccountValue? {
        allKnownPlaidAccounts.first { $0.accountID == accountID }
    }

    private var allKnownPlaidAccounts: [PlaidAccountValue] {
        let localAccounts = plaidAccounts.map(PlaidAccountValue.init)
        var seenAccountIDs = Set<String>()
        return (plaidAccountSnapshots + localAccounts)
            .filter { seenAccountIDs.insert($0.accountID).inserted }
    }

    private func loadPlaidAccountSnapshots() {
        let context = ModelContext(plaidContainer)
        let syncAccounts = (try? context.fetch(FetchDescriptor<PlaidAccountSnapshot>())) ?? []
        let localAccounts = plaidAccounts.map(PlaidAccountValue.init)
        var seenAccountIDs = Set<String>()
        plaidAccountSnapshots = (syncAccounts.map(PlaidAccountValue.init) + localAccounts)
            .filter { seenAccountIDs.insert($0.accountID).inserted }
    }

    private func accountFilterLabel(for account: PlaidAccountValue) -> String {
        [
            account.institutionName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            accountFilterTitle(for: account),
            account.lastFourLabel
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
    }

    private func accountFilterTitle(for account: PlaidAccountValue) -> String {
        let title = [
            account.displayName
                .billViewReplacingLeadingPhrase(account.institutionName)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty,
            account.lastFourLabel
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
        return title.nilIfEmpty ?? account.displayName
    }

    private func accountFilterGroupTitle(for account: PlaidAccountValue) -> String {
        account.institutionName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Bank Accounts"
    }

    private func orphanPlaidAccountTitle(for accountID: String) -> String {
        "Account \(String(accountID.suffix(6)))"
    }

    private func accountFilterSubtitle(for account: PlaidAccountValue) -> String? {
        [
            account.subtype?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            account.type.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
        .nilIfEmpty
    }

    private func accountSystemImage(for account: PlaidAccountValue) -> String {
        switch account.subtype ?? account.type {
        case "credit card", "credit":
            return "creditcard"
        case "checking":
            return "building.columns"
        case "savings", "money market":
            return "banknote"
        default:
            return "wallet.pass"
        }
    }

    private func tieBreak(lhs: Transaction, rhs: Transaction, ascending: Bool) -> Bool {
        let lhsDate = BillPaymentMatcher.transactionDate(for: lhs) ?? .distantPast
        let rhsDate = BillPaymentMatcher.transactionDate(for: rhs) ?? .distantPast
        return ascending ? lhsDate < rhsDate : lhsDate > rhsDate
    }

    private func parsedAmount(_ text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned).map(abs)
    }

    private func clearFilters() {
        selectedSourceFilterID = nil
        dateFilter = .any
        amountFilter = .any
        minimumAmountText = ""
        maximumAmountText = ""
    }

    private func beginFriendlyNameEdit(for transaction: Transaction) {
        pendingFriendlyName = transaction.friendlyName ?? ""
        transactionForFriendlyName = transaction
        prefixSearchText = rawTransactionName(for: transaction) ?? transaction.merchant ?? ""
        showingFriendlyNamePrompt = true
    }

    private func handleFriendlyNameResult(saved: Bool) {
        defer {
            transactionForFriendlyName = nil
            pendingFriendlyName = ""
            matchPrefix = false
            prefixSearchText = ""
        }

        guard saved, let transaction = transactionForFriendlyName else {
            return
        }

        let normalizedFriendlyName = pendingFriendlyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingTransactions: [Transaction]
        if matchPrefix {
            let prefix = prefixSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prefix.isEmpty else { return }
            matchingTransactions = transactions.filter {
                guard let rawName = rawTransactionName(for: $0) else { return false }
                return rawName.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil
            }
        } else {
            matchingTransactions = transactionsMatchingRawName(of: transaction, in: transactions)
        }

        matchingTransactions.forEach { $0.friendlyName = normalizedFriendlyName }
        try? modelContext.save()
    }
}

private enum BillTransactionLinkSortField: String, CaseIterable, Identifiable {
    case date
    case amount
    case merchant
    case source

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: return "Date"
        case .amount: return "Amount"
        case .merchant: return "Merchant"
        case .source: return "Source"
        }
    }

    var systemImage: String {
        switch self {
        case .date: return "calendar"
        case .amount: return "dollarsign.circle"
        case .merchant: return "building.2"
        case .source: return "wallet.pass"
        }
    }
}

private enum BillTransactionLinkSortOrder: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ascending: return "Ascending"
        case .descending: return "Descending"
        }
    }

    var systemImage: String {
        switch self {
        case .ascending: return "arrow.up"
        case .descending: return "arrow.down"
        }
    }
}

private enum BillTransactionDateFilter: String, CaseIterable, Identifiable {
    case any
    case last30Days
    case last90Days
    case dueWindow
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any Date"
        case .last30Days: return "Last 30 Days"
        case .last90Days: return "Last 90 Days"
        case .dueWindow: return "Due Window"
        case .custom: return "Custom Range"
        }
    }

    func summary(bill: Bill, customStartDate: Date, customEndDate: Date) -> String? {
        switch self {
        case .any:
            return nil
        case .last30Days, .last90Days:
            return title
        case .dueWindow:
            if let dueDate = bill.dueDate {
                return "Around \(MoneyMapFormatters.mediumDateString(for: dueDate))"
            }
            return title
        case .custom:
            let start = min(customStartDate, customEndDate)
            let end = max(customStartDate, customEndDate)
            return "\(MoneyMapFormatters.mediumDateString(for: start)) to \(MoneyMapFormatters.mediumDateString(for: end))"
        }
    }
}

private enum BillTransactionAmountFilter: String, CaseIterable, Identifiable {
    case any
    case nearBillAmount
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any Amount"
        case .nearBillAmount: return "Near Bill Amount"
        case .custom: return "Custom Range"
        }
    }

    func summary(bill: Bill, minimumAmount: Double?, maximumAmount: Double?) -> String? {
        switch self {
        case .any:
            return nil
        case .nearBillAmount:
            if let amount = bill.amount {
                return "Near \(MoneyMapFormatters.currencyString(for: abs(amount)))"
            }
            return title
        case .custom:
            if let minimumAmount, let maximumAmount {
                return "\(MoneyMapFormatters.currencyString(for: minimumAmount)) to \(MoneyMapFormatters.currencyString(for: maximumAmount))"
            }
            if let minimumAmount {
                return "\(MoneyMapFormatters.currencyString(for: minimumAmount))+"
            }
            if let maximumAmount {
                return "Up to \(MoneyMapFormatters.currencyString(for: maximumAmount))"
            }
            return title
        }
    }
}

private struct BillTransactionSourceFilterOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let groupTitle: String
    let systemImage: String
}

private struct BillTransactionLinkFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedSourceFilterID: String?
    @Binding var dateFilter: BillTransactionDateFilter
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    @Binding var amountFilter: BillTransactionAmountFilter
    @Binding var minimumAmountText: String
    @Binding var maximumAmountText: String

    let sourceOptions: [BillTransactionSourceFilterOption]
    let bill: Bill
    let hasActiveFilters: Bool
    let activeFilterSummary: String
    let clearFilters: () -> Void

    private var groupedSourceOptions: [(title: String, options: [BillTransactionSourceFilterOption])] {
        let grouped = Dictionary(grouping: sourceOptions, by: \.groupTitle)
        return grouped
            .map { title, options in
                (
                    title,
                    options.sorted {
                        let result = $0.title.localizedCaseInsensitiveCompare($1.title)
                        if result == .orderedSame {
                            return ($0.subtitle ?? "").localizedCaseInsensitiveCompare($1.subtitle ?? "") == .orderedAscending
                        }
                        return result == .orderedAscending
                    }
                )
            }
            .sorted { lhs, rhs in
                sourceGroupSortOrder(lhs.title) < sourceGroupSortOrder(rhs.title)
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if hasActiveFilters {
                    Section {
                        Label {
                            Text(activeFilterSummary)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .foregroundStyle(MoneyMapDesign.calmGreen)
                        }
                    } header: {
                        Text("Active Filters")
                    }
                    .listRowBackground(MoneyMapDesign.surfaceBackground)
                }

                Section("Source") {
                    sourceFilterRow(
                        title: "All Sources",
                        subtitle: nil,
                        systemImage: "tray.full",
                        id: nil
                    )
                }
                .listRowBackground(MoneyMapDesign.surfaceBackground)

                ForEach(groupedSourceOptions, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.options) { option in
                            sourceFilterRow(
                                title: option.title,
                                subtitle: option.subtitle,
                                systemImage: option.systemImage,
                                id: option.id
                            )
                        }
                    }
                    .listRowBackground(MoneyMapDesign.surfaceBackground)
                }

                Section("Date") {
                    Picker("Date", selection: $dateFilter) {
                        ForEach(BillTransactionDateFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }

                    if dateFilter == .custom {
                        DatePicker("Start", selection: $customStartDate, displayedComponents: .date)
                        DatePicker("End", selection: $customEndDate, displayedComponents: .date)
                    }
                }
                .listRowBackground(MoneyMapDesign.surfaceBackground)

                Section {
                    Picker("Amount", selection: $amountFilter) {
                        ForEach(BillTransactionAmountFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }

                    if amountFilter == .custom {
                        TextField("Minimum", text: $minimumAmountText)
                            .keyboardType(.decimalPad)
                        TextField("Maximum", text: $maximumAmountText)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("Amount")
                } footer: {
                    if amountFilter == .nearBillAmount, let amount = bill.amount {
                        Text("Matches roughly \(MoneyMapFormatters.currencyString(for: abs(amount))).")
                    }
                }
                .listRowBackground(MoneyMapDesign.surfaceBackground)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MoneyMapDesign.groupedBackground)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        clearFilters()
                    }
                    .disabled(!hasActiveFilters)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sourceFilterRow(
        title: String,
        subtitle: String?,
        systemImage: String,
        id: String?
    ) -> some View {
        Button {
            selectedSourceFilterID = id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                if selectedSourceFilterID == id {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MoneyMapDesign.calmGreen)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sourceGroupSortOrder(_ title: String) -> String {
        switch title {
        case "Bank Accounts":
            return "000-\(title)"
        case "Cards":
            return "998-\(title)"
        case "Import Sources":
            return "999-\(title)"
        case "Other":
            return "zzzz-\(title)"
        default:
            return "100-\(title)"
        }
    }
}

private struct BillTransactionCandidateRow: View {
    enum State {
        case connected
        case suggested
        case available
    }

    let transaction: Transaction
    let state: State
    let sourceDetail: String?
    let action: () -> Void
    var renameAction: (() -> Void)?

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if let amount = transaction.amountUSD {
                    Text(MoneyMapFormatters.currencyString(for: amount))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 3)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .contextMenu {
            if let renameAction {
                Button("Rename Matching Transactions", systemImage: "text.badge.checkmark") {
                    renameAction()
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let renameAction {
                Button {
                    renameAction()
                } label: {
                    Label("Rename", systemImage: "text.badge.checkmark")
                }
                .tint(.blue)
            }
        }
    }

    private var systemImage: String {
        switch state {
        case .connected:
            return "checkmark.circle.fill"
        case .suggested:
            return "sparkle.magnifyingglass"
        case .available:
            return "plus.circle"
        }
    }

    private var tint: Color {
        switch state {
        case .connected:
            return MoneyMapDesign.calmGreen
        case .suggested:
            return .blue
        case .available:
            return .secondary
        }
    }

    private var title: String {
        transaction.friendlyName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ??
            transaction.merchant?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ??
            transaction.transactionDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ??
            "Transaction"
    }

    private var subtitle: String {
        [
            BillPaymentMatcher.transactionDate(for: transaction).map(MoneyMapFormatters.mediumDateString(for:)),
            transaction.category?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            sourceDetail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
    }
}

private struct BillDetailConfirmationDialogs: ViewModifier {
    let billName: String?
    @Binding var showingMarkPaid: Bool
    @Binding var showingDeleteBill: Bool
    @Binding var showingClearPayment: Bool
    let markPaid: () -> Void
    let deleteBill: () -> Void
    let clearPaymentDate: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Mark \(billName ?? "this bill") as paid?",
                isPresented: $showingMarkPaid,
                titleVisibility: .visible
            ) {
                Button("Mark Paid") {
                    markPaid()
                }
                Button("Cancel", role: .cancel) { }
            }
            .confirmationDialog(
                "Delete \(billName ?? "this bill")?",
                isPresented: $showingDeleteBill,
                titleVisibility: .visible
            ) {
                Button("Delete Bill", role: .destructive) {
                    deleteBill()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes the bill and its detail history from the app.")
            }
            .confirmationDialog(
                "Clear payment date?",
                isPresented: $showingClearPayment,
                titleVisibility: .visible
            ) {
                Button("Clear Payment Date", role: .destructive) {
                    clearPaymentDate()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This marks the bill unpaid again if the due date still needs attention.")
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
                    Text("By default this applies to every transaction with the same raw name.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Toggle("Apply to raw names that begin with this text", isOn: $matchPrefix)
                    if matchPrefix {
                        TextField("Prefix to match", text: $prefixSearchText)
                    }
                }
                .moneyMapListSectionBackground()
            }
            .moneyMapGroupedListBackground()
            .navigationTitle("Set Friendly Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem {
                    Button("Save", systemImage: "checkmark", role: .confirm) {
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func billViewReplacingLeadingPhrase(_ phrase: String?) -> String {
        guard let phrase = phrase?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return self
        }

        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.localizedCaseInsensitiveCompare(phrase) != .orderedSame else {
            return trimmed
        }

        let lowercasedTrimmed = trimmed.lowercased()
        let lowercasedPhrase = phrase.lowercased()
        guard lowercasedTrimmed.hasPrefix(lowercasedPhrase) else {
            return trimmed
        }

        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: phrase.count)
        let remainder = trimmed[startIndex...]
            .trimmingCharacters(in: CharacterSet(charactersIn: " -:/"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return remainder.isEmpty ? trimmed : remainder
    }
}

private struct PlaidPaymentMethodSelectorContainerView: View {
    let existingPaymentMethodAccountIDs: Set<String>
    let createPaymentMethod: (PlaidAccountValue) -> Void

    private let plaidContainer: ModelContainer

    init(
        existingPaymentMethodAccountIDs: Set<String>,
        createPaymentMethod: @escaping (PlaidAccountValue) -> Void
    ) {
        self.existingPaymentMethodAccountIDs = existingPaymentMethodAccountIDs
        self.createPaymentMethod = createPaymentMethod
        do {
            plaidContainer = try PlaidSyncContainerFactory.make()
        } catch {
            plaidContainer = PlaidSyncContainerFactory.makeInMemory(fallbackReason: "Could not open Plaid payment accounts: \(error.localizedDescription)")
        }
    }

    var body: some View {
        PlaidPaymentMethodSelectorView(
            existingPaymentMethodAccountIDs: existingPaymentMethodAccountIDs,
            createPaymentMethod: createPaymentMethod
        )
        .modelContainer(plaidContainer)
    }
}

private struct PlaidPaymentMethodSelectorView: View {
    let existingPaymentMethodAccountIDs: Set<String>
    let createPaymentMethod: (PlaidAccountValue) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PlaidAccountSnapshot.accountName) private var accounts: [PlaidAccountSnapshot]

    private var paymentAccounts: [PlaidAccountValue] {
        accounts
            .map(PlaidAccountValue.init)
            .filter { account in
                paymentMethodType(for: account) != .creditCard
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if paymentAccounts.isEmpty {
                    MoneyMapEmptyState(
                        title: "No Plaid Accounts",
                        message: "Refresh Bank Sync after connecting a checking or savings account.",
                        systemImage: "link"
                    )
                    .listRowBackground(MoneyMapDesign.surfaceBackground)
                } else {
                    Section("Synced Accounts") {
                        ForEach(paymentAccounts) { account in
                            Button {
                                createPaymentMethod(account)
                                dismiss()
                            } label: {
                                PlaidPaymentAccountRow(
                                    account: account,
                                    type: paymentMethodType(for: account),
                                    isAlreadySaved: existingPaymentMethodAccountIDs.contains(account.accountID)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(MoneyMapDesign.surfaceBackground)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MoneyMapDesign.groupedBackground)
            .navigationTitle("Connect Plaid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func paymentMethodType(for account: PlaidAccountValue) -> PaymentMethodType {
        switch account.subtype ?? account.type {
        case "credit card":
            return .creditCard
        case "savings", "money market":
            return .savings
        case "checking":
            return .checking
        default:
            switch account.type {
            case "credit":
                return .creditCard
            case "depository":
                return .checking
            default:
                return .other
            }
        }
    }
}

private struct PlaidPaymentAccountRow: View {
    let account: PlaidAccountValue
    let type: PaymentMethodType
    let isAlreadySaved: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .foregroundStyle(type.color)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(account.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if isAlreadySaved {
                Text("Saved")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MoneyMapDesign.calmGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(MoneyMapDesign.calmGreen.opacity(0.12), in: Capsule())
            } else {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(type.color)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var detailText: String {
        let parts = [
            account.institutionName,
            account.lastFourLabel,
            type.name
        ]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }

        return parts.joined(separator: " - ")
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

private struct CreditCardDataSourcesView: View {
    let bill: Bill
    private let plaidContainer: ModelContainer

    @Environment(\.dismiss) private var dismiss
    @State private var plaidAccount: PlaidAccountValue?
    @State private var loadErrorMessage: String?

    init(bill: Bill) {
        self.bill = bill
        do {
            plaidContainer = try PlaidSyncContainerFactory.make()
        } catch {
            plaidContainer = PlaidSyncContainerFactory.makeInMemory(fallbackReason: "Could not open Plaid card data: \(error.localizedDescription)")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                sourceSummarySection
                plaidSection
                manualSection
                calculatedSection
            }
            .navigationTitle("Data Sources")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(MoneyMapDesign.groupedBackground)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                loadPlaidAccount()
            }
        }
    }

    private var sourceSummarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(bill.name ?? "Credit Card", systemImage: "creditcard")
                    .font(.headline)
                Text(summaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } footer: {
            Text("This screen explains where card fields come from without adding labels to every number on the card view.")
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var plaidSection: some View {
        Section("From Plaid") {
            if bill.plaidAccountID == nil {
                DataSourceRow(title: "Bank Sync", value: "Not linked", systemImage: "link.slash", tint: .secondary)
            } else {
                DataSourceRow(title: "Institution", value: plaidAccount?.institutionName ?? bill.creditCardDetails?.issuerName ?? "Synced bank", systemImage: "building.columns", tint: MoneyMapDesign.calmGreen)
                DataSourceRow(title: "Account", value: plaidAccount?.displayName ?? "Linked card", systemImage: "creditcard", tint: MoneyMapDesign.calmGreen)
                DataSourceRow(title: "Current Balance", value: currentBalanceText, systemImage: "dollarsign.circle", tint: MoneyMapDesign.calmGreen)
                DataSourceRow(title: "Available Credit", value: availableCreditText, systemImage: "gauge.with.dots.needle.33percent", tint: MoneyMapDesign.calmGreen)
                DataSourceRow(title: "Last Four", value: lastFourText, systemImage: "number", tint: MoneyMapDesign.calmGreen)
                DataSourceRow(title: "Last Synced", value: plaidUpdatedText, systemImage: "clock.arrow.circlepath", tint: MoneyMapDesign.calmGreen)

                if let loadErrorMessage {
                    DataSourceRow(title: "Plaid Snapshot", value: loadErrorMessage, systemImage: "exclamationmark.triangle", tint: MoneyMapDesign.attentionRed)
                } else if plaidAccount == nil {
                    DataSourceRow(title: "Plaid Snapshot", value: "Linked account details will appear after the next bank refresh.", systemImage: "icloud.and.arrow.down", tint: .secondary)
                }
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var manualSection: some View {
        Section("Manual in MoneyMap") {
            if bill.plaidAccountID == nil {
                DataSourceRow(
                    title: "Plaid Upgrade",
                    value: bill.plaidUnavailable ? "Kept manual" : "Available to link",
                    systemImage: bill.plaidUnavailable ? "hand.raised" : "link",
                    tint: bill.plaidUnavailable ? .secondary : MoneyMapDesign.calmGreen
                )
            }
            DataSourceRow(title: "Due Date", value: bill.dueDate.map(MoneyMapFormatters.mediumDateString(for:)) ?? "Not set", systemImage: "calendar", tint: .blue)
            DataSourceRow(title: "Schedule", value: scheduleText, systemImage: "repeat", tint: .blue)
            DataSourceRow(title: "APR", value: percentageText(bill.creditCardDetails?.annualPercentageRate), systemImage: "percent", tint: .purple)
            DataSourceRow(title: "Minimum Payment", value: moneyText(bill.creditCardDetails?.minimumPayment), systemImage: "creditcard.and.123", tint: .blue)
            DataSourceRow(title: "Statement Balance", value: moneyText(bill.creditCardDetails?.statementBalance), systemImage: "doc.text", tint: .indigo)
            DataSourceRow(title: "Payment Settings", value: bill.autopayEnabled ? "Autopay on" : "Autopay off", systemImage: "gearshape", tint: .secondary)
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var calculatedSection: some View {
        Section {
            DataSourceRow(title: "Credit Limit", value: creditLimitSourceText, systemImage: "gauge.with.dots.needle.67percent", tint: MoneyMapDesign.warningGold)
            DataSourceRow(title: "Utilization", value: utilizationText, systemImage: "chart.pie", tint: MoneyMapDesign.warningGold)
            DataSourceRow(title: "Recommended Payment", value: moneyText(bill.creditCardDetails?.recommendedPayment), systemImage: "arrow.down.circle", tint: MoneyMapDesign.warningGold)
        } header: {
            Text("Calculated by MoneyMap")
        } footer: {
            Text("Calculated fields may combine Plaid balances with manual MoneyMap settings.")
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var summaryText: String {
        if bill.plaidAccountID == nil {
            return "This card is managed manually in MoneyMap."
        }
        return "This card combines Plaid bank data with your MoneyMap schedule and settings."
    }

    private var currentBalanceText: String {
        moneyText(plaidAccount?.currentBalance ?? bill.creditCardDetails?.cardBalance)
    }

    private var availableCreditText: String {
        moneyText(plaidAccount?.availableBalance)
    }

    private var lastFourText: String {
        if let mask = plaidAccount?.mask, !mask.isEmpty {
            return "•••• \(mask)"
        }
        if let lastFour = bill.creditCardDetails?.lastFourDigits, !lastFour.isEmpty {
            return "•••• \(lastFour)"
        }
        return "Not available"
    }

    private var plaidUpdatedText: String {
        bill.plaidUpdatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not synced yet"
    }

    private var scheduleText: String {
        guard let interval = bill.recurrenceInterval, let unit = bill.recurrenceUnit else {
            return "Not set"
        }
        return "Every \(interval) \(unit.rawValue)\(interval == 1 ? "" : "s")"
    }

    private var creditLimitSourceText: String {
        guard let details = bill.creditCardDetails else { return "Not set" }
        let value = MoneyMapFormatters.currencyString(for: details.creditLimit)
        if plaidAccount?.availableBalance != nil {
            return "\(value) from Plaid balance plus available credit"
        }
        return "\(value) manual value"
    }

    private var utilizationText: String {
        guard let details = bill.creditCardDetails else { return "Not available" }
        return details.utilization.formatted(.percent.precision(.fractionLength(0)))
    }

    private func moneyText(_ value: Double?) -> String {
        guard let value else { return "Not set" }
        return MoneyMapFormatters.currencyString(for: value)
    }

    private func percentageText(_ value: Double?) -> String {
        guard let value else { return "Not set" }
        return value.formatted(.percent.precision(.fractionLength(2)))
    }

    @MainActor
    private func loadPlaidAccount() {
        guard let plaidAccountID = bill.plaidAccountID else { return }

        do {
            let context = ModelContext(plaidContainer)
            let descriptor = FetchDescriptor<PlaidAccountSnapshot>(
                predicate: #Predicate { account in
                    account.accountID == plaidAccountID
                }
            )
            if let account = try context.fetch(descriptor).first {
                plaidAccount = PlaidAccountValue(account)
            }
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }
}

private struct DataSourceRow: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 26)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
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
