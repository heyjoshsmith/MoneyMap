//
//  TransactionCSVImportGuideView.swift
//  MoneyMapShared
//
//  Created by Codex on 7/22/26.
//

import SwiftData
import SwiftUI

#if !os(watchOS)
public struct TransactionCSVImportGuideView: View {
    private enum Step: Int, CaseIterable {
        case chooseCard
        case review
        case complete

        var title: String {
            switch self {
            case .chooseCard: return "Card"
            case .review: return "Review"
            case .complete: return "Done"
            }
        }

        var systemImage: String {
            switch self {
            case .chooseCard: return "creditcard"
            case .review: return "checklist"
            case .complete: return "checkmark"
            }
        }
    }

    private let csvURLs: [URL]
    private let fixedBill: Bill?
    private let onFinished: (TransactionCSVImportSummary?) -> Void
    private let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var bills: [Bill]

    @State private var selectedBill: Bill?
    @State private var step: Step
    @State private var preview: TransactionCSVImportPreview?
    @State private var summary: TransactionCSVImportSummary?
    @State private var isImporting = false
    @State private var errorMessage: String?

    public init(
        csvURLs: [URL],
        fixedBill: Bill? = nil,
        onFinished: @escaping (TransactionCSVImportSummary?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.csvURLs = csvURLs
        self.fixedBill = fixedBill
        self.onFinished = onFinished
        self.onCancel = onCancel
        self._selectedBill = State(initialValue: fixedBill)
        self._step = State(initialValue: fixedBill == nil ? .chooseCard : .review)
    }

    private var creditCards: [Bill] {
        bills
            .filter { $0.category == .creditCard }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    public var body: some View {
        NavigationStack {
            List {
                importHeader
                progressSection

                switch step {
                case .chooseCard:
                    cardSection
                    fileSection
                case .review:
                    fileSection
                    reviewSection
                case .complete:
                    completionSection
                    fileSection
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(TransactionImportDesign.attention)
                    }
                    .listRowBackground(TransactionImportDesign.surfaceBackground)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(TransactionImportDesign.groupedBackground)
            .tint(TransactionImportDesign.accent)
            .navigationTitle("Import Transactions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step != .complete {
                        Button("Cancel") {
                            onCancel()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    confirmationButton
                }
            }
            .onAppear {
                if fixedBill != nil {
                    refreshPreview()
                }
            }
        }
    }

    private var importHeader: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: TransactionImportDesign.controlCornerRadius)
                        .fill(TransactionImportDesign.moneyGradient)
                    Image(systemName: "creditcard.and.123")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Card CSV")
                        .font(.headline)
                    Text(headerDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(TransactionImportDesign.surfaceBackground)
    }

    private var headerDetail: String {
        switch step {
        case .chooseCard:
            return "Choose the MoneyMap card that should receive this Wallet export."
        case .review:
            return "Check the file summary before MoneyMap adds new transactions."
        case .complete:
            return "The import is finished and duplicates were left untouched."
        }
    }

    private var progressSection: some View {
        Section {
            HStack(spacing: 10) {
                ForEach(Step.allCases, id: \.self) { item in
                    stepBadge(for: item)
                    if item != Step.allCases.last {
                        Rectangle()
                            .fill(item.rawValue < step.rawValue ? TransactionImportDesign.accent : Color.secondary.opacity(0.25))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(TransactionImportDesign.surfaceBackground)
    }

    private func stepBadge(for item: Step) -> some View {
        let isActive = item == step
        let isComplete = item.rawValue < step.rawValue

        return VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(isActive || isComplete ? TransactionImportDesign.accent : TransactionImportDesign.controlBackground)
                Image(systemName: isComplete ? "checkmark" : item.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isActive || isComplete ? .white : .secondary)
            }
            .frame(width: 28, height: 28)

            Text(item.title)
                .font(.caption2.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
        }
        .frame(width: 58)
        .accessibilityLabel(item.title)
    }

    private var cardSection: some View {
        Section("Destination") {
            if creditCards.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("No credit cards found", systemImage: "creditcard.trianglebadge.exclamationmark")
                        .font(.headline)
                    Text("Add Apple Card as a credit card in MoneyMap, then run the import again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(creditCards, id: \.id) { card in
                    Button {
                        withAnimation(.snappy) {
                            selectedBill = card
                        }
                        refreshPreview(for: card)
                    } label: {
                        cardRow(card, isSelected: selectedBill?.id == card.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listRowBackground(TransactionImportDesign.surfaceBackground)
    }

    private func cardRow(_ card: Bill, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "creditcard")
                .foregroundStyle(TransactionImportDesign.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.name ?? "Untitled Card")
                    .font(.body.weight(.medium))
                if let amount = card.amount {
                    Text(amount, format: .currency(code: "USD"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? TransactionImportDesign.accent : .secondary)
                .imageScale(.medium)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    private var fileSection: some View {
        Section("Files") {
            ForEach(csvURLs, id: \.self) { url in
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(TransactionImportDesign.accent)
                        .frame(width: 28)
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
            }
        }
        .listRowBackground(TransactionImportDesign.surfaceBackground)
    }

    @ViewBuilder
    private var reviewSection: some View {
        if isImporting {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Importing transactions...")
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(TransactionImportDesign.surfaceBackground)
        } else if let preview {
            Section("Review") {
                HStack(spacing: 8) {
                    metric("New", value: preview.importableRows, image: "plus.circle.fill", tint: TransactionImportDesign.accent)
                    metric("Duplicates", value: preview.duplicateRows, image: "square.on.square", tint: .secondary)
                    metric("Skipped", value: preview.invalidRows, image: "exclamationmark.triangle.fill", tint: TransactionImportDesign.attention)
                }
                .padding(.vertical, 2)

                ForEach(preview.files) { file in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.fileName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(file.importableRows) new, \(file.duplicateRows) duplicate, \(file.invalidRows) skipped")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listRowBackground(TransactionImportDesign.surfaceBackground)

            if !preview.sampleRows.isEmpty {
                Section("Sample") {
                    ForEach(preview.sampleRows) { row in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.merchant)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text("\(row.dateText) · \(row.category)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if let amount = row.amount {
                                Text(amount, format: .currency(code: "USD"))
                                    .font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                }
                .listRowBackground(TransactionImportDesign.surfaceBackground)
            }
        } else {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Reading CSV...")
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(TransactionImportDesign.surfaceBackground)
        }
    }

    private func metric(_ title: String, value: Int, image: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: image)
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(TransactionImportDesign.controlBackground, in: RoundedRectangle(cornerRadius: TransactionImportDesign.controlCornerRadius))
    }

    private var completionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("Import Complete", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(TransactionImportDesign.accent)

                if let summary {
                    Text("\(summary.importedRows) transaction\(summary.importedRows == 1 ? "" : "s") imported. \(summary.duplicateRows) duplicate\(summary.duplicateRows == 1 ? "" : "s") skipped.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(TransactionImportDesign.surfaceBackground)
    }

    @ViewBuilder
    private var confirmationButton: some View {
        switch step {
        case .chooseCard:
            Button("Next") {
                withAnimation(.snappy) {
                    step = .review
                }
                refreshPreview()
            }
            .disabled(selectedBill == nil)
        case .review:
            Button("Import") {
                importNow()
            }
            .disabled(selectedBill == nil || isImporting || preview == nil)
        case .complete:
            Button("Done") {
                onFinished(summary)
            }
        }
    }

    private func refreshPreview(for bill: Bill? = nil) {
        let destination = bill ?? selectedBill
        guard let destination else { return }

        do {
            errorMessage = nil
            preview = try withSecurityScopedAccess {
                try previewTransactionCSVFiles(from: csvURLs, for: destination)
            }
        } catch {
            preview = nil
            errorMessage = error.localizedDescription
        }
    }

    private func importNow() {
        guard let selectedBill else { return }
        isImporting = true
        errorMessage = nil

        do {
            let result = try withSecurityScopedAccess {
                try importTransactionCSVFiles(from: csvURLs, to: selectedBill, context: selectedBill.modelContext ?? modelContext)
            }
            summary = result
            withAnimation(.snappy) {
                step = .complete
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isImporting = false
    }

    private func withSecurityScopedAccess<T>(_ work: () throws -> T) throws -> T {
        let accessedURLs = csvURLs.filter { $0.startAccessingSecurityScopedResource() }
        defer {
            for url in accessedURLs {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try work()
    }
}

private enum TransactionImportDesign {
    static let controlCornerRadius = MoneyMapSharedDesign.controlCornerRadius

    static var accent: Color {
        MoneyMapSharedDesign.calmGreen
    }

    static var attention: Color {
        MoneyMapSharedDesign.attentionRed
    }

    static var moneyGradient: LinearGradient {
        MoneyMapSharedDesign.moneyGradient
    }

    static var groupedBackground: Color {
        MoneyMapSharedDesign.groupedBackground
    }

    static var surfaceBackground: Color {
        MoneyMapSharedDesign.surfaceBackground
    }

    static var controlBackground: Color {
        MoneyMapSharedDesign.controlBackground
    }
}
#endif
