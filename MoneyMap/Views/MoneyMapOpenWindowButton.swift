import SwiftUI

/// Window availability comes from the current scene, never a device-model check.
struct MoneyMapOpenWindowButton: View {
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Environment(\.openWindow) private var openWindow
    let content: MoneyMapWindowContent

    var body: some View {
        if supportsMultipleWindows {
            Button("Open in New Window", systemImage: "rectangle.badge.plus") {
                openWindow(value: content)
            }
        }
    }
}
