import AppIntents
import SwiftUI
import WidgetKit
import SwiftData
import RelevanceKit

@main struct MoneyMapWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        MoneyMapWatchWidget()
        MoneyMapWatchControl()
        MoneyMapTimelyWidget()
    }
}

enum WatchWidgetContent: String, AppEnum {
    case today, payday, bill, account, card, spending, goal
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Content"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .today: "Today", .payday: "Payday", .bill: "Bill", .account: "Account Balance",
        .card: "Card Utilization", .spending: "Spending", .goal: "Goal"]
}
enum WatchWidgetDisplay: String, AppEnum {
    case automatic, amount, countdown, percentage, count
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Display"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .automatic: "Automatic", .amount: "Amount", .countdown: "Countdown", .percentage: "Percentage", .count: "Count"]
}
enum WatchWidgetPeriod: String, AppEnum {
    case today, week, month, cycle
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Period"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.today: "Today", .week: "This Week", .month: "This Month", .cycle: "Pay Cycle"]
}
enum WatchWidgetColor: String, AppEnum {
    case theme, green, gold, sage, coral
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Color"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.theme: "MoneyMap", .green: "Green", .gold: "Gold", .sage: "Sage", .coral: "Coral"]
    var color: Color {
        switch self {
        case .theme, .green: MoneyMapSharedDesign.brandGreen
        case .gold: MoneyMapSharedDesign.warningGold
        case .sage: MoneyMapSharedDesign.sage
        case .coral: MoneyMapSharedDesign.attentionRed
        }
    }
}

