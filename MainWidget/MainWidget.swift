//
//  MainWidget.swift
//  MainWidget
//
//  Created by Josh Smith on 3/4/26.
//

import SwiftData
import SwiftUI
import WidgetKit
import MoneyMapShared

struct WidgetBillSummary: Equatable {
    let id: UUID
    let name: String
    let dueDate: Date
    let amount: Double
    let category: BillCategory?
    let autopayEnabled: Bool
    let gracePeriodDays: Int?

    init(
        id: UUID,
        name: String,
        dueDate: Date,
        amount: Double,
        category: BillCategory?,
        autopayEnabled: Bool = false,
        gracePeriodDays: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.dueDate = dueDate
        self.amount = amount
        self.category = category
        self.autopayEnabled = autopayEnabled
        self.gracePeriodDays = gracePeriodDays
    }
}

enum WidgetFormatters {
    static func currency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: amount)) ?? "$0"
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func compactCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = amount.rounded() == amount ? 0 : 2
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: amount)) ?? "$0"
    }
}

private enum WidgetDeepLink {
    static func upcomingBillsURL() -> URL? {
        actionURL("show_upcoming_bills")
    }

    static func cardUtilizationURL() -> URL? {
        actionURL("show_card_utilization")
    }

    static func recommendationsURL() -> URL? {
        actionURL("show_recommendations")
    }

    static func billURL(_ id: UUID) -> URL? {
        var components = URLComponents()
        components.scheme = "moneymap"
        components.host = "bill"
        components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        return components.url
    }

    private static func actionURL(_ id: String) -> URL? {
        var components = URLComponents()
        components.scheme = "moneymap"
        components.host = "action"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url
    }
}

