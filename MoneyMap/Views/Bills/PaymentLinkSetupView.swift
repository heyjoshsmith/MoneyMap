//
//  PaymentLinkSetupView.swift
//  MoneyMap
//
//  Created by Codex on 7/1/26.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct PaymentLinkSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    let bill: Bill

    @State private var linkText: String
    @State private var showingInvalidLink = false

    init(bill: Bill) {
        self.bill = bill
        _linkText = State(initialValue: bill.paymentURLString ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PaymentLinkInputControls(linkText: $linkText)
                } header: {
                    Text("Payment Link")
                } footer: {
                    Text("Web links are best. If the biller's app supports the same link, iOS opens the app.")
                }

                Section {
                    if let paymentURL {
                        Button("Open Link", systemImage: "arrow.up.forward.app") {
                            openURL(paymentURL)
                        }

                        Button("Save Link", systemImage: "checkmark") {
                            saveLink()
                        }
                    } else {
                        Label("Enter a website or app link", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                    }

                    if bill.paymentURLString != nil {
                        Button("Remove Link", systemImage: "trash", role: .destructive) {
                            removeLink()
                        }
                    }
                }
            }
            .navigationTitle(bill.name ?? "Payment Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveLink()
                    }
                    .disabled(paymentURL == nil)
                }
            }
            .alert("Link Not Ready", isPresented: $showingInvalidLink) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Add a website like biller.com or paste an app link.")
            }
        }
    }

    private var normalizedLink: String? {
        Bill.normalizedPaymentURLString(from: linkText)
    }

    private var paymentURL: URL? {
        Bill.paymentURL(from: linkText)
    }

    private func saveLink() {
        guard let normalizedLink else {
            showingInvalidLink = true
            return
        }

        bill.paymentURLString = normalizedLink
        saveAndDismiss()
    }

    private func removeLink() {
        bill.paymentURLString = nil
        saveAndDismiss()
    }

    private func saveAndDismiss() {
        do {
            try modelContext.save()
            AppRefreshEvents.notifyBillsDidChange()
            dismiss()
        } catch {
            showingInvalidLink = true
        }
    }
}

struct PaymentLinkInputControls: View {
    @Environment(\.openURL) private var openURL

    @Binding var linkText: String

    private var trimmedLink: String {
        linkText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var paymentURL: URL? {
        Bill.paymentURL(from: linkText)
    }

    private var showsInvalidLink: Bool {
        !trimmedLink.isEmpty && paymentURL == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("biller.com or app://pay", text: $linkText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            ViewThatFits(in: .horizontal) {
                HStack {
                    actionButtons
                }

                VStack(alignment: .leading) {
                    actionButtons
                }
            }
            .buttonStyle(.bordered)

            if showsInvalidLink {
                Label("Use a website or app link", systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(MoneyMapDesign.attentionRed)
            } else if let host = Bill.paymentHost(from: linkText) {
                Label(host, systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(MoneyMapDesign.calmGreen)
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button("Paste Link", systemImage: "doc.on.clipboard") {
            pasteLink()
        }

        if let paymentURL {
            Button("Test Link", systemImage: "arrow.up.forward.app") {
                openURL(paymentURL)
            }
        }

        if !trimmedLink.isEmpty {
            Button("Clear", systemImage: "xmark.circle") {
                linkText = ""
            }
        }
    }

    private func pasteLink() {
        #if canImport(UIKit)
        if let pasted = UIPasteboard.general.string {
            linkText = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
    }
}

struct PaymentLinkSummaryCard: View {
    let bill: Bill
    let openPaymentLink: (URL) -> Void
    let configurePaymentLink: () -> Void

    private var paymentURL: URL? {
        bill.paymentURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "link")
                    .foregroundStyle(.blue)
                    .font(.title3)
                    .frame(width: 26)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Payment Link")
                        .font(.headline)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)
            }

            LazyVGrid(columns: actionGridColumns, alignment: .leading, spacing: 8) {
                ForEach(actions) { action in
                    PaymentLinkActionButton(action: action)
                }
            }
        }
        .padding()
        .background(MoneyMapDesign.surfaceBackground)
        .clipShape(.rect(cornerRadius: MoneyMapDesign.sectionCornerRadius))
    }

    private var statusText: String {
        if let host = bill.paymentHost {
            return host
        }
        if let rawValue = bill.paymentURLString, !rawValue.isEmpty {
            return "Link needs attention"
        }
        return "Not set"
    }

    private var actionGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 148), spacing: 8, alignment: .top)
        ]
    }

    private var actions: [PaymentLinkAction] {
        if let paymentURL {
            return [
                PaymentLinkAction(
                    title: "Open Link",
                    detail: bill.paymentHost ?? "Website or app",
                    systemImage: "arrow.up.forward.app",
                    tint: .blue,
                    style: .prominent
                ) {
                    openPaymentLink(paymentURL)
                },
                PaymentLinkAction(
                    title: "Change",
                    detail: "Edit destination",
                    systemImage: "slider.horizontal.3",
                    tint: .secondary
                ) {
                    configurePaymentLink()
                }
            ]
        } else {
            return [
                PaymentLinkAction(
                    title: "Set Up Link",
                    detail: "Website or app link",
                    systemImage: "link.badge.plus",
                    tint: .blue,
                    style: .prominent
                ) {
                    configurePaymentLink()
                }
            ]
        }
    }
}

private struct PaymentLinkAction: Identifiable {
    enum Style: Equatable {
        case prominent
        case secondary
    }

    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    var style: Style = .secondary
    let handler: () -> Void

    var id: String {
        "\(title)-\(systemImage)"
    }
}

private struct PaymentLinkActionButton: View {
    let action: PaymentLinkAction

    var body: some View {
        Button {
            action.handler()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: action.systemImage)
                    .font(.headline)
                    .foregroundStyle(action.tint)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(action.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(MoneyMapDesign.controlBackground)
            .clipShape(.rect(cornerRadius: MoneyMapDesign.controlCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: MoneyMapDesign.controlCornerRadius)
                    .stroke(MoneyMapDesign.separator.opacity(0.24), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let (container, _) = PreviewDataProvider.createContainer()
    let bills = (try? container.mainContext.fetch(FetchDescriptor<Bill>())) ?? []

    PaymentLinkSetupView(bill: bills.first ?? Bill(
        name: "Electric",
        amount: 120,
        dueDate: .now,
        category: .utilities,
        recurrenceInterval: 1,
        recurrenceUnit: .month
    ))
    .modelContainer(container)
}