struct WatchFinanceEntity: AppEntity {
    var id: String
    var name: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "MoneyMap Item"
    static var defaultQuery = WatchFinanceEntityQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct WatchFinanceEntityQuery: EntityQuery {
    @IntentParameterDependency<WatchWidgetConfiguration>(\.$content) var widget

    func entities(for identifiers: [String]) async throws -> [WatchFinanceEntity] {
        (WatchSnapshotStore.read()?.items ?? []).filter { identifiers.contains($0.id) }.map { .init(id: $0.id, name: $0.title) }
    }
    func suggestedEntities() async throws -> [WatchFinanceEntity] {
        (WatchSnapshotStore.read()?.items ?? []).filter { item in
            if let kind = widget?.content.rawValue { return item.kind == kind }
            return ["bill", "goal", "account", "card"].contains(item.kind)
        }.map { .init(id: $0.id, name: $0.title) }
    }
}

struct WatchDisplayOptions: DynamicOptionsProvider {
    @IntentParameterDependency<WatchWidgetConfiguration>(\.$content) var widget
    func results() async throws -> [WatchWidgetDisplay] {
        switch widget?.content ?? .today {
        case .today, .spending: return [.automatic, .amount, .count]
        case .payday, .bill: return [.automatic, .amount, .countdown]
        case .goal: return [.automatic, .amount, .countdown, .percentage]
        case .account: return [.automatic, .amount]
        case .card: return [.automatic, .amount, .percentage]
        }
    }
}

struct WatchWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "MoneyMap"
    static var description = IntentDescription("Choose what to see at a glance.")
    @Parameter(title: "Content", default: .today) var content: WatchWidgetContent
    @Parameter(title: "Item") var item: WatchFinanceEntity?
    @Parameter(title: "Display", default: .automatic, optionsProvider: WatchDisplayOptions()) var display: WatchWidgetDisplay
    @Parameter(title: "Period", default: .cycle) var period: WatchWidgetPeriod
    @Parameter(title: "Hide Amounts", default: false) var hideAmounts: Bool
    @Parameter(title: "Color", default: .theme) var color: WatchWidgetColor
}
struct WatchWidgetEntry: TimelineEntry {
    var date: Date
    var configuration: WatchWidgetConfiguration
    var snapshot: WatchSnapshot?
}
struct WatchWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WatchWidgetEntry {
        .init(date: .now, configuration: .init(), snapshot: .init(updatedAt: .now, items: [.init(id: "today", kind: "today", title: "Bills before payday", amount: 245, count: 3, route: "bills")]))
    }
    func snapshot(for configuration: WatchWidgetConfiguration, in context: Context) async -> WatchWidgetEntry {
        .init(date: .now, configuration: configuration, snapshot: WatchSnapshotStore.read())
    }
    func timeline(for configuration: WatchWidgetConfiguration, in context: Context) async -> Timeline<WatchWidgetEntry> {
        await MainActor.run {
            if let container = try? MoneyMapSharedContainerFactory.make() {
                try? WatchSnapshotStore.publish(context: ModelContext(container), reloadWidgets: false)
            }
        }
        let now = Date()
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
        return Timeline(entries: [.init(date: now, configuration: configuration, snapshot: WatchSnapshotStore.read())], policy: .after(min(midnight, now.addingTimeInterval(3600))))
    }
    func recommendations() -> [AppIntentRecommendation<WatchWidgetConfiguration>] { [] }
}
struct MoneyMapWatchWidget: Widget {
    let kind = "MoneyMapWatchSummary"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WatchWidgetConfiguration.self, provider: WatchWidgetProvider()) { entry in
            WatchWidgetView(entry: entry).containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("MoneyMap")
        .description("Your bills, balances, payday, spending, and goals.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}
struct WatchWidgetView: View {
    let entry: WatchWidgetEntry
    @Environment(\.widgetFamily) private var family
    private var item: WatchSnapshotItem? {
        let config = entry.configuration
        let items = entry.snapshot?.items ?? []
        if config.content == .spending { return items.first { $0.id == "spending/\(config.period.rawValue)" } }
        if let selected = config.item, [.bill, .account, .goal, .card].contains(config.content) {
            return items.first { $0.id == selected.id && $0.kind == config.content.rawValue }
        }
        return items.first { $0.kind == config.content.rawValue }
    }
    private var value: String {
        guard let item else { return "—" }
        let display = entry.configuration.display
        if entry.configuration.content == .bill, item.status == "Paid", [.automatic, .countdown].contains(display) { return "Paid" }
        if display == .count { return item.count.map(String.init) ?? "—" }
        if display == .countdown || (display == .automatic && entry.configuration.content == .payday) {
            guard let date = item.date else { return "—" }
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: entry.date), to: Calendar.current.startOfDay(for: date)).day ?? 0
            return days == 0 ? "Today" : days < 0 ? "Overdue" : "\(days)d"
        }
        if display == .percentage || (display == .automatic && [.goal, .card].contains(entry.configuration.content)) {
            return item.progress?.formatted(.percent.precision(.fractionLength(0))) ?? "—"
        }
        if entry.configuration.hideAmounts { return "••••" }
        return item.amount?.formatted(.currency(code: item.currency).precision(.fractionLength(0))) ?? "—"
    }
    private var symbol: String {
        switch entry.configuration.content {
        case .today, .bill: "calendar"
        case .payday: "banknote"
        case .account: "wallet.bifold"
        case .card: "creditcard"
        case .spending: "cart"
        case .goal: "target"
        }
    }
    private var subtitle: String {
        guard let snapshot = entry.snapshot else { return "Open MoneyMap" }
        if item == nil { return "Choose another item" }
        if entry.date.timeIntervalSince(snapshot.updatedAt) > 86400 { return "Updated \(snapshot.updatedAt.formatted(.dateTime.month(.abbreviated).day()))" }
        if let date = item?.date { return date.formatted(.dateTime.month(.abbreviated).day()) }
        return "MoneyMap"
    }
    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("\(item?.title ?? "MoneyMap"): \(value)", systemImage: symbol)
            case .accessoryCorner:
                Text(value).font(.system(.title3, design: .rounded, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .widgetLabel { Text(item?.title ?? "MoneyMap") }
            case .accessoryCircular:
                Gauge(value: min(max(item?.progress ?? 0, 0), 1)) {
                    Image(systemName: symbol)
                } currentValueLabel: { Text(value).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.5) }
                    .gaugeStyle(.accessoryCircular)
            default:
                HStack {
                    Image(systemName: symbol).font(.title2).widgetAccentable()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item?.title ?? "MoneyMap").font(.caption).lineLimit(1)
                        Text(value).font(.system(.title2, design: .rounded, weight: .bold)).minimumScaleFactor(0.5).lineLimit(1)
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .foregroundStyle(entry.configuration.color.color)
        .privacySensitive(!entry.configuration.hideAmounts)
        .widgetURL(URL(string: "moneymap-watch://\(item?.route ?? "wallet")"))
        .accessibilityLabel("\(item?.title ?? "MoneyMap"), \(value), \(subtitle)")
    }
}

