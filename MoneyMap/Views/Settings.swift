//
//  Settings.swift
//  MoneyMap
//
//  Created by Josh Smith on 5/19/25.
//

import SwiftUI
import UserNotifications
import SwiftData

struct Settings: View {
    @State private var showDeleteAllDataConfirmation = false
    @State private var isDeletingAllData = false
    @AppStorage(MoneyMapDesign.appearanceStyleKey) private var appearanceStyleRawValue = MoneyMapAppearanceStyle.warm.rawValue
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                NavigationLink("Activity") {
                    ActivityFeedView(title: "Activity")
                }
                NavigationLink("Smart Features") {
                    SmartFeaturesGuideView()
                }
                NavigationLink("Ask MoneyMap") {
                    MoneyMapAssistantView()
                }
                NavigationLink("What's New") {
                    WhatsNewView(releases: WhatsNewRepository.releases, onDone: nil)
                }
                NavigationLink("Notifications") {
                    ScheduledNotificationsView()
                }
                NavigationLink("Payment Methods") {
                    PaymentMethodsView()
                }
                NavigationLink("Bank Connections") {
                    BankSyncStatusContainerView()
                }
                Section {
                    Button(role: .destructive, action: { showDeleteAllDataConfirmation = true }) {
                        Label("Remove All Data", systemImage: "trash")
                    }
                    .disabled(isDeletingAllData)
                    .confirmationDialog("Are you sure you want to permanently remove ALL app data from this device and iCloud? This cannot be undone.", isPresented: $showDeleteAllDataConfirmation, titleVisibility: .visible) {
                        Button("Remove All Data", role: .destructive) {
                            Task { await removeAllAppData() }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(MoneyMapDesign.groupedBackground)
        }
    }
    
}

extension Settings {
    private var appearanceStyle: Binding<MoneyMapAppearanceStyle> {
        Binding {
            MoneyMapAppearanceStyle(rawValue: appearanceStyleRawValue) ?? .warm
        } set: { newValue in
            appearanceStyleRawValue = newValue.rawValue
            MoneyMapSharedDesign.setAppearanceStyleRawValue(newValue.rawValue)
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Section Style", selection: appearanceStyle) {
                ForEach(MoneyMapAppearanceStyle.allCases) { style in
                    Text(style.name).tag(style)
                }
            }
            .pickerStyle(.segmented)

            Text((MoneyMapAppearanceStyle(rawValue: appearanceStyleRawValue) ?? .warm).detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Appearance")
        }
    }

    func removeAllAppData() async {
        isDeletingAllData = true
        defer { isDeletingAllData = false }
        do {
            try await AppResetService.removeAllAppData(modelContext: modelContext)
        } catch {
            print("Failed to remove all app data: \(error)")
        }
    }
}

struct PaymentMethodsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PaymentMethod.name) private var paymentMethods: [PaymentMethod]
    @Query private var bills: [Bill]

    @State private var showingNewPaymentMethod = false
    @State private var editingPaymentMethod: PaymentMethod?

    var body: some View {
        List {
            if paymentMethods.isEmpty {
                MoneyMapEmptyState(
                    title: "No Payment Methods",
                    message: "Add checking, savings, debit, cash, or card methods you use to pay bills.",
                    systemImage: "creditcard.and.123"
                )
                .listRowBackground(MoneyMapDesign.surfaceBackground)
            }

            if !cardMethods.isEmpty {
                Section("Cards") {
                    ForEach(cardMethods) { paymentMethod in
                        if let linkedBill = linkedBill(for: paymentMethod) {
                            NavigationLink {
                                BillView(bill: linkedBill)
                            } label: {
                                PaymentMethodListRow(
                                    paymentMethod: paymentMethod,
                                    detailOverride: "Managed from \(linkedBill.name ?? "card bill")"
                                )
                            }
                        } else {
                            Button {
                                editingPaymentMethod = paymentMethod
                            } label: {
                                PaymentMethodListRow(paymentMethod: paymentMethod)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    delete(paymentMethod)
                                }
                            }
                        }
                    }
                }
                .listRowBackground(MoneyMapDesign.surfaceBackground)
            }

            Section("Accounts and Other") {
                if editableMethods.isEmpty {
                    Text("Add checking, savings, debit, cash, or other ways you pay bills.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(editableMethods) { paymentMethod in
                        Button {
                            editingPaymentMethod = paymentMethod
                        } label: {
                            PaymentMethodListRow(paymentMethod: paymentMethod)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete(paymentMethod)
                            }
                        }
                    }
                }
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
        .navigationTitle("Payment Methods")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewPaymentMethod = true
                } label: {
                    Label("Add Payment Method", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewPaymentMethod) {
            PaymentMethodEditor()
        }
        .sheet(item: $editingPaymentMethod) { paymentMethod in
            PaymentMethodEditor(paymentMethod: paymentMethod)
        }
        .onAppear(perform: syncCreditCards)
        .onChange(of: creditCardSyncSignature) { _, _ in
            syncCreditCards()
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

    private var cardMethods: [PaymentMethod] {
        sortedPaymentMethods.filter { $0.type == .creditCard }
    }

    private var editableMethods: [PaymentMethod] {
        sortedPaymentMethods.filter { $0.type != .creditCard }
    }

    private var creditCardSyncSignature: String {
        let cardBills = bills
            .filter { $0.category == .creditCard }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { bill in
                "\(bill.id.uuidString)|\(bill.name ?? "")|\(bill.creditCardDetails?.issuerName ?? "")|\(bill.creditCardDetails?.lastFourDigits ?? "")"
            }
            .joined(separator: ";")
        let cardMethods = paymentMethods
            .filter { $0.type == .creditCard }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString)|\($0.linkedBillID?.uuidString ?? "")|\($0.displayName)" }
            .joined(separator: ";")
        return "\(cardBills)#\(cardMethods)"
    }

    private func linkedBill(for paymentMethod: PaymentMethod) -> Bill? {
        guard let linkedBillID = paymentMethod.linkedBillID else { return nil }
        return bills.first { $0.id == linkedBillID }
    }

    private func syncCreditCards() {
        guard PaymentMethodSyncService.syncCreditCardPaymentMethods(
            bills: bills,
            paymentMethods: paymentMethods,
            context: modelContext
        ) else {
            return
        }

        try? modelContext.save()
    }

    private func delete(_ paymentMethod: PaymentMethod) {
        for bill in bills where bill.paymentMethodID == paymentMethod.id {
            bill.paymentMethodID = nil
            if bill.autopaySource == paymentMethod.displayName {
                bill.autopaySource = nil
            }
        }

        modelContext.delete(paymentMethod)
        try? modelContext.save()
        AppRefreshEvents.notifyBillsDidChange()
    }
}

