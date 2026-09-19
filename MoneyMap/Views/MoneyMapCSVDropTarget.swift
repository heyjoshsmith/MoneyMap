import SwiftUI

struct MoneyMapCSVDropTarget: ViewModifier {
    @ObservedObject var review: MoneyMapCSVReview
    var isEnabled = true
    @State private var isTargeted = false

    private var showsTarget: Bool { isTargeted && isEnabled && review.canAccept }

    func body(content: Content) -> some View {
        content
            .dropDestination(for: MoneyMapCSVFile.self) { files, _ in
                guard isEnabled else { return false }
                return review.accept(files)
            } isTargeted: {
                isTargeted = $0
            }
            .overlay {
                if showsTarget {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(MoneyMapDesign.calmGreen, style: StrokeStyle(lineWidth: 3, dash: [8]))
                        .padding(8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .top) {
                if showsTarget {
                    Label("Review CSV", systemImage: "tray.and.arrow.down")
                        .font(.headline)
                        .padding()
                        .background(.regularMaterial, in: Capsule())
                        .padding()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}
