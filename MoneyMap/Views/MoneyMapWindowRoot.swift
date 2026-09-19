import CoreSpotlight
import SwiftUI

/// Each window owns its navigation, presentations, and incoming routes. Business data
/// and services are shared by the app; resizing never reconstructs this state owner.
struct MoneyMapWindowRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var deepLinkManager = DeepLinkManager()
    let sceneRouter: MoneyMapSceneRouter
    var initialContent: MoneyMapWindowContent? = nil

    var body: some View {
        ContentView(initialWindowContent: initialContent)
            .environmentObject(deepLinkManager)
            .onOpenURL { url in
                deepLinkManager.handle(url: url)
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                if let route = SpotlightIndexer.routeFromSearchableItemActivity(activity) {
                    deepLinkManager.pendingRoute = route
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    sceneRouter.activate(deepLinkManager)
                } else {
                    sceneRouter.deactivate(deepLinkManager)
                }
            }
            .onDisappear {
                sceneRouter.deactivate(deepLinkManager)
            }
    }
}
