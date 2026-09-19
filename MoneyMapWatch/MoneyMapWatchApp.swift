import SwiftData
import SwiftUI

@main
struct MoneyMapWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchNotificationDelegate.self) private var delegate
    @State private var container: ModelContainer?
    @State private var failure: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    WatchDashboardView().modelContainer(container)
                } else if let failure {
                    VStack(spacing: 12) {
                        Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
                        Text("Unable to Open Data").font(.headline)
                        Text(failure).font(.caption)
                        Button("Try Again", action: openStore)
                    }.padding()
                } else { ProgressView("Opening MoneyMap") }
            }
            .tint(WatchDesign.green)
            .task { if container == nil { openStore() } }
        }
    }
    private func openStore() {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--watch-preview") {
            do { container = try WatchPreviewData.make(); failure = nil } catch { failure = error.localizedDescription }
            return
        }
        #endif
        do { container = try MoneyMapSharedContainerFactory.make(); failure = nil }
        catch { failure = error.localizedDescription }
    }
}