struct PaymentMethodEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let paymentMethod: PaymentMethod?
    let onSave: (PaymentMethod) -> Void

    @State private var name: String
    @State private var type: PaymentMethodType
    @State private var institutionName: String
    @State private var lastFourDigits: String
    @State private var routingNumber: String
    @State private var notes: String

    init(paymentMethod: PaymentMethod? = nil, onSave: @escaping (PaymentMethod) -> Void = { _ in }) {
        self.paymentMethod = paymentMethod
        self.onSave = onSave
        _name = State(initialValue: paymentMethod?.name ?? "")
        _type = State(initialValue: paymentMethod?.type ?? .checking)
        _institutionName = State(initialValue: paymentMethod?.institutionName ?? "")
        _lastFourDigits = State(initialValue: paymentMethod?.lastFourDigits ?? "")
        _routingNumber = State(initialValue: paymentMethod?.routingNumber ?? "")
        _notes = State(initialValue: paymentMethod?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if paymentMethod?.isCreditCardMirror == true {
                    Section {
                        Label("This card is managed from its bill.", systemImage: "creditcard")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Basics") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(PaymentMethodType.allCases) { type in
                            Label(type.name, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    TextField("Institution", text: $institutionName)
                }

                Section {
                    TextField("Last 4 Digits", text: $lastFourDigits)
                        .keyboardType(.numberPad)

                    if type.usesRoutingNumber {
                        TextField("Routing Number", text: $routingNumber)
                            .keyboardType(.numberPad)
                    }
                } header: {
                    Text("Numbers")
                } footer: {
                    Text("MoneyMap stores labels and identifying digits only. No bank or card connection is set up yet.")
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(paymentMethod == nil ? "New Method" : "Edit Method")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave || paymentMethod?.isCreditCardMirror == true)
                }
            }
        }
    }

    private var canSave: Bool {
        !normalizedName.isEmpty
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedInstitutionName: String? {
        let trimmed = institutionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() {
        let target = paymentMethod ?? PaymentMethod(name: normalizedName, type: type)
        target.name = normalizedName
        target.type = type
        target.institutionName = normalizedInstitutionName
        target.lastFourDigits = PaymentMethod.normalizedLastFourDigits(lastFourDigits)
        target.routingNumber = type.usesRoutingNumber ? PaymentMethod.normalizedRoutingNumber(routingNumber) : nil
        target.notes = normalizedNotes
        target.updatedAt = .now

        if paymentMethod == nil {
            modelContext.insert(target)
        }

        do {
            try modelContext.save()
            onSave(target)
            dismiss()
        } catch {
            // Keep the editor open if SwiftData cannot save this method.
        }
    }
}

private struct PaymentMethodListRow: View {
    let paymentMethod: PaymentMethod
    var detailOverride: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: paymentMethod.type.icon)
                .foregroundStyle(paymentMethod.type.color)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(paymentMethod.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(detailOverride ?? paymentMethod.detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct ScheduledNotificationsView: View {
    @State private var notifications: [UNNotificationRequest] = []
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    var body: some View {
        List {
            Section {
                if notifications.isEmpty {
                    MoneyMapEmptyState(
                        title: "No Scheduled Notifications",
                        message: "Payday, bill, and goal alerts will appear here after they are scheduled.",
                        systemImage: "bell"
                    )
                } else {
                    ForEach(notifications, id: \.identifier) { request in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(request.content.title)
                                .font(.headline)
                            Text(request.content.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let trigger = request.trigger as? UNCalendarNotificationTrigger,
                               let nextTriggerDate = trigger.nextTriggerDate() {
                                Text("Scheduled for \(nextTriggerDate.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
        .onAppear(perform: fetchNotifications)
        .navigationTitle("Scheduled Notifications")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                    Label("Remove All", systemImage: "trash")
                }
                .disabled(notifications.isEmpty || isDeleting)
                .confirmationDialog("Are you sure you want to remove all scheduled notifications? This action cannot be undone.", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                    Button("Remove All", role: .destructive) {
                        removeAllNotifications()
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
    }

    func fetchNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
                self.notifications = requests
            }
        }
    }

    func removeAllNotifications() {
        isDeleting = true
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        // Wait a bit to let the system update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            fetchNotifications()
            isDeleting = false
        }
    }
}

#Preview {
    Settings()
}