private enum WidgetPalette {
    static let payoffGradient = LinearGradient(
        colors: [.green, .blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let billCardBackground = LinearGradient(
        colors: [Color(red: 0.10, green: 0.42, blue: 0.28), Color(red: 0.09, green: 0.20, blue: 0.39)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func accent(for category: BillCategory?) -> Color {
        switch category {
        case .creditCard:
            return .blue
        case .rent:
            return .green
        case .utilities:
            return .yellow
        case .insurance:
            return .orange
        case .subscription:
            return .purple
        case .groceries:
            return .red
        case .transportation:
            return .pink
        case .phone:
            return .mint
        case .internet:
            return .indigo
        case .entertainment:
            return .teal
        case .other, .none:
            return .gray
        @unknown default:
            return .gray
        }
    }

    static func icon(for category: BillCategory?) -> String {
        category?.icon ?? "calendar"
    }
}

private enum WidgetStore {
    static func context() throws -> ModelContext {
        let container = try MoneyMapSharedContainerFactory.make()
        return ModelContext(container)
    }

    static func fetchNextPayday() -> Date? {
        guard let context = try? context() else { return nil }
        let configs = (try? context.fetch(FetchDescriptor<PaydayConfig>())) ?? []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return configs
            .compactMap(\.nextPayday)
            .map { advancePaydayIfNeeded($0, today: today, calendar: calendar) }
            .sorted()
            .first
    }

    static func fetchUpcomingBills(limit: Int? = nil) -> [WidgetBillSummary] {
        guard let context = try? context() else { return [] }
        let bills = (try? context.fetch(FetchDescriptor<Bill>())) ?? []

        let summaries: [WidgetBillSummary] = bills
            .compactMap { bill -> WidgetBillSummary? in
                guard bill.datePaid == nil, let dueDate = bill.dueDate else { return nil }
                return WidgetBillSummary(
                    id: bill.id,
                    name: bill.name ?? "Bill",
                    dueDate: dueDate,
                    amount: bill.amount ?? 0,
                    category: bill.category,
                    autopayEnabled: bill.autopayEnabled,
                    gracePeriodDays: bill.gracePeriodDays
                )
            }
            .sorted { lhs, rhs in
                if lhs.dueDate == rhs.dueDate {
                    return lhs.name < rhs.name
                }
                return lhs.dueDate < rhs.dueDate
            }

        guard let limit else {
            return summaries
        }

        return Array(summaries.prefix(limit))
    }

    private static func advancePaydayIfNeeded(_ payday: Date, today: Date, calendar: Calendar) -> Date {
        var current = calendar.startOfDay(for: payday)
        while current < today {
            current = calendar.date(byAdding: .day, value: 14, to: current) ?? current
        }
        return current
    }

    static func totalDue(_ bills: [WidgetBillSummary]) -> Double {
        bills.reduce(0) { $0 + $1.amount }
    }

    static func overdueCount(_ bills: [WidgetBillSummary]) -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        return bills.filter { Calendar.current.startOfDay(for: $0.dueDate) < today }.count
    }
}

struct MainWidgetEntry: TimelineEntry {
    let date: Date
}

struct MainWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MainWidgetEntry {
        MainWidgetEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (MainWidgetEntry) -> Void) {
        completion(MainWidgetEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MainWidgetEntry>) -> Void) {
        let now = Date()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now
        completion(Timeline(entries: [MainWidgetEntry(date: now)], policy: .after(nextRefresh)))
    }
}

struct MainWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: MainWidgetProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Plan Your Money")
                        .font(family == .systemSmall ? .headline.weight(.bold) : .title3.weight(.bold))
                    Text("Open the right view fast")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Text("MAP")
                    .font(.caption2.weight(.black))
                    .tracking(1.2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.16))
                    .clipShape(Capsule())
            }

            VStack(spacing: 8) {
                if let upcomingURL = WidgetDeepLink.upcomingBillsURL() {
                    Link(destination: upcomingURL) {
                        WidgetActionPill(
                            title: "Upcoming Bills",
                            subtitle: "Due dates and cash needs",
                            systemImage: "calendar.badge.clock"
                        )
                    }
                }

                if let utilizationURL = WidgetDeepLink.cardUtilizationURL() {
                    Link(destination: utilizationURL) {
                        WidgetActionPill(
                            title: "Card Utilization",
                            subtitle: "Balances and usage",
                            systemImage: "chart.pie"
                        )
                    }
                }

                if family != .systemSmall, let recommendationsURL = WidgetDeepLink.recommendationsURL() {
                    Link(destination: recommendationsURL) {
                        WidgetActionPill(
                            title: "Recommendations",
                            subtitle: "Open today's plan",
                            systemImage: "wand.and.stars"
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .foregroundStyle(.white)
    }
}

private struct WidgetActionPill: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            Image(systemName: "arrow.up.forward")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                }
        )
    }
}

