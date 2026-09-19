import SwiftUI

/// Content dimensions, not device models or orientation, determine the fallback layout.
/// Keep this policy separate from presentation state and financial calculations.
enum MoneyMapAdaptiveLayout {
    static let readableWidth: CGFloat = 760
    static let minimumPaneWidth: CGFloat = 340
    static let paneSpacing: CGFloat = 20

    static func showsCompanion(width: CGFloat, minimumPaneWidth: CGFloat, allowsColumns: Bool) -> Bool {
        allowsColumns && width >= minimumPaneWidth * 2 + paneSpacing
    }
}

/// A primary task with supplementary content. Place this inside navigation and outside
/// scroll containers. Each pane owns its scrolling; the caller owns drafts and selection.
/// Replace the layout implementation with ArrangementView after validating the 27.1 SDK.
struct MoneyMapCompanionLayout<Primary: View, Companion: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var minimumPaneWidth = MoneyMapAdaptiveLayout.minimumPaneWidth

    @ViewBuilder var primary: (Bool) -> Primary
    @ViewBuilder var companion: () -> Companion

    var body: some View {
        GeometryReader { geometry in
            let showsCompanion = MoneyMapAdaptiveLayout.showsCompanion(
                width: geometry.size.width,
                minimumPaneWidth: minimumPaneWidth,
                allowsColumns: horizontalSizeClass != .compact && !dynamicTypeSize.isAccessibilitySize
            )

            // The primary pane stays at the same structural identity as the window resizes.
            HStack(alignment: .top, spacing: MoneyMapAdaptiveLayout.paneSpacing) {
                primary(showsCompanion)
                    .frame(maxWidth: MoneyMapAdaptiveLayout.readableWidth, maxHeight: .infinity)

                if showsCompanion {
                    companion()
                        .frame(maxWidth: MoneyMapAdaptiveLayout.readableWidth, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension View {
    /// Bounds long-form content while keeping backgrounds and native bars edge to edge.
    func moneyMapReadableContent() -> some View {
        frame(maxWidth: MoneyMapAdaptiveLayout.readableWidth)
            .frame(maxWidth: .infinity)
    }
}
