import Foundation

/// Stable content identity for window activation. Only navigation identifiers are
/// encoded; financial values and editing drafts remain in their existing owners.
enum MoneyMapWindowContent: Codable, Hashable {
    case wallet(WalletDestination?)
    case goal(UUID)
    case plan

    var tab: ContentView.Tab {
        switch self {
        case .wallet: .wallet
        case .goal: .goals
        case .plan: .plan
        }
    }

    @MainActor
    func prepareNavigation(in manager: DeepLinkManager) {
        switch self {
        case .wallet(let destination): manager.requestedWalletDestination = destination
        case .goal(let id): manager.requestedGoalID = id
        case .plan: break
        }
    }
}

enum WalletDestination: Hashable, Codable, Identifiable {
    case bill(UUID)
    case account(String)
    case cards
    case accounts
    case bills
    case paymentMethods
    case transactions
    case cardUtilization
    case bankSyncSettings
    case cardUpgrade
    case billCalendar

    var id: Self { self }
}