struct MainWidget: Widget {
    let kind: String = "MainWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MainWidgetProvider()) { entry in
            if #available(iOS 17.0, macOS 14.0, *) {
                MainWidgetEntryView(entry: entry)
                    .containerBackground(for: .widget) {
                        WidgetPalette.payoffGradient
                    }
            } else {
                MainWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .contentMarginsDisabled()
        .configurationDisplayName("MoneyMap Actions")
        .description("Quickly jump to bills and utilization flows.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PaydayCountdownEntry: TimelineEntry {
    let date: Date
    let nextPayday: Date?
}

struct PaydayCountdownProvider: TimelineProvider {
    func placeholder(in context: Context) -> PaydayCountdownEntry {
        PaydayCountdownEntry(date: .now, nextPayday: Calendar.current.date(byAdding: .day, value: 5, to: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (PaydayCountdownEntry) -> Void) {
        completion(PaydayCountdownEntry(date: .now, nextPayday: WidgetStore.fetchNextPayday()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PaydayCountdownEntry>) -> Void) {
        let now = Date()
        let entry = PaydayCountdownEntry(date: now, nextPayday: WidgetStore.fetchNextPayday())
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 6, to: now) ?? now.addingTimeInterval(21600)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct PaydayCountdownWidgetView: View {
    var entry: PaydayCountdownEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next Payday")
                        .font(.headline.weight(.bold))
                    Text("Cash planning checkpoint")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Image(systemName: "banknote.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if let nextPayday = entry.nextPayday {
                VStack(alignment: .leading, spacing: 10) {
                    Text(relativeCountdown(for: nextPayday))
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Date")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            Text(nextPayday, format: .dateTime.month(.abbreviated).day().year())
                                .font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("Cycle")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            Text(cycleLabel(for: nextPayday))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .padding(10)
                    .background(.white.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Time until payday")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.74))
                            Spacer()
                            Text(progressLabel(for: nextPayday))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                        Capsule()
                            .fill(.white.opacity(0.22))
                            .frame(height: 9)
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    Capsule()
                                        .fill(.white.opacity(0.92))
                                        .frame(width: progressWidth(for: nextPayday, availableWidth: proxy.size.width), height: 9)
                                }
                            }
                    }
                }
            } else {
                Text("Not set")
                    .font(.title3.weight(.semibold))
                Text("Open MoneyMap to choose your next payday.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .foregroundStyle(.white)
        .widgetURL(WidgetDeepLink.recommendationsURL())
    }

    private func relativeCountdown(for date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<0:
            return "Needs updating"
        case 0:
            return "Today"
        case 1:
            return "Tomorrow"
        default:
            return "In \(days) days"
        }
    }

    private func progressWidth(for date: Date, availableWidth: CGFloat) -> CGFloat {
        let days = max(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0, 0)
        let clamped = min(max(days, 0), 14)
        let ratio = CGFloat(14 - clamped) / 14
        return min(availableWidth, max(18, availableWidth * ratio))
    }

    private func cycleLabel(for date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0
        switch days {
        case 0...3:
            return "Very Soon"
        case 4...7:
            return "This Week"
        default:
            return "Next Cycle"
        }
    }

    private func progressLabel(for date: Date) -> String {
        let days = max(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0, 0)
        return "\(min(days, 14))/14 days"
    }
}

struct PaydayCountdownWidget: Widget {
    let kind: String = "PaydayCountdownWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PaydayCountdownProvider()) { entry in
            if #available(iOS 17.0, macOS 14.0, *) {
                PaydayCountdownWidgetView(entry: entry)
                    .containerBackground(for: .widget) {
                        WidgetPalette.payoffGradient
                    }
            } else {
                PaydayCountdownWidgetView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Next Payday")
        .description("Shows your next payday and countdown.")
        .supportedFamilies([.systemSmall])
    }
}

struct NextBillEntry: TimelineEntry {
    let date: Date
    let bill: WidgetBillSummary?
}

struct NextBillProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextBillEntry {
        NextBillEntry(
            date: .now,
            bill: WidgetBillSummary(
                id: UUID(),
                name: "Rent",
                dueDate: Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now,
                amount: 1450,
                category: .rent,
                autopayEnabled: true,
                gracePeriodDays: 3
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NextBillEntry) -> Void) {
        completion(NextBillEntry(date: .now, bill: WidgetStore.fetchUpcomingBills(limit: 1).first))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextBillEntry>) -> Void) {
        let now = Date()
        let entry = NextBillEntry(date: now, bill: WidgetStore.fetchUpcomingBills(limit: 1).first)
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 3, to: now) ?? now.addingTimeInterval(10800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct NextBillWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: NextBillEntry

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumBody
            } else {
                smallBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .foregroundStyle(.white)
        .widgetURL(entry.bill.flatMap { WidgetDeepLink.billURL($0.id) } ?? WidgetDeepLink.upcomingBillsURL())
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let bill = entry.bill {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Next Bill Due")
                            .font(.headline.weight(.bold))
                        Text(categoryLabel(for: bill.category))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    Spacer()
                    Image(systemName: WidgetPalette.icon(for: bill.category))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(WidgetPalette.accent(for: bill.category).opacity(0.32))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(bill.name)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Amount due")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.72))
                            Text(WidgetFormatters.compactCurrency(bill.amount))
                                .font(.title3.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        Spacer()
                        Text(WidgetFormatters.shortDate(bill.dueDate))
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.14))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 12) {
                    BillMetricBadge(
                        title: "Status",
                        value: relativeBillDueText(for: bill.dueDate),
                        systemImage: "calendar.badge.clock",
                        tint: statusTint(for: bill.dueDate, category: bill.category)
                    )
                    BillMetricBadge(
                        title: bill.autopayEnabled ? "Pay" : "Priority",
                        value: bill.autopayEnabled ? "Autopay" : priorityLabel(for: bill.dueDate),
                        systemImage: bill.autopayEnabled ? "arrow.triangle.2.circlepath" : "exclamationmark.circle",
                        tint: .white
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Next Bill Due")
                        .font(.headline.weight(.bold))
                    Text("No upcoming bills")
                        .font(.title3.weight(.bold))
                    Text("You're clear for now.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }

    private var mediumBody: some View {
        HStack(alignment: .top, spacing: 14) {
            if let bill = entry.bill {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: WidgetPalette.icon(for: bill.category))
                            .font(.caption.weight(.bold))
                            .frame(width: 28, height: 28)
                            .background(WidgetPalette.accent(for: bill.category).opacity(0.28))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        Text(categoryLabel(for: bill.category))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.78))
                    }

                    Text(bill.name)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    Text(relativeBillDueText(for: bill.dueDate))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(statusTint(for: bill.dueDate, category: bill.category))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Amount due")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(WidgetFormatters.compactCurrency(bill.amount))
                        .font(.title2.weight(.heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Divider()
                        .overlay(.white.opacity(0.25))

                    BillInfoRow(title: "Date", value: WidgetFormatters.shortDate(bill.dueDate), systemImage: "calendar")
                    BillInfoRow(
                        title: bill.autopayEnabled ? "Payment" : "Priority",
                        value: bill.autopayEnabled ? "Autopay" : priorityLabel(for: bill.dueDate),
                        systemImage: bill.autopayEnabled ? "arrow.triangle.2.circlepath" : "exclamationmark.circle"
                    )
                    if let gracePeriodDays = bill.gracePeriodDays, gracePeriodDays > 0 {
                        BillInfoRow(title: "Grace", value: "\(gracePeriodDays)d", systemImage: "clock")
                    }
                }
                .padding(10)
                .frame(width: 142, alignment: .leading)
                .background(.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Next Bill Due")
                        .font(.headline.weight(.bold))
                    Text("No upcoming bills")
                        .font(.title2.weight(.heavy))
                    Text("You're clear for now.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
            }
        }
    }

    private func relativeBillDueText(for date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<0:
            return "\(abs(days))d overdue"
        case 0:
            return "Due today"
        case 1:
            return "Due tomorrow"
        default:
            return "Due in \(days) days"
        }
    }

    private func categoryLabel(for category: BillCategory?) -> String {
        switch category {
        case .creditCard:
            return "Credit card"
        case .rent:
            return "Housing"
        case .utilities:
            return "Utilities"
        case .insurance:
            return "Insurance"
        case .subscription:
            return "Subscription"
        case .groceries:
            return "Groceries"
        case .transportation:
            return "Transportation"
        case .phone:
            return "Phone"
        case .internet:
            return "Internet"
        case .entertainment:
            return "Entertainment"
        case .other, .none:
            return "Bill"
        @unknown default:
            return "Bill"
        }
    }

    private func priorityLabel(for dueDate: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: dueDate)).day ?? 0
        switch days {
        case ...1:
            return "High"
        case 2...5:
            return "Soon"
        default:
            return "Planned"
        }
    }

    private func statusTint(for dueDate: Date, category: BillCategory?) -> Color {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: dueDate)).day ?? 0
        if days < 0 {
            return .red
        }
        return WidgetPalette.accent(for: category)
    }
}

