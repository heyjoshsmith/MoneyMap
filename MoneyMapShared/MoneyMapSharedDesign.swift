//
//  MoneyMapSharedDesign.swift
//  MoneyMapShared
//
//  Created by Codex on 7/22/26.
//

import SwiftUI

public enum MoneyMapSharedAppearanceStyle: String {
    case warm
    case system
}

public enum MoneyMapSharedDesign {
    public static let appearanceStyleKey = "moneyMapAppearanceStyle"
    public static let cornerRadius: CGFloat = 8
    public static let sectionCornerRadius: CGFloat = 16
    public static let controlCornerRadius: CGFloat = 12
    public static let compactSpacing: CGFloat = 8
    public static let sectionSpacing: CGFloat = 12

    public static var brandGreen: Color {
        adaptiveColor(
            light: Color(red: 0.07, green: 0.24, blue: 0.16),
            dark: Color(red: 0.58, green: 0.78, blue: 0.62)
        )
    }

    public static var deepMoneyGreen: Color {
        adaptiveColor(
            light: Color(red: 0.05, green: 0.20, blue: 0.13),
            dark: Color(red: 0.10, green: 0.22, blue: 0.16)
        )
    }

    public static var calmGreen: Color {
        adaptiveColor(
            light: Color(red: 0.16, green: 0.43, blue: 0.29),
            dark: Color(red: 0.48, green: 0.72, blue: 0.52)
        )
    }

    public static var sage: Color {
        adaptiveColor(
            light: Color(red: 0.54, green: 0.64, blue: 0.55),
            dark: Color(red: 0.43, green: 0.55, blue: 0.45)
        )
    }

    public static var groupedBackground: Color {
        switch appearanceStyle {
        case .warm:
            return warmNeutral
        case .system:
            return systemGroupedBackground
        }
    }

    public static var surfaceBackground: Color {
        switch appearanceStyle {
        case .warm:
            return warmSurface
        case .system:
            return systemSecondaryGroupedBackground
        }
    }

    public static var controlBackground: Color {
        switch appearanceStyle {
        case .warm:
            return warmRaisedSurface
        case .system:
            return systemTertiaryGroupedBackground
        }
    }

    public static var attentionRed: Color {
        adaptiveColor(
            light: Color(red: 0.78, green: 0.27, blue: 0.23),
            dark: Color(red: 1.00, green: 0.46, blue: 0.40)
        )
    }

    public static var warningGold: Color {
        adaptiveColor(
            light: Color(red: 0.70, green: 0.47, blue: 0.15),
            dark: Color(red: 0.96, green: 0.70, blue: 0.30)
        )
    }

    public static var separator: Color {
        adaptiveColor(
            light: Color(red: 0.07, green: 0.24, blue: 0.16).opacity(0.18),
            dark: Color(red: 0.78, green: 0.70, blue: 0.56).opacity(0.18)
        )
    }

    public static var moneyGradient: LinearGradient {
        LinearGradient(
            colors: [deepMoneyGreen, calmGreen],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static func setAppearanceStyleRawValue(_ rawValue: String) {
        UserDefaults.standard.set(rawValue, forKey: appearanceStyleKey)
        appGroupUserDefaults?.set(rawValue, forKey: appearanceStyleKey)
    }

    private static var appearanceStyle: MoneyMapSharedAppearanceStyle {
        let rawValue = UserDefaults.standard.string(forKey: appearanceStyleKey)
            ?? appGroupUserDefaults?.string(forKey: appearanceStyleKey)
        return MoneyMapSharedAppearanceStyle(rawValue: rawValue ?? "") ?? .warm
    }

    private static var appGroupUserDefaults: UserDefaults? {
        UserDefaults(suiteName: "group.com.heyjoshsmith.MoneyMap")
    }

    private static var warmNeutral: Color {
        adaptiveColor(
            light: Color(red: 0.96, green: 0.93, blue: 0.86),
            dark: Color(red: 0.16, green: 0.14, blue: 0.11)
        )
    }

    private static var warmSurface: Color {
        adaptiveColor(
            light: Color(red: 1.00, green: 0.98, blue: 0.93),
            dark: Color(red: 0.20, green: 0.18, blue: 0.14)
        )
    }

    private static var warmRaisedSurface: Color {
        adaptiveColor(
            light: Color(red: 1.00, green: 0.99, blue: 0.96),
            dark: Color(red: 0.24, green: 0.22, blue: 0.17)
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
