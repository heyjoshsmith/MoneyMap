import SwiftUI

struct TransactionRow: View {
    var transaction: Transaction
    var onSetFriendlyName: ((Transaction) -> Void)? = nil
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.friendlyName?.isEmpty == false ? transaction.friendlyName! : (transaction.merchant ?? "No Merchant"))
                    .font(.headline)
                if let category = transaction.category {
                    Text(category)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let date = transaction.transactionDate {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let amount = transaction.amountUSD {
                    Text(amount, format: .currency(code: "USD"))
                        .font(.headline)
                        .foregroundStyle(amount < 0 ? .green : .primary)
                } else {
                    Text("-")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu {
            Button("Set Friendly Name") {
                onSetFriendlyName?(transaction)
            }
        }
    }
}

#Preview {
    // Preview with a mock transaction
    let transaction = Transaction(
        transactionDate: "07/07/2025",
        clearingDate: "07/12/2025",
        transactionDescription: "Coffee Shop",
        merchant: "Starbucks",
        category: "Food",
        type: "Debit",
        amountUSD: 4.50,
        purchasedBy: "Josh"
    )
    List {
        TransactionRow(transaction: transaction)
    }
}
