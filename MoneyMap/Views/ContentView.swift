//
//  ContentView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/11/25.
//

import SwiftUI
import UniformTypeIdentifiers
import SwiftData

// MARK: - ContentView (TabView)
struct ContentView: View {
    
    @Environment(\.modelContext) private var modelContext
    @State private var selection: Tab = .bills
    
    @State private var pendingCSVURLs: [URL] = []
    @State private var showingBillsImportSheet = false
    
    var body: some View {
        TabView(selection: $selection) {
            GoalsView().tag(Tab.goals)
                .tabItem {
                    Image(systemName: "dollarsign.circle")
                    Text("Goals")
                }
            PaydayView().tag(Tab.pay)
                .tabItem {
                    Image(systemName: "dollarsign.arrow.circlepath")
                    Text("Pay")
                }
            BillsHome().tag(Tab.bills)
                .tabItem {
                    Image(systemName: "banknote")
                    Text("Bills")
                }
            Settings().tag(Tab.settings)
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
        }
        .onOpenURL { url in
            if url.pathExtension.lowercased() == "csv" {
                pendingCSVURLs = [url]
                showingBillsImportSheet = true
            } else if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
                      type.conforms(to: .commaSeparatedText) {
                pendingCSVURLs = [url]
                showingBillsImportSheet = true
            }
        }
        .sheet(isPresented: $showingBillsImportSheet) {
            CreditCardPickerSheet(csvURLs: pendingCSVURLs) { selectedBill in
                // Import logic goes here
                for url in pendingCSVURLs {
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        do {
                            let context = selectedBill.modelContext ?? modelContext
                            _ = try importTransactions(fromCSVAt: url, to: selectedBill, context: context)
                        } catch {
                            print("Error importing CSV: \(error)")
                        }
                    }
                }
                pendingCSVURLs.removeAll()
            }
        }
    }
    
    enum Tab: String, CaseIterable, Identifiable {
        case goals, pay, bills, settings
        var id: Self { return self }
    }
}

struct CreditCardPickerSheet: View {
    @Environment(\.modelContext) private var modelContext
    let csvURLs: [URL]
    let onImport: (Bill) -> Void
    @Query private var bills: [Bill]
    @Environment(\.dismiss) private var dismiss

    var creditCards: [Bill] {
        bills.filter { $0.category == .creditCard }
    }
    var body: some View {
        NavigationView {
            List(creditCards, id: \.id) { card in
                Button {
                    onImport(card)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: card.category?.icon ?? "creditcard")
                            .foregroundStyle(.blue)
                        Text(card.name ?? "Untitled")
                        Spacer()
                        if let amount = card.amount {
                            Text(amount, format: .currency(code: "USD"))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Select Credit Card")
        }
    }
}

#Preview {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    ContentView()
        .environmentObject(paydayManager)
        .modelContainer(container)
}
