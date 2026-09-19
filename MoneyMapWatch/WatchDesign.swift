import SwiftUI
import WatchKit

// Watch uses the phone palette with dark, high-contrast surfaces.
enum WatchDesign {
    static let green = MoneyMapSharedDesign.brandGreen
    static let gold = MoneyMapSharedDesign.warningGold
    static let coral = MoneyMapSharedDesign.attentionRed
    static let sage = MoneyMapSharedDesign.sage
    static func money(_ value: Double, code: String = "USD") -> String {
        value.formatted(.currency(code: code))
    }
}

struct WatchMetric: View {
    let title: String
    let value: String
    var detail: String? = nil
    var symbol = "banknote"
    var tint: Color = WatchDesign.green
    var progress: Double? = nil
    @AppStorage("moneyMapAppearanceStyle") private var appearance = "warm"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(tint)
            Text(value).font(.system(.largeTitle, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.55).lineLimit(1).monospacedDigit().privacySensitive()
                .contentTransition(.numericText())
            if let progress { ProgressView(value: min(max(progress, 0), 1)).tint(tint) }
            if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(tint.opacity(dimmed ? 0.04 : 0.12), in: RoundedRectangle(cornerRadius: 20))
        .background(appearance == "warm" ? MoneyMapSharedDesign.surfaceBackground : Color(white: 0.08), in: RoundedRectangle(cornerRadius: 20))
        .animation(reduceMotion || dimmed ? nil : .snappy(duration: 0.3), value: value)
        .accessibilityElement(children: .combine)
    }
}

struct WatchAmountField: View {
    let title: String
    @Binding var amount: Double
    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, value: $amount, format: .number.precision(.fractionLength(0...2)))
                .font(.title3.monospacedDigit())
        }
    }
}