private struct BillInfoRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .frame(width: 14)
                .foregroundStyle(.white.opacity(0.78))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.64))
            Spacer(minLength: 4)
            Text(value)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct BillMetricBadge: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.68))
                Text(value)
                    .font(.caption.weight(.bold))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct NextBillWidget: Widget {
    let kind: String = "NextBillWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextBillProvider()) { entry in
            if #available(iOS 17.0, macOS 14.0, *) {
                NextBillWidgetView(entry: entry)
                    .containerBackground(for: .widget) {
                        WidgetPalette.billCardBackground
                    }
            } else {
                NextBillWidgetView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Next Bill Due")
        .description("Shows the next unpaid bill due today or later.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct UpcomingBillsListEntry: TimelineEntry {
    let date: Date
    let bills: [WidgetBillSummary]
}

struct UpcomingBillsListProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpcomingBillsListEntry {
        UpcomingBillsListEntry(
            date: .now,
            bills: [
                WidgetBillSummary(
                    id: UUID(),
                    name: "Rent",
                    dueDate: .now,
                    amount: 1450,
                    category: .rent,
                    autopayEnabled: true,
                    gracePeriodDays: 3
                ),
                WidgetBillSummary(
                    id: UUID(),
                    name: "Electric",
                    dueDate: Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now,
                    amount: 105,
                    category: .utilities
                )
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingBillsListEntry) -> Void) {
        completion(UpcomingBillsListEntry(date: .now, bills: WidgetStore.fetchUpcomingBills()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingBillsListEntry>) -> Void) {
        let now = Date()
        let entry = UpcomingBillsListEntry(date: now, bills: WidgetStore.fetchUpcomingBills())
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 3, to: now) ?? now.addingTimeInterval(10800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct UpcomingBillsListWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: UpcomingBillsListEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Upcoming Bills")
                        .font(.headline.weight(.bold))
                    Text(summaryText)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.78))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(WidgetFormatters.compactCurrency(WidgetStore.totalDue(entry.bills)))
                        .font(.caption.weight(.black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(countLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }

            if entry.bills.isEmpty {
                Text("No upcoming bills")
                    .font(.title3.weight(.semibold))
                Text("You're all caught up.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                ForEach(displayBills, id: \.id) { bill in
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(WidgetPalette.accent(for: bill.category).opacity(0.22))
                            Image(systemName: WidgetPalette.icon(for: bill.category))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 30, height: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(bill.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(relativeBillText(for: bill.dueDate))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.75))
                        }

                        Spacer(minLength: 8)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(WidgetFormatters.compactCurrency(bill.amount))
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text(WidgetFormatters.shortDate(bill.dueDate))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 16)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .foregroundStyle(.white)
        .widgetURL(WidgetDeepLink.upcomingBillsURL())
    }

    private var displayBills: [WidgetBillSummary] {
        let limit = family == .systemMedium ? 3 : 3
        return Array(entry.bills.prefix(limit))
    }

    private var summaryText: String {
        let overdueCount = WidgetStore.overdueCount(entry.bills)
        if overdueCount > 0 {
            return "\(overdueCount) overdue"
        }
        if let next = entry.bills.first {
            return "Next up: \(WidgetFormatters.shortDate(next.dueDate))"
        }
        return "Nothing due soon"
    }

    private var countLabel: String {
        let hiddenCount = max(entry.bills.count - displayBills.count, 0)
        if hiddenCount > 0 {
            return "\(entry.bills.count) bills, +\(hiddenCount)"
        }
        return entry.bills.count == 1 ? "1 bill" : "\(entry.bills.count) bills"
    }

    private func relativeBillText(for date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<0:
            return "\(abs(days))d overdue"
        case 0:
            return "Due today"
        case 1:
            return "Due tomorrow"
        default:
            return "Due in \(days) days"
        }
    }
}

struct UpcomingBillsListWidget: Widget {
    let kind: String = "UpcomingBillsListWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UpcomingBillsListProvider()) { entry in
            if #available(iOS 17.0, macOS 14.0, *) {
                UpcomingBillsListWidgetView(entry: entry)
                    .containerBackground(for: .widget) {
                        WidgetPalette.billCardBackground
                    }
            } else {
                UpcomingBillsListWidgetView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Upcoming Bills")
        .description("Shows a short list of bills due next.")
        .supportedFamilies([.systemMedium])
    }
}
