import Foundation

/// Delivers app-wide events to one foreground window. URL and Spotlight events are
/// delivered directly to the window the system selected, not broadcast across windows.
@MainActor
final class MoneyMapSceneRouter {
    private struct Destination {
        weak var manager: DeepLinkManager?
    }

    private var destinations: [Destination] = []
    private let consumePending: () -> MoneyMapRoute?
    private let savePending: (MoneyMapRoute) -> Void

    init(
        consumePending: @escaping () -> MoneyMapRoute? = { PendingRouteStore.consume() },
        savePending: @escaping (MoneyMapRoute) -> Void = { PendingRouteStore.set($0) }
    ) {
        self.consumePending = consumePending
        self.savePending = savePending
    }

    func activate(_ manager: DeepLinkManager) {
        deactivate(manager)
        destinations.append(Destination(manager: manager))
        deliverPendingIfActive()
    }

    func deactivate(_ manager: DeepLinkManager) {
        destinations.removeAll { $0.manager == nil || $0.manager === manager }
    }

    func deliver(_ route: MoneyMapRoute) {
        destinations.removeAll { $0.manager == nil }
        if let manager = destinations.last?.manager {
            manager.pendingRoute = route
        } else {
            savePending(route)
        }
    }

    func deliverPendingIfActive() {
        destinations.removeAll { $0.manager == nil }
        guard let manager = destinations.last?.manager, let route = consumePending() else { return }
        manager.pendingRoute = route
    }
}
