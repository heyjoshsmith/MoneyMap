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
                .moneyMapListSectionBackground()

                Section {
                    if let paymentURL {
                        Button {
                            openURL(paymentURL)
                        } label: {
                            MoneyMapActionCardLabel(
                                title: "Open Link",
                                detail: Bill.paymentHost(from: linkText) ?? "Website or app",
                                systemImage: "arrow.up.forward.app",
                                tint: .blue
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            saveLink()
                        } label: {
                            MoneyMapActionCardLabel(
                                title: "Save Link",
                                detail: "Use this destination for payments.",
                                systemImage: "checkmark.circle",
                                tint: MoneyMapDesign.calmGreen,
                                isProminent: true
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        MoneyMapStatusBanner(
                            message: "Enter a website or app link.",
                            systemImage: "exclamationmark.circle"
                        )
                    }

                    if bill.paymentURLString != nil {
                        Button(role: .destructive) {
                            removeLink()
                        } label: {
                            MoneyMapActionCardLabel(
                                title: "Remove Link",
                                detail: "Clear the saved destination.",
                                systemImage: "trash",
                                tint: MoneyMapDesign.attentionRed
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .moneyMapListSectionBackground()
            }
            .moneyMapGroupedListBackground()
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                    Image(systemName: "link")
                        .foregroundStyle(.blue)
                        .font(.title3.weight(.semibold))
                }
                .frame(width: 46, height: 42)
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
            GridItem(.flexible(), spacing: 8, alignment: .top)
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
