//
//  MoneyMapDesign.swift
//  MoneyMap
//
//  Created by Codex on 7/1/26.
//

import SwiftUI

enum MoneyMapAppearanceStyle: String, CaseIterable, Identifiable {
    case warm
    case system

    var id: String { rawValue }

    var name: String {
        switch self {
        case .warm:
            return "Warm"
        case .system:
            return "Graphite"
        }
    }

    var detail: String {
        switch self {
        case .warm:
            return "Softer surfaces that blend with Today."
        case .system:
            return "Darker grouped sections like classic Wallet cards."
        }
    }
}

enum MoneyMapDesign {
    static let appearanceStyleKey = "moneyMapAppearanceStyle"
    static let cornerRadius: CGFloat = 8
    static let sectionCornerRadius: CGFloat = 16
    static let controlCornerRadius: CGFloat = 12
    static let compactSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 12

    static var brandGreen: Color {
        adaptiveColor(
            light: Color(red: 0.07, green: 0.24, blue: 0.16),
            dark: Color(red: 0.58, green: 0.78, blue: 0.62)
        )
    }

    static var deepMoneyGreen: Color {
        adaptiveColor(
            light: Color(red: 0.05, green: 0.20, blue: 0.13),
            dark: Color(red: 0.10, green: 0.22, blue: 0.16)
        )
    }

    static var calmGreen: Color {
        adaptiveColor(
            light: Color(red: 0.16, green: 0.43, blue: 0.29),
            dark: Color(red: 0.48, green: 0.72, blue: 0.52)
        )
    }

    static var sage: Color {
        adaptiveColor(
            light: Color(red: 0.54, green: 0.64, blue: 0.55),
            dark: Color(red: 0.43, green: 0.55, blue: 0.45)
        )
    }

    static var warmNeutral: Color {
        adaptiveColor(
            light: Color(red: 0.96, green: 0.93, blue: 0.86),
            dark: Color(red: 0.16, green: 0.14, blue: 0.11)
        )
    }

    static var warmSurface: Color {
        adaptiveColor(
            light: Color(red: 1.00, green: 0.98, blue: 0.93),
            dark: Color(red: 0.20, green: 0.18, blue: 0.14)
        )
    }

    static var warmRaisedSurface: Color {
        adaptiveColor(
            light: Color(red: 1.00, green: 0.99, blue: 0.96),
            dark: Color(red: 0.24, green: 0.22, blue: 0.17)
        )
    }

    static var attentionRed: Color {
        adaptiveColor(
            light: Color(red: 0.78, green: 0.27, blue: 0.23),
            dark: Color(red: 1.00, green: 0.46, blue: 0.40)
        )
    }

    static var warningGold: Color {
        adaptiveColor(
            light: Color(red: 0.70, green: 0.47, blue: 0.15),
            dark: Color(red: 0.96, green: 0.70, blue: 0.30)
        )
    }

    static var groupedBackground: Color {
        switch appearanceStyle {
        case .warm:
            return warmNeutral
        case .system:
            return systemGroupedBackground
        }
    }

    static var surfaceBackground: Color {
        switch appearanceStyle {
        case .warm:
            return warmSurface
        case .system:
            return systemSecondaryGroupedBackground
        }
    }

    static var controlBackground: Color {
        switch appearanceStyle {
        case .warm:
            return warmRaisedSurface
        case .system:
            return systemTertiaryGroupedBackground
        }
    }

    static var separator: Color {
        adaptiveColor(
            light: Color(red: 0.07, green: 0.24, blue: 0.16).opacity(0.18),
            dark: Color(red: 0.78, green: 0.70, blue: 0.56).opacity(0.18)
        )
    }

    static var moneyGradient: LinearGradient {
        LinearGradient(
            colors: [deepMoneyGreen, calmGreen],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func adaptiveColor(light: Color, dark: Color) -> Color {
        #if os(iOS) || os(tvOS) || os(visionOS)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif os(macOS)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
            return bestMatch == .darkAqua ? NSColor(dark) : NSColor(light)
        })
        #else
        return light
        #endif
    }

    private static var appearanceStyle: MoneyMapAppearanceStyle {
        let rawValue = UserDefaults.standard.string(forKey: appearanceStyleKey)
        return MoneyMapAppearanceStyle(rawValue: rawValue ?? "") ?? .warm
    }

    private static var systemGroupedBackground: Color {
        #if os(iOS) || os(tvOS) || os(visionOS)
        return Color(uiColor: .systemGroupedBackground)
        #elseif os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return warmNeutral
        #endif
    }

    private static var systemSecondaryGroupedBackground: Color {
        #if os(iOS) || os(tvOS) || os(visionOS)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #elseif os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return warmSurface
        #endif
    }

    private static var systemTertiaryGroupedBackground: Color {
        #if os(iOS) || os(tvOS) || os(visionOS)
        return Color(uiColor: .tertiarySystemGroupedBackground)
        #elseif os(macOS)
        return Color(nsColor: .underPageBackgroundColor)
        #else
        return warmRaisedSurface
        #endif
    }
}

extension View {
    func moneyMapGroupedListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(MoneyMapDesign.groupedBackground)
    }

    func moneyMapListSectionBackground() -> some View {
        listRowBackground(MoneyMapDesign.surfaceBackground)
    }
}

struct MoneyMapMoneyText: View {
    let amount: Double
    var font: Font = .headline
    var foregroundStyle: Color = .primary

    var body: some View {
        Text(amount, format: .currency(code: "USD"))
            .font(font)
            .fontDesign(.rounded)
            .monospacedDigit()
            .foregroundStyle(foregroundStyle)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityLabel(MoneyMapFormatters.currencyString(for: amount))
    }
}

struct MoneyMapSummaryRow: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 26, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

struct MoneyMapActionListRow: View {
    let title: String
    let detail: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }
}

struct MoneyMapMetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    var detail: String? = nil
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, minHeight: detail == nil ? 68 : 88, alignment: .topLeading)
        .padding(10)
        .background(MoneyMapDesign.controlBackground, in: RoundedRectangle(cornerRadius: MoneyMapDesign.controlCornerRadius))
        .accessibilityElement(children: .combine)
    }
}

struct MoneyMapStatusLabel: View {
    let message: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
    }
}

struct MoneyMapNeutralButtonLabel: View {
    let title: String
    let systemImage: String
    var iconColor: Color = .accentColor
    var fillsWidth = true

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil)
    }
}

struct MoneyMapActionCardLabel: View {
    let title: String
    let detail: String
    let systemImage: String
    var tint: Color = .accentColor
    var isProminent = false
    var trailingSystemImage = "chevron.right"

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(isProminent ? 0.18 : 0.12))
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 42, height: 38)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 8)

            Image(systemName: trailingSystemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint.opacity(isProminent ? 0.95 : 0.72))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(12)
        .background(MoneyMapDesign.controlBackground, in: RoundedRectangle(cornerRadius: MoneyMapDesign.controlCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MoneyMapDesign.controlCornerRadius, style: .continuous)
                .stroke(isProminent ? tint.opacity(0.38) : MoneyMapDesign.separator.opacity(0.22), lineWidth: 1)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

struct MoneyMapStatusBanner: View {
    let message: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

struct MoneyMapEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}
