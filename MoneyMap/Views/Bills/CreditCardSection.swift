//
//  CreditCardSection.swift
//  AddMoneyMap
//
//  Created by Josh Smith on 7/2/25.
//

import SwiftUI
import SwiftData
import ImagePlayground

struct CreditCardSection: View {
    
    @Environment(\.modelContext) private var modelContext
    
    var bills: Bills
    @Binding var billToEdit: Bill?
    @Binding var alertValue: String
    @Binding var editingBalance: Bool
    @Binding var editingLimit: Bool
    @Binding var makingPayment: Bool
    
    enum SortOption: String, CaseIterable, Identifiable {
        case statusDateUtilization, date, name, limit, balance
        var id: String { rawValue }
        var title: String {
            switch self {
            case .statusDateUtilization: return "Default"
            case .date: return "Due Date"
            case .name: return "Name"
            case .limit: return "Credit Limit"
            case .balance: return "Balance"
            }
        }
        var sortClosure: (Bill, Bill) -> Bool {
            switch self {
            case .statusDateUtilization: return Bill.byStatusDateUtilization
            case .date: return Bill.byDate
            case .name: return Bill.byName
            case .limit: return Bill.byLimit
            case .balance: return Bill.byBalance
            }
        }
    }
    
    private enum SortDirection: String, CaseIterable, Identifiable {
        case ascending, descending
        var id: String { rawValue }
        var title: String {
            switch self {
            case .ascending: return "Ascending"
            case .descending: return "Descending"
            }
        }
        var isAscending: Bool { self == .ascending }
    }
    
    @State private var selectedSort: SortOption = .statusDateUtilization
    @State private var sortDirection: SortDirection = .ascending
    
    var sortedCreditCards: [Bill] {
        let sorted = bills.creditCards.sorted(by: selectedSort.sortClosure)
        return sortDirection.isAscending ? sorted : sorted.reversed()
    }