enum WatchQuickAction: String, AppEnum {
    case spending, payment, contribution, wallet
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Action"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.spending: "Record Spending", .payment: "Record Payment", .contribution: "Add Contribution", .wallet: "Open Wallet"]
    var route: String { switch self { case .spending: "record"; case .payment: "payment"; case .contribution: "contribute"; case .wallet: "wallet" } }
    var symbol: String { switch self { case .spending: "cart.badge.plus"; case .payment: "checkmark.circle"; case .contribution: "target"; case .wallet: "wallet.bifold" } }
    var title: String { switch self { case .spending: "Record Spending"; case .payment: "Record Payment"; case .contribution: "Add Contribution"; case .wallet: "Open Wallet" } }
}
struct WatchControlConfiguration: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "MoneyMap Action"
    @Parameter(title: "Action", default: .spending) var action: WatchQuickAction
    @Parameter(title: "Item") var item: WatchFinanceEntity?
}
struct WatchControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: WatchControlConfiguration) -> WatchControlConfiguration { configuration }
    func currentValue(configuration: WatchControlConfiguration) async throws -> WatchControlConfiguration { configuration }
}
struct MoneyMapWatchControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "MoneyMapWatchAction", provider: WatchControlProvider()) { config in
            ControlWidgetButton(action: OpenWatchFinanceIntent(route: route(config))) {
                Label(config.action.title, systemImage: config.action.symbol)
            }
        }.displayName("MoneyMap Action").description("Open a financial action on your Watch.")
    }
    private func route(_ config: WatchControlConfiguration) -> String {
        if let id = config.item?.id {
            if config.action == .payment { return "bill/\(id)" }
            if config.action == .contribution { return "goal/\(id)" }
        }
        return config.action.route
    }
}

struct MoneyMapTimelyEntry: RelevanceEntry {
    var configuration: WatchWidgetConfiguration
    var snapshot: WatchSnapshot?
}
struct MoneyMapTimelyProvider: RelevanceEntriesProvider {
    func relevance() async -> WidgetRelevance<WatchWidgetConfiguration> {
        let defaults = UserDefaults(suiteName: WatchSnapshotStore.suite)
        guard defaults?.object(forKey: "watchSmartSuggestions") as? Bool ?? true else { return WidgetRelevance([]) }
        let calendar = Calendar.current
        let attributes: [WidgetRelevanceAttribute<WatchWidgetConfiguration>] = (WatchSnapshotStore.read()?.items ?? [])
            .filter { ["bill", "payday"].contains($0.kind) }.prefix(10).compactMap { item in
                guard let date = item.date,
                      let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)),
                      let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)), end > .now else { return nil }
                let configuration = WatchWidgetConfiguration()
                configuration.content = item.kind == "bill" ? .bill : .payday
                configuration.item = .init(id: item.id, name: item.title)
                configuration.display = .countdown
                configuration.hideAmounts = true
                return WidgetRelevanceAttribute(configuration: configuration, context: .date(range: start...end, kind: .scheduled))
            }
        return WidgetRelevance(attributes)
    }
    func entry(configuration: WatchWidgetConfiguration, context: Context) async throws -> MoneyMapTimelyEntry {
        .init(configuration: configuration, snapshot: WatchSnapshotStore.read())
    }
    func placeholder(context: Context) -> MoneyMapTimelyEntry {
        .init(configuration: .init(), snapshot: nil)
    }
}
struct MoneyMapTimelyWidget: Widget {
    var body: some WidgetConfiguration {
        RelevanceConfiguration(kind: "MoneyMapWatchTimely", provider: MoneyMapTimelyProvider()) { entry in
            WatchWidgetView(entry: .init(date: .now, configuration: entry.configuration, snapshot: entry.snapshot))
                .containerBackground(for: .widget) { Color.black }
        }.configurationDisplayName("Timely MoneyMap").description("Bills and payday when they matter.")
    }
}
