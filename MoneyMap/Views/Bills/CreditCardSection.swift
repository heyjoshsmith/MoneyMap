//
//  CreditCardSection.swift
//  AddMoneyMap
//
//  Created by Josh Smith on 7/2/25.
//

import SwiftUI
import SwiftData

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
            ForEach(sortedCreditCards) { card in
                CardRowWithDelete(card: card, modelContext: modelContext, billToEdit: $billToEdit, alertValue: $alertValue, editingBalance: $editingBalance, editingLimit: $editingLimit, makingPayment: $makingPayment)
            }
        } header: {
            HStack {
                Text(selectedSort.title)
                    .foregroundStyle(Color.primary)
                    .font(.title2.weight(.semibold))
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
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }
}

private struct CardRowWithDelete: View {
    let card: Bill
    let modelContext: ModelContext
    
    @Binding var billToEdit: Bill?
    @Binding var alertValue: String
    @Binding var editingBalance: Bool
    @Binding var editingLimit: Bool
    @Binding var makingPayment: Bool
    
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        CreditCardRow(for: card)
            .swipeActions(edge: .leading) {
                Button("Pay", systemImage: "dollarsign.arrow.trianglehead.counterclockwise.rotate.90") {
                    billToEdit = card
                    alertValue = ""
                    makingPayment = true
                }.tint(.green)
                Button("Balance", systemImage: "dollarsign.gauge.chart.lefthalf.righthalf") {
                    billToEdit = card
                    editingBalance = true
                }.tint(.blue)
            }
            .swipeActions(edge: .trailing) {
                Button("Limit", systemImage: "dollarsign.gauge.chart.lefthalf.righthalf") {
                    billToEdit = card
                    editingLimit = true
                }.tint(.purple)
                Button("Delete", systemImage: "trash") {
                    showingDeleteConfirmation = true
                }.tint(.red)
            }
            .confirmationDialog("Are you sure you want to delete this bill?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(card)
                }
                Button("Cancel", role: .cancel) {}
            }
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
        .listStyle(.plain)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