    var body: some View {
        Section {
            CreditCardPortfolioPanel(cards: bills.creditCards)
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)

        Section {
            ForEach(sortedCreditCards) { card in
                CardRowWithDelete(
                    card: card,
                    modelContext: modelContext,
                    billToEdit: $billToEdit,
                    alertValue: $alertValue,
                    editingBalance: $editingBalance,
                    editingLimit: $editingLimit,
                    makingPayment: $makingPayment
                )
            }
        } header: {
            creditCardHeader
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var creditCardHeader: some View {
        HStack(spacing: 8) {
            Label("Credit Cards", systemImage: "creditcard")
                .foregroundStyle(MoneyMapDesign.brandGreen)
                .font(.headline)

            Spacer()

            Menu {
                Picker("Sort by", selection: $selectedSort) {
                    ForEach(SortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Picker("Order", selection: $sortDirection) {
                    ForEach(SortDirection.allCases) { direction in
                        Text(direction.title).tag(direction)
                    }
                }
            } label: {
                Label(selectedSort.title, systemImage: "arrow.up.arrow.down")
            }
            .font(.subheadline.weight(.semibold))
        }
    }
}

private struct CardRowWithDelete: View {
    let card: Bill
    let modelContext: ModelContext
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    
    @Binding var billToEdit: Bill?
    @Binding var alertValue: String
    @Binding var editingBalance: Bool
    @Binding var editingLimit: Bool
    @Binding var makingPayment: Bool
    
    @State private var showingDeleteConfirmation = false
    @State private var imagePickerSource: ImagePickerSource?
    @State private var creatingImage = false
    
    var body: some View {
        NavigationLink {
            BillView(bill: card)
        } label: {
            CreditCardListRow(card: card)
        }
            .swipeActions(edge: .leading) {
                Button(MoneyMapAction.makePayment.title, systemImage: MoneyMapAction.makePayment.systemImage) {
                    billToEdit = card
                    alertValue = ""
                    makingPayment = true
                }
                .tint(MoneyMapDesign.calmGreen)
                Button(MoneyMapAction.editBalance.title, systemImage: MoneyMapAction.editBalance.systemImage) {
                    billToEdit = card
                    editingBalance = true
                }
                .tint(MoneyMapDesign.sage)
            }
            .swipeActions(edge: .trailing) {
                Button(MoneyMapAction.editLimit.title, systemImage: MoneyMapAction.editLimit.systemImage) {
                    billToEdit = card
                    editingLimit = true
                }
                .tint(MoneyMapDesign.warningGold)
                Button("Delete", systemImage: "trash") {
                    showingDeleteConfirmation = true
                }
                .tint(MoneyMapDesign.attentionRed)
            }
            .contextMenu {
                Section("Card Image") {
                    Button("Take Photo", systemImage: "camera") {
                        imagePickerSource = .camera
                    }
                    Button("Choose Photo", systemImage: "photo.on.rectangle") {
                        imagePickerSource = .photoLibrary
                    }
                    if supportsImagePlayground {
                        Button("Generate Image", systemImage: "paintpalette") {
                            creatingImage = true
                        }
                    }
                    if card.imageData != nil {
                        Button("Remove Image", systemImage: "xmark.circle", role: .destructive) {
                            card.imageData = nil
                            saveCardImageChange()
                        }
                    }
                }

                Button(MoneyMapAction.makePayment.title, systemImage: MoneyMapAction.makePayment.systemImage) {
                    billToEdit = card
                    alertValue = ""
                    makingPayment = true
                }
                Button(MoneyMapAction.editBalance.title, systemImage: MoneyMapAction.editBalance.systemImage) {
                    billToEdit = card
                    editingBalance = true
                }
                Button(MoneyMapAction.editLimit.title, systemImage: MoneyMapAction.editLimit.systemImage) {
                    billToEdit = card
                    editingLimit = true
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
            .confirmationDialog("Are you sure you want to delete this bill?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(card)
                    try? modelContext.save()
                    AppRefreshEvents.notifyBillsDidChange()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $imagePickerSource) { source in
                switch source {
                case .camera:
                    ImagePicker(sourceType: .camera) { image in
                        card.setImage(image)
                        imagePickerSource = nil
                        saveCardImageChange()
                    }
                case .photoLibrary:
                    ImagePicker(sourceType: .photoLibrary) { image in
                        card.setImage(image)
                        imagePickerSource = nil
                        saveCardImageChange()
                    }
                case .files:
                    DocumentPicker { image in
                        card.setImage(image)
                        imagePickerSource = nil
                        saveCardImageChange()
                    }
                case .playground:
                    EmptyView()
                }
            }
            .imagePlaygroundSheet(isPresented: $creatingImage, concept: card.name ?? "credit card", onCompletion: { url in
                Task {
                    if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                        card.setImage(image)
                        saveCardImageChange()
                    }
                }
            })
    }

    private func saveCardImageChange() {
        try? modelContext.save()
        AppRefreshEvents.notifyBillsDidChange()
    }
}

private struct CreditCardPortfolioPanel: View {
    let cards: Bills

    private var utilization: Double {
        min(max(cards.creditCardUtilization, 0), 1)
    }

    private var recommendedPayment: Double? {
        cards.recommendedPayment
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "creditcard.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(MoneyMapDesign.moneyGradient)
                    .clipShape(.rect(cornerRadius: MoneyMapDesign.controlCornerRadius))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Card Snapshot")
                        .font(.headline)
                    Text("\(cards.creditCards.count) card\(cards.creditCards.count == 1 ? "" : "s") tracked")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(utilization, format: .percent.precision(.fractionLength(0)))
                        .font(.title2.weight(.bold).monospacedDigit())
                    Text("utilization")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: utilization)
                .tint(utilizationColor)

            HStack(spacing: 10) {
                CreditCardMetric(
                    title: "Balance",
                    value: MoneyMapFormatters.currencyString(for: cards.totalBalance),
                    systemImage: "dollarsign.circle",
                    tint: utilizationColor
                )
                CreditCardMetric(
                    title: "Limit",
                    value: MoneyMapFormatters.currencyString(for: cards.totalCreditLimit),
                    systemImage: "gauge.with.dots.needle.67percent",
                    tint: MoneyMapDesign.sage
                )
            }

            if let recommendedPayment {
                CreditCardRecommendationRow(amount: recommendedPayment)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var utilizationColor: Color {
        if utilization >= 0.3 {
            return MoneyMapDesign.attentionRed
        }
        if utilization >= 0.1 {
            return MoneyMapDesign.warningGold
        }
        return MoneyMapDesign.calmGreen
    }
}

private struct CreditCardListRow: View {
    let card: Bill

    private var details: CreditCardDetails? {
        card.creditCardDetails
    }

    private var utilization: Double {
        guard let details else { return 0 }
        return min(max(details.utilization, 0), 1)
    }

    private var utilizationColor: Color {
        if utilization >= 0.3 {
            return MoneyMapDesign.attentionRed
        }
        if utilization >= 0.1 {
            return MoneyMapDesign.warningGold
        }
        return MoneyMapDesign.calmGreen
    }

    private var dueText: String {
        guard let dueDate = card.dueDate else { return "No due date" }
        return "Due \(MoneyMapFormatters.mediumDateString(for: dueDate))"
    }

    private var paymentText: String {
        if let recommended = details?.recommendedPayment, recommended > 0 {
            return "\(MoneyMapFormatters.currencyString(for: recommended)) recommended"
        }
        return "On target"
    }

    private var paymentIcon: String {
        if let recommended = details?.recommendedPayment, recommended > 0 {
            return "arrow.down.circle"
        }
        return "checkmark.circle"
    }

    var body: some View {
        HStack(spacing: 12) {
            cardArt
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(card.name ?? "Untitled Card")
                    .font(.headline)
                    .lineLimit(1)

                Text(dueText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Image(systemName: paymentIcon)
                        .imageScale(.medium)
                        .frame(width: 16)
                    Text(paymentText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(paymentIcon == "checkmark.circle" ? MoneyMapDesign.calmGreen : utilizationColor)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 5) {
                Text(details?.cardBalance ?? 0, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .imageScale(.medium)
                    Text(utilization, format: .percent.precision(.fractionLength(0)))
                        .lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(utilizationColor)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var cardGradient: LinearGradient {
        LinearGradient(
            colors: [MoneyMapDesign.deepMoneyGreen, MoneyMapDesign.calmGreen],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var cardArt: some View {
        if let cardImage = card.image {
            cardImage
                .resizable()
                .scaledToFill()
                .clipShape(.rect(cornerRadius: MoneyMapDesign.controlCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: MoneyMapDesign.controlCornerRadius)
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: MoneyMapDesign.controlCornerRadius)
                    .fill(cardGradient)

                Image(systemName: "creditcard.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct CreditCardMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CreditCardRecommendationRow: View {
    let amount: Double

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(MoneyMapDesign.calmGreen)
                .accessibilityHidden(true)

            Text("Recommended payment")
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(MoneyMapFormatters.currencyString(for: amount))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(MoneyMapDesign.controlBackground)
        .clipShape(.rect(cornerRadius: MoneyMapDesign.controlCornerRadius))
    }
}

#Preview {
    struct Container: View {
        @State private var billToEdit: Bill? = nil
        @State private var alertValue: String = ""
        @State private var editingBalance: Bool = false
        @State private var editingLimit: Bool = false
        @State private var makingPayment: Bool = false

        var body: some View {
            // Use sample credit card bills
            let sampleBills = Bill.sampleBills(type: .creditCard)
            CreditCardSection(
                bills: sampleBills,
                billToEdit: $billToEdit,
                alertValue: $alertValue,
                editingBalance: $editingBalance, editingLimit: $editingLimit,
                makingPayment: $makingPayment
            )
            .padding()
        }
    }
    return NavigationStack {
        List {
            Container()
        }
        .navigationTitle("Bills")
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
    }
}
