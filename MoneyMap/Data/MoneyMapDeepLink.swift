//
//  MoneyMapDeepLink.swift
//  MoneyMap
//
//  Created by Codex on 3/4/26.
//

import Foundation
import UniformTypeIdentifiers

enum MoneyMapRoute: Equatable {
    case importCSV(URL)
    case openBill(UUID)
    case openGoal(UUID)
    case showUpcomingBills
    case showCardUtilization
    case showRecommendations
}

enum BillsNavigationTarget: String, Identifiable {
    case upcomingBills
    case cardUtilization

    var id: String { rawValue }
}

enum PayNavigationTarget: String, Identifiable {
    case recommendations

    var id: String { rawValue }
}

enum MoneyMapDeepLink {
    static let scheme = "moneymap"

    static func route(from url: URL) -> MoneyMapRoute? {
        if url.isFileURL, isCSVFileURL(url) {
            return .importCSV(url)
        }

        guard url.scheme?.lowercased() == scheme else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = url.host?.lowercased() ?? ""

        switch host {
        case "bill":
            guard let billIDValue = queryValue("id", in: components) ?? url.pathComponents.dropFirst().first,
                  let billID = UUID(uuidString: billIDValue) else {
                return nil
            }
            return .openBill(billID)

        case "goal":
            guard let goalIDValue = queryValue("id", in: components) ?? url.pathComponents.dropFirst().first,
                  let goalID = UUID(uuidString: goalIDValue) else {
                return nil
            }
            return .openGoal(goalID)

        case "action":
            guard let actionID = queryValue("id", in: components),
                  let action = MoneyMapAction(rawValue: actionID) else {
                return nil
            }
            switch action {
            case .showUpcomingBills:
                return .showUpcomingBills
            case .showCardUtilization:
                return .showCardUtilization
            case .showRecommendations:
                return .showRecommendations
            default:
                return nil
            }

        default:
            return nil
        }
    }

    static func url(for route: MoneyMapRoute) -> URL? {
        switch route {
        case .importCSV(let fileURL):
            return fileURL
        case .openBill(let billID):
            var components = URLComponents()
            components.scheme = scheme
            components.host = "bill"
            components.queryItems = [URLQueryItem(name: "id", value: billID.uuidString)]
            return components.url
        case .openGoal(let goalID):
            var components = URLComponents()
            components.scheme = scheme
            components.host = "goal"
            components.queryItems = [URLQueryItem(name: "id", value: goalID.uuidString)]
            return components.url
        case .showUpcomingBills:
            return actionURL(for: .showUpcomingBills)
        case .showCardUtilization:
            return actionURL(for: .showCardUtilization)
        case .showRecommendations:
            return actionURL(for: .showRecommendations)
        }
    }

    private static func queryValue(_ name: String, in components: URLComponents?) -> String? {
        components?.queryItems?.first(where: { $0.name == name })?.value
    }

    private static func actionURL(for action: MoneyMapAction) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "action"
        components.queryItems = [URLQueryItem(name: "id", value: action.rawValue)]
        return components.url
    }

    private static func isCSVFileURL(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "csv" {
            return true
        }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type.conforms(to: .commaSeparatedText)
        }
        return false
    }
}

@MainActor
final class DeepLinkManager: ObservableObject {
    @Published var pendingRoute: MoneyMapRoute?
    @Published var requestedBillID: UUID?
    @Published var requestedGoalID: UUID?
    @Published var requestedBillsDestination: BillsNavigationTarget?
    @Published var requestedPayDestination: PayNavigationTarget?

    func handle(url: URL) {
        guard let route = MoneyMapDeepLink.route(from: url) else {
            return
        }
        pendingRoute = route
        if case .openBill(let billID) = route {
            requestedBillID = billID
        } else if case .openGoal(let goalID) = route {
            requestedGoalID = goalID
        } else if case .showUpcomingBills = route {
            requestedBillsDestination = .upcomingBills
        } else if case .showCardUtilization = route {
            requestedBillsDestination = .cardUtilization
        } else if case .showRecommendations = route {
            requestedPayDestination = .recommendations
        }
    }

    func clearPendingRoute() {
        pendingRoute = nil
    }
}
