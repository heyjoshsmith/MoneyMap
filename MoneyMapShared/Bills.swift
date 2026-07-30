//
//  Bills.swift
//  MoneyMap
//
//  Created by Josh Smith on 3/26/25.
//

import SwiftUI
import SwiftData
import AppIntents

// MARK: - Bill Category

public enum BillCategory: String, CaseIterable, Codable {
    case utilities
    case creditCard
    case rent
    case mortgage
    case insurance
    case subscription
    case streaming
    case software
    case membership
    case groceries
    case transportation
    case phone
    case internet
    case entertainment
    case healthcare
    case personalCare
    case childcare
    case education
    case loans
    case taxes
    case banking
    case homeServices
    case security
    case other

    public var name: String {
        switch self {
        case .utilities:     return "Utilities"
        case .creditCard:    return "Credit Card"
        case .rent:          return "Rent"
        case .mortgage:      return "Mortgage"
        case .insurance:     return "Insurance"
        case .subscription:  return "Subscription"
        case .streaming:     return "Streaming"
        case .software:      return "Software"
        case .membership:    return "Membership"
        case .groceries:     return "Groceries"
        case .transportation: return "Transportation"
        case .phone:         return "Phone"
        case .internet:      return "Internet"
        case .entertainment: return "Entertainment"
        case .healthcare:    return "Healthcare"
        case .personalCare:  return "Personal Care"
        case .childcare:     return "Childcare"
        case .education:     return "Education"
        case .loans:         return "Loans"
        case .taxes:         return "Taxes"
        case .banking:       return "Banking"
        case .homeServices:  return "Home Services"
        case .security:      return "Security"
        case .other:         return "Other"
        }
    }

    public var icon: String {
        switch self {
        case .utilities:     return "bolt"
        case .creditCard:    return "creditcard"
        case .rent:          return "house"
        case .mortgage:      return "house.and.flag"
        case .insurance:     return "shield.lefthalf.filled"
        case .subscription:  return "repeat"
        case .streaming:     return "play.rectangle"
        case .software:      return "laptopcomputer"
        case .membership:    return "person.crop.circle.badge.checkmark"
        case .groceries:     return "cart"
        case .transportation: return "car"
        case .phone:         return "phone"
        case .internet:      return "wifi"
        case .entertainment: return "gamecontroller"
        case .healthcare:    return "cross.case"
        case .personalCare:  return "scissors"
        case .childcare:     return "figure.2"
        case .education:     return "graduationcap"
        case .loans:         return "banknote"
        case .taxes:         return "doc.text.magnifyingglass"
        case .banking:       return "building.columns"
        case .homeServices:  return "wrench.and.screwdriver"
        case .security:      return "lock.shield"
        case .other:         return "ellipsis"
        }
    }

    public var color: Color {
        switch self {
        case .utilities:     return Color(red: 0.70, green: 0.50, blue: 0.20)
        case .creditCard:    return Color(red: 0.22, green: 0.44, blue: 0.56)
        case .rent:          return Color(red: 0.26, green: 0.48, blue: 0.32)
        case .mortgage:      return Color(red: 0.18, green: 0.40, blue: 0.35)
        case .insurance:     return Color(red: 0.24, green: 0.46, blue: 0.52)
        case .subscription:  return Color(red: 0.46, green: 0.38, blue: 0.58)
        case .streaming:     return Color(red: 0.58, green: 0.31, blue: 0.34)
        case .software:      return Color(red: 0.36, green: 0.42, blue: 0.58)
        case .membership:    return Color(red: 0.50, green: 0.37, blue: 0.51)
        case .groceries:     return Color(red: 0.32, green: 0.54, blue: 0.30)
        case .transportation: return Color(red: 0.65, green: 0.38, blue: 0.24)
        case .phone:         return Color(red: 0.24, green: 0.52, blue: 0.55)
        case .internet:      return Color(red: 0.28, green: 0.48, blue: 0.62)
        case .entertainment: return Color(red: 0.54, green: 0.36, blue: 0.56)
        case .healthcare:    return Color(red: 0.62, green: 0.30, blue: 0.29)
        case .personalCare:  return Color(red: 0.58, green: 0.34, blue: 0.40)
        case .childcare:     return Color(red: 0.66, green: 0.43, blue: 0.43)
        case .education:     return Color(red: 0.42, green: 0.40, blue: 0.58)
        case .loans:         return Color(red: 0.55, green: 0.42, blue: 0.27)
        case .taxes:         return Color(red: 0.45, green: 0.45, blue: 0.42)
        case .banking:       return Color(red: 0.20, green: 0.45, blue: 0.38)
        case .homeServices:  return Color(red: 0.50, green: 0.43, blue: 0.34)
        case .security:      return Color(red: 0.24, green: 0.32, blue: 0.34)
        case .other:         return Color(red: 0.48, green: 0.50, blue: 0.47)
        }
    }

    public var isSubscriptionCategory: Bool {
        switch self {
        case .subscription, .streaming, .software, .membership:
            return true
        default:
            return false
        }
    }

    static func < (lhs: BillCategory, rhs: BillCategory) -> Bool {
        return lhs.name < rhs.name
    }
}

// MARK: - Recurrence Unit

public enum RecurrenceUnit: String, CaseIterable, Codable {
    case day
    case week
    case month
    case year
}

// MARK: - Bill Lifecycle

public enum BillLifecycleState: String, CaseIterable, Codable {
    case active
    case paused
    case canceled

    public var title: String {
        switch self {
        case .active:
            return "Active"
        case .paused:
            return "Paused"
        case .canceled:
            return "Canceled"
        }
    }

    public var icon: String {
        switch self {
        case .active:
            return "play.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .canceled:
            return "xmark.circle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .active:
            return .green
        case .paused:
            return .orange
        case .canceled:
            return .red
        }
    }
}

public enum BillPaymentMode: String, CaseIterable, Codable, Identifiable {
    case manual
    case payLink
    case inPerson
    case autopay

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .manual:
            return "Manual"
        case .payLink:
            return "Pay Link"
        case .inPerson:
            return "In Person"
        case .autopay:
            return "Autopay"
        }
    }

    public var icon: String {
        switch self {
        case .manual:
            return "hand.tap"
        case .payLink:
            return "link"
        case .inPerson:
            return "person.crop.circle.badge.checkmark"
        case .autopay:
            return "arrow.triangle.2.circlepath"
        }
    }

    public var detail: String {
        switch self {
        case .manual:
            return "Mark paid yourself when needed."
        case .payLink:
            return "Open a saved website or app link."
        case .inPerson:
            return "Watch synced transactions after you pay in person."
        case .autopay:
            return "Expect the payment to happen automatically."
        }
    }
}

// MARK: - Payment Methods

public enum PaymentMethodType: String, CaseIterable, Codable, Identifiable {
    case creditCard
    case debitCard
    case checking
    case savings
    case cash
    case other

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .creditCard: return "Credit Card"
        case .debitCard:  return "Debit Card"
        case .checking:   return "Checking"
        case .savings:    return "Savings"
        case .cash:       return "Cash"
        case .other:      return "Other"
        }
    }

    public var icon: String {
        switch self {
        case .creditCard: return "creditcard"
        case .debitCard:  return "rectangle.connected.to.line.below"
        case .checking:   return "building.columns"
        case .savings:    return "banknote"
        case .cash:       return "dollarsign.circle"
        case .other:      return "ellipsis.circle"
        }
    }

    public var color: Color {
        switch self {
        case .creditCard: return Color(red: 0.22, green: 0.44, blue: 0.56)
        case .debitCard:  return Color(red: 0.22, green: 0.49, blue: 0.42)
        case .checking:   return Color(red: 0.20, green: 0.45, blue: 0.38)
        case .savings:    return Color(red: 0.32, green: 0.54, blue: 0.30)
        case .cash:       return Color(red: 0.55, green: 0.42, blue: 0.27)
        case .other:      return Color(red: 0.48, green: 0.50, blue: 0.47)
        }
    }

    public var usesRoutingNumber: Bool {
        self == .checking || self == .savings
    }
}

@Model
public class PaymentMethod: Identifiable {
    public var id: UUID = UUID()
    public var name: String = ""
    public var typeRawValue: String = PaymentMethodType.checking.rawValue
    public var institutionName: String?
    public var lastFourDigits: String?
    public var routingNumber: String?
    public var linkedBillID: UUID?
    public var notes: String?
    public var plaidAccountID: String?
    public var plaidItemID: String?
    public var plaidInstitutionID: String?
    public var plaidUpdatedAt: Date?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        name: String,
        type: PaymentMethodType,
        institutionName: String? = nil,
        lastFourDigits: String? = nil,
        routingNumber: String? = nil,
        linkedBillID: UUID? = nil,
        notes: String? = nil,
        plaidAccountID: String? = nil,
        plaidItemID: String? = nil,
        plaidInstitutionID: String? = nil,
        plaidUpdatedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = UUID()
        self.name = name
        self.typeRawValue = type.rawValue
        self.institutionName = institutionName
        self.lastFourDigits = Self.normalizedLastFourDigits(lastFourDigits)
        self.routingNumber = Self.normalizedRoutingNumber(routingNumber)
        self.linkedBillID = linkedBillID
        self.notes = notes
        self.plaidAccountID = plaidAccountID
        self.plaidItemID = plaidItemID
        self.plaidInstitutionID = plaidInstitutionID
        self.plaidUpdatedAt = plaidUpdatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var type: PaymentMethodType {
        get { PaymentMethodType(rawValue: typeRawValue) ?? .other }
        set { typeRawValue = newValue.rawValue }
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? type.name : trimmed
    }

    public var numberLabel: String? {
        guard let lastFourDigits, !lastFourDigits.isEmpty else { return nil }
        return "Ending \(lastFourDigits)"
    }

    public var detailText: String {
        let rawParts: [String?] = [
            institutionName?.trimmingCharacters(in: .whitespacesAndNewlines),
            numberLabel
        ]

        let parts = rawParts.compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }

        return parts.isEmpty ? type.name : parts.joined(separator: " - ")
    }

    public var isCreditCardMirror: Bool {
        type == .creditCard && linkedBillID != nil
    }

    public func updateCreditCardMirror(from bill: Bill) {
        type = .creditCard
        name = bill.name ?? "Credit Card"
        institutionName = bill.creditCardDetails?.issuerName
        lastFourDigits = Self.normalizedLastFourDigits(bill.creditCardDetails?.lastFourDigits)
        linkedBillID = bill.id
        plaidAccountID = bill.plaidAccountID
        plaidItemID = bill.plaidItemID
        plaidInstitutionID = bill.plaidInstitutionID
        plaidUpdatedAt = bill.plaidUpdatedAt
        updatedAt = .now
    }

    public static func normalizedLastFourDigits(_ value: String?) -> String? {
        guard let value else { return nil }
        let digits = value.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return String(digits.suffix(4))
    }

    public static func normalizedRoutingNumber(_ value: String?) -> String? {
        guard let value else { return nil }
        let digits = value.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return digits
    }
}

// MARK: - Credit Card Details

public struct CreditCardDetails: Codable {
    public var creditLimit: Double
    public var cardBalance: Double
    public var annualPercentageRate: Double?
    public var minimumPayment: Double?
    public var statementBalance: Double?
    public var issuerName: String?
    public var lastFourDigits: String?
    public var statementClosingDate: Date?
    public var promoAPRExpiration: Date?

    public var utilization: Double {
        guard creditLimit > 0 else { return 0 }
        return cardBalance / creditLimit
    }

    public var overExcellentThreshold: Bool {
        utilization > 0.1
    }

    public var overUtilized: Bool {
        utilization > 0.3
    }
    
    public var recommendedPayment: Double {
        if overUtilized {
            return roundedToCents(cardBalance - (creditLimit * 0.3))
        } else if overExcellentThreshold {
            return roundedToCents(cardBalance - (creditLimit * 0.1))
        } else {
            return 0
        }
    }

    public var effectiveMinimumPayment: Double {
        max(minimumPayment ?? 0, 0)
    }

    public init(
        creditLimit: Double,
        cardBalance: Double,
        annualPercentageRate: Double? = nil,
        minimumPayment: Double? = nil,
        statementBalance: Double? = nil,
        issuerName: String? = nil,
        lastFourDigits: String? = nil,
        statementClosingDate: Date? = nil,
        promoAPRExpiration: Date? = nil
    ) {
        self.creditLimit = creditLimit
        self.cardBalance = cardBalance
        self.annualPercentageRate = annualPercentageRate
        self.minimumPayment = minimumPayment
        self.statementBalance = statementBalance
        self.issuerName = issuerName
        self.lastFourDigits = lastFourDigits
        self.statementClosingDate = statementClosingDate
        self.promoAPRExpiration = promoAPRExpiration
    }
    
    private func roundedToCents(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

// MARK: - Bill Model

/// Represents a bill, which can also represent a credit card with related transactions.
@Model
public class Bill {

    public var id: UUID = UUID()
    public var name: String?
    public var amount: Double?
    public var dueDate: Date?
    public var datePaid: Date?
    public var category: BillCategory?
    public var recurrenceInterval: Int?
    public var recurrenceUnit: RecurrenceUnit?
    public var creditCardDetails: CreditCardDetails?
    public var notes: String?
    public var autopaySource: String?
    public var gracePeriodDays: Int?
    public var paymentURLString: String?
    public var paymentMethodID: UUID?
    public var paymentModeRawValue: String?
    public var lifecycleStateRaw: String?
    public var lifecycleUpdatedAt: Date?
    public var plaidAccountID: String?
    public var plaidItemID: String?
    public var plaidInstitutionID: String?
    public var plaidUpdatedAt: Date?
    public var plaidUnavailable: Bool = false
    public var status: Status?
    public var imageData: Data?
    private var storedAutopayEnabled: Bool?

    @Relationship(inverse: \Transaction.creditCard) public var transactions: [Transaction]?

    public var autopayEnabled: Bool {
        get { storedAutopayEnabled ?? false }
        set { storedAutopayEnabled = newValue }
    }

    public var image: Image? {
        #if os(iOS) || os(tvOS) || os(visionOS)
        guard let data = imageData, let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #elseif os(macOS)
        guard let data = imageData, let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #else
        return nil
        #endif
    }
    
    #if os(iOS) || os(tvOS) || os(visionOS)
    func setImage(_ image: UIImage, compressionQuality: CGFloat = 0.9) {
        self.imageData = image.jpegData(compressionQuality: compressionQuality)
    }
    #elseif os(macOS)
    func setImage(_ image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            self.imageData = nil
            return
        }
        self.imageData = pngData
    }
    #endif

    public init(name: String?, amount: Double?, dueDate: Date?, category: BillCategory?, recurrenceInterval: Int?, recurrenceUnit: RecurrenceUnit?, creditCardDetails: CreditCardDetails? = nil, imageData: Data? = nil, autopayEnabled: Bool = false, notes: String? = nil, autopaySource: String? = nil, gracePeriodDays: Int? = nil, paymentURLString: String? = nil, paymentMethodID: UUID? = nil, paymentMode: BillPaymentMode? = nil, lifecycleState: BillLifecycleState = .active, lifecycleUpdatedAt: Date? = nil, plaidAccountID: String? = nil, plaidItemID: String? = nil, plaidInstitutionID: String? = nil, plaidUpdatedAt: Date? = nil, plaidUnavailable: Bool = false) {
        self.name = name
        self.amount = amount
        self.dueDate = dueDate
        self.category = category
        self.recurrenceInterval = recurrenceInterval
        self.recurrenceUnit = recurrenceUnit
        self.creditCardDetails = creditCardDetails
        self.imageData = imageData
        self.storedAutopayEnabled = autopayEnabled
        self.notes = notes
        self.autopaySource = autopaySource
        self.gracePeriodDays = gracePeriodDays
        self.paymentURLString = paymentURLString
        self.paymentMethodID = paymentMethodID
        self.paymentModeRawValue = paymentMode?.rawValue
        self.lifecycleStateRaw = lifecycleState == .active ? nil : lifecycleState.rawValue
        self.lifecycleUpdatedAt = lifecycleUpdatedAt
        self.plaidAccountID = plaidAccountID
        self.plaidItemID = plaidItemID
        self.plaidInstitutionID = plaidInstitutionID
        self.plaidUpdatedAt = plaidUpdatedAt
        self.plaidUnavailable = plaidUnavailable
    }
    
    public func makePayment(of amount: Double) {
        if let currentBalance = self.creditCardDetails?.cardBalance {
            if currentBalance < 0 {
                self.creditCardDetails?.cardBalance = min(currentBalance + amount, 0)
            } else {
                self.creditCardDetails?.cardBalance = max(currentBalance - amount, 0)
            }
        }
        datePaid = .now
        status = .paid
        checkStatus()
    }

}

public enum Status: Codable, Equatable {
    
    case paid
    case overdue
    case upcoming(date: Date)
    
    public static func == (lhs: Status, rhs: Status) -> Bool {
        switch (lhs, rhs) {
        case (.paid, .paid):
            return true
        case (.overdue, .overdue):
            return true
        case let (.upcoming(date1), .upcoming(date2)):
            return Calendar.current.isDate(date1, inSameDayAs: date2)
        default:
            return false
        }
    }
    
    public var name: String {
        switch self {
        case .paid:
            return "Paid"
        case .overdue:
            return "Overdue"
        case .upcoming(let date):
            return date.daysUntil
        }
    }
    
    public var color: Color {
        switch self {
        case .paid:
            return Color(red: 0.32, green: 0.54, blue: 0.30)
        case .overdue:
            return Color(red: 0.62, green: 0.30, blue: 0.29)
        case .upcoming(let date):
            
            let daysDifference = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
            
            switch daysDifference {
            case 0...7:
                return Color(red: 0.70, green: 0.50, blue: 0.20)
            case 8...14:
                return Color(red: 0.55, green: 0.42, blue: 0.27)
            default:
                return Color(red: 0.28, green: 0.48, blue: 0.62)
            }
        }
    }
    
}

extension Bill {
    public var paymentURL: URL? {
        Self.paymentURL(from: paymentURLString)
    }

    public static func normalizedPaymentURLString(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty {
            let lowercasedScheme = scheme.lowercased()
            if lowercasedScheme == "http" || lowercasedScheme == "https" {
                return url.host == nil ? nil : trimmed
            }
            return trimmed
        }

        guard trimmed.contains(".") else { return nil }
        return "https://\(trimmed)"
    }

    public static func paymentURL(from rawValue: String?) -> URL? {
        guard let normalized = normalizedPaymentURLString(from: rawValue) else { return nil }
        return URL(string: normalized)
    }

    public static func paymentHost(from rawValue: String?) -> String? {
        paymentURL(from: rawValue)?.host?.replacingOccurrences(of: "www.", with: "")
    }

    public var paymentHost: String? {
        Self.paymentHost(from: paymentURLString)
    }

    public func normalizePaymentURLString() {
        paymentURLString = Self.normalizedPaymentURLString(from: paymentURLString)
    }

    public var hasValidPaymentURL: Bool {
        paymentURL != nil
    }

    public var paymentMode: BillPaymentMode {
        get {
            if let paymentModeRawValue,
               let mode = BillPaymentMode(rawValue: paymentModeRawValue) {
                return mode
            }
            if autopayEnabled {
                return .autopay
            }
            if paymentURL != nil {
                return .payLink
            }
            return .manual
        }
        set {
            paymentModeRawValue = newValue.rawValue
            autopayEnabled = newValue == .autopay
        }
    }

    public var paymentModeTitle: String {
        paymentMode.title
    }

    public var paymentModeIcon: String {
        paymentMode.icon
    }

    public func paymentMethod(in paymentMethods: [PaymentMethod]) -> PaymentMethod? {
        guard let paymentMethodID else { return nil }
        return paymentMethods.first { $0.id == paymentMethodID }
    }

    public func paymentMethodName(in paymentMethods: [PaymentMethod]) -> String? {
        paymentMethod(in: paymentMethods)?.displayName ?? autopaySource
    }

    public func updatePaymentSettings(
        autopayEnabled: Bool,
        paymentMethodID: UUID?,
        autopaySource: String?,
        gracePeriodDays: Int,
        paymentMode: BillPaymentMode? = nil
    ) {
        let resolvedMode = paymentMode ?? (autopayEnabled ? .autopay : self.paymentMode)
        self.paymentModeRawValue = resolvedMode.rawValue
        self.autopayEnabled = resolvedMode == .autopay
        self.paymentMethodID = paymentMethodID

        let normalizedSource = autopaySource?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.autopaySource = resolvedMode == .autopay && normalizedSource?.isEmpty == false ? normalizedSource : nil
        self.gracePeriodDays = gracePeriodDays > 0 ? gracePeriodDays : nil
    }

    public var lifecycleState: BillLifecycleState {
        get {
            guard let lifecycleStateRaw else { return .active }
            return BillLifecycleState(rawValue: lifecycleStateRaw) ?? .active
        }
        set {
            lifecycleStateRaw = newValue == .active ? nil : newValue.rawValue
            lifecycleUpdatedAt = .now
        }
    }

    public var isActive: Bool {
        lifecycleState == .active
    }

    public var isPaused: Bool {
        lifecycleState == .paused
    }

    public var isCanceled: Bool {
        lifecycleState == .canceled
    }

    public var isSubscriptionLike: Bool {
        category?.isSubscriptionCategory == true || recurrenceInterval != nil
    }

    public var displayStatusName: String {
        lifecycleState == .active ? (status?.name ?? "Unknown") : lifecycleState.title
    }

    public var displayStatusColor: Color {
        lifecycleState == .active ? (status?.color ?? .secondary) : lifecycleState.color
    }

    public func delay(to newDueDate: Date) {
        lifecycleState = .active
        dueDate = newDueDate
        datePaid = nil
        checkStatus()
    }

    public func skipNextOccurrence(calendar: Calendar = .current) {
        let nextDate = nextOccurrenceDate(calendar: calendar) ??
            calendar.date(byAdding: .month, value: 1, to: dueDate ?? .now) ??
            .now
        delay(to: nextDate)
    }

    public func pause(on date: Date = .now) {
        lifecycleState = .paused
        lifecycleUpdatedAt = date
        datePaid = nil
        status = .paid
    }

    public func cancel(on date: Date = .now) {
        lifecycleState = .canceled
        lifecycleUpdatedAt = date
        datePaid = nil
        status = .paid
    }

    public func resume(nextDueDate: Date) {
        lifecycleState = .active
        dueDate = nextDueDate
        datePaid = nil
        checkStatus()
    }

    public func nextOccurrenceDate(calendar: Calendar = .current) -> Date? {
        guard
            let dueDate,
            let recurrenceUnit,
            let recurrenceInterval
        else {
            return calendar.date(byAdding: .month, value: 1, to: self.dueDate ?? .now)
        }

        return advance(date: dueDate, unit: recurrenceUnit, interval: recurrenceInterval, calendar: calendar)
    }

    
    // MARK: - Sorting
    
    public static func byDate(lhs: Bill, rhs: Bill) -> Bool {
        let lhsDate = Calendar.current.startOfDay(for: lhs.dueDate ?? .distantPast)
        let rhsDate = Calendar.current.startOfDay(for: rhs.dueDate ?? .distantPast)
        if lhsDate == rhsDate {
            return (lhs.amount ?? 0) > (rhs.amount ?? 0)
        }
        return lhsDate < rhsDate
    }
    
    public static func byName(lhs: Bill, rhs: Bill) -> Bool {
        if lhs.name == rhs.name {
            return (lhs.amount ?? 0) > (rhs.amount ?? 0)
        }
        return (lhs.name ?? "") < (rhs.name ?? "")
    }
    
    public static func byBalance(lhs: Bill, rhs: Bill) -> Bool {
        let lhsBalance = lhs.creditCardDetails?.cardBalance ?? 0
        let rhsBalance = rhs.creditCardDetails?.cardBalance ?? 0
        if lhsBalance == rhsBalance {
            return (lhs.amount ?? 0) > (rhs.amount ?? 0)
        }
        return lhsBalance < rhsBalance
    }
    
    public static func byLimit(lhs: Bill, rhs: Bill) -> Bool {
        let lhsLimit = lhs.creditCardDetails?.creditLimit ?? 0
        let rhsLimit = rhs.creditCardDetails?.creditLimit ?? 0
        if lhsLimit == rhsLimit {
            return (lhs.amount ?? 0) > (rhs.amount ?? 0)
        }
        return lhsLimit < rhsLimit
    }
    
    public static func byStatusDateUtilization(lhs: Bill, rhs: Bill) -> Bool {
        let lhsIsPaid = lhs.status == .paid
        let rhsIsPaid = rhs.status == .paid
        if lhsIsPaid != rhsIsPaid {
            // Unpaid first
            return !lhsIsPaid
        }

        let lhsDate = lhs.dueDate ?? .distantFuture
        let rhsDate = rhs.dueDate ?? .distantFuture
        let lhsUtilization = lhs.creditCardDetails?.utilization ?? 0
        let rhsUtilization = rhs.creditCardDetails?.utilization ?? 0

        if lhsIsPaid && rhsIsPaid {
            // Both are paid: utilization, then date
            if lhsUtilization != rhsUtilization {
                return lhsUtilization > rhsUtilization
            }
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
        } else {
            // Both are unpaid: date, then utilization
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            if lhsUtilization != rhsUtilization {
                return lhsUtilization < rhsUtilization
            }
        }
        // Fallback: by name
        return (lhs.name ?? "") < (rhs.name ?? "")
    }
    
    
    // MARK: - Functions
    
    public func checkStatus() {
        guard lifecycleState == .active else {
            status = .paid
            return
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let dueDate = self.dueDate else {
            status = .overdue
            return
        }
        var dueDay = calendar.startOfDay(for: dueDate)

        if autopayEnabled {
            if dueDay < today {
                if let advancedDueDate = advancedDueDateIfNeeded(from: dueDate, untilAtLeast: today, calendar: calendar) {
                    self.dueDate = advancedDueDate
                    dueDay = calendar.startOfDay(for: advancedDueDate)
                    datePaid = nil
                    status = .upcoming(date: dueDay)
                    return
                }

                datePaid = dueDate
                status = .paid
                return
            }

            datePaid = nil
            status = .upcoming(date: dueDay)
            return
        }

        if let _ = datePaid {
            // If the bill is paid, check if the current billing period has ended
            if today > dueDay {
                guard
                    let recurrenceUnit = recurrenceUnit,
                    let recurrenceInterval = recurrenceInterval,
                    let currentDueDate = self.dueDate
                else {
                    status = .paid
                    return
                }
                // Assign to self.dueDate, not local let dueDate
                switch recurrenceUnit {
                case .day:
                    self.dueDate = calendar.date(byAdding: .day, value: recurrenceInterval, to: currentDueDate)
                case .week:
                    self.dueDate = calendar.date(byAdding: .day, value: 7 * recurrenceInterval, to: currentDueDate)
                case .month:
                    self.dueDate = calendar.date(byAdding: .month, value: recurrenceInterval, to: currentDueDate)
                case .year:
                    self.dueDate = calendar.date(byAdding: .year, value: recurrenceInterval, to: currentDueDate)
                }
                // Clear the payment date since we're starting a new billing cycle
                datePaid = nil

                if let newDueDate = self.dueDate {
                    let newDueDay = calendar.startOfDay(for: newDueDate)
                    let daysDifference = calendar.dateComponents([.day], from: today, to: newDueDay).day ?? 0

                    if daysDifference >= 0 {
                        status = .upcoming(date: newDueDay)
                    } else {
                        status = .overdue
                    }
                } else {
                    status = .overdue
                }
            } else {
                // Payment is still valid for the current period
                status = .paid
            }
        } else {
            // Not paid yet; determine status based on dueDate
            let daysDifference = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0

            if daysDifference >= 0 {
                status = .upcoming(date: dueDay)
            } else {
                status = .overdue
            }
        }
    }

    private func advancedDueDateIfNeeded(from currentDueDate: Date, untilAtLeast targetDay: Date, calendar: Calendar) -> Date? {
        guard let recurrenceUnit, let recurrenceInterval else { return nil }

        var nextDueDate = currentDueDate
        var nextDueDay = calendar.startOfDay(for: currentDueDate)

        while nextDueDay < targetDay {
            guard let advanced = advance(date: nextDueDate, unit: recurrenceUnit, interval: recurrenceInterval, calendar: calendar) else {
                return nil
            }
            nextDueDate = advanced
            nextDueDay = calendar.startOfDay(for: advanced)
        }

        return nextDueDate
    }

    private func advance(date: Date, unit: RecurrenceUnit, interval: Int, calendar: Calendar) -> Date? {
        switch unit {
        case .day:
            return calendar.date(byAdding: .day, value: interval, to: date)
        case .week:
            return calendar.date(byAdding: .day, value: 7 * interval, to: date)
        case .month:
            return calendar.date(byAdding: .month, value: interval, to: date)
        case .year:
            return calendar.date(byAdding: .year, value: interval, to: date)
        }
    }
    
    public static func calculateTotal(for category: BillCategory?) async throws -> Double {
        let bills = sampleBills()
        if let billCategory = category {
            let filteredBills = bills.filter { $0.category == billCategory }
            return filteredBills.totalAmount
        }
        return bills.totalAmount
    }
    
    
    // MARK: - Sample Data
    
    public static func sampleBills(type: BillCategory? = nil) -> Bills {
        let bills = [
            Bill(name: "Electricity", amount: 100.0, dueDate: Date(), category: .utilities, recurrenceInterval: 1, recurrenceUnit: .month),
            Bill(name: "Water", amount: 50.0, dueDate: Date(), category: .utilities, recurrenceInterval: 1, recurrenceUnit: .month),
            Bill(name: "Rent", amount: 1200.0, dueDate: Date(), category: .rent, recurrenceInterval: 1, recurrenceUnit: .month),
            getSampleCreditCard(name: "American Express"),
            getSampleCreditCard(name: "Apple Card"),
            getSampleCreditCard(name: "Capital One"),
            getSampleCreditCard(name: "Chase")
        ]
        
        if let type {
            return bills.filter { bill in
                bill.category == type
            }
        }
        
        return bills
    }
    
    public static func getSampleCreditCard(name: String) -> Bill {
        
        let limit = Double.random(in: 1_000...50_000)
        let balance = Double.random(in: 0...limit)
        let details = CreditCardDetails(creditLimit: limit, cardBalance: balance)
        
        return Bill(
            name: name,
            amount: 200,
            dueDate: .now,
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: details
        )
    }
}

extension Bill {
    @MainActor static var preview: ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: Bill.self, Transaction.self, AuditEvent.self, PaymentMethod.self, configurations: config) else {
            preconditionFailure("Failed to create in-memory preview container for Bill.")
        }
        let context = container.mainContext
        // Insert sample bills into the context
        for bill in Bill.sampleBills() {
            context.insert(bill)
        }
        return container
    }
}

public enum PaymentMethodSyncService {
    @discardableResult
    public static func syncCreditCardPaymentMethods(
        bills: [Bill],
        paymentMethods: [PaymentMethod],
        context: ModelContext
    ) -> Bool {
        var didChange = false
        let creditCardBills = bills.filter { $0.category == .creditCard }
        let methodsByBillID = Dictionary(
            paymentMethods
                .filter { $0.type == .creditCard }
                .compactMap { method -> (UUID, PaymentMethod)? in
                    guard let billID = method.linkedBillID else { return nil }
                    return (billID, method)
                },
            uniquingKeysWith: { first, _ in first }
        )

        for bill in creditCardBills {
            if let method = methodsByBillID[bill.id] {
                let oldName = method.name
                let oldInstitution = method.institutionName
                let oldLastFour = method.lastFourDigits
                method.updateCreditCardMirror(from: bill)
                didChange = didChange ||
                    oldName != method.name ||
                    oldInstitution != method.institutionName ||
                    oldLastFour != method.lastFourDigits
            } else {
                let method = PaymentMethod(
                    name: bill.name ?? "Credit Card",
                    type: .creditCard,
                    institutionName: bill.creditCardDetails?.issuerName,
                    lastFourDigits: bill.creditCardDetails?.lastFourDigits,
                    linkedBillID: bill.id,
                    plaidAccountID: bill.plaidAccountID,
                    plaidItemID: bill.plaidItemID,
                    plaidInstitutionID: bill.plaidInstitutionID,
                    plaidUpdatedAt: bill.plaidUpdatedAt
                )
                context.insert(method)
                didChange = true
            }
        }

        let activeCreditCardIDs = Set(creditCardBills.map(\.id))
        for method in paymentMethods where method.isCreditCardMirror {
            guard let linkedBillID = method.linkedBillID, !activeCreditCardIDs.contains(linkedBillID) else {
                continue
            }
            context.delete(method)
            didChange = true
        }

        return didChange
    }
}

extension Double {
    var abbreviatedCurrency: String {
        let absValue = abs(self)
        let sign = self < 0 ? "-" : ""
        switch absValue {
        case 1_000_000_000...:
            return "\(sign)$\(String(format: "%.1f", absValue / 1_000_000_000))B"
        case 1_000_000...:
            return "\(sign)$\(String(format: "%.1f", absValue / 1_000_000))M"
        case 1_000...:
            return "\(sign)$\(String(format: "%.1f", absValue / 1_000))K"
        default:
            return "\(sign)$\(absValue)"
        }
    }
}

public typealias Bills = [Bill]
extension Bills {
    
    var totalAmount: Double {
        reduce(0) { $0 + ($1.amount ?? 0) }
    }
    
    var withoutCreditCards: Bills {
        return self.filter { bill in
            bill.category != .creditCard
        }
    }
    
    var creditCards: Bills {
        return self.filter { bill in
            bill.category == .creditCard
        }
    }
    
    var totalBalance: Double {
        return creditCards.reduce(0) { $0 + ($1.creditCardDetails?.cardBalance ?? 0) }
    }
    
    var totalCreditLimit: Double {
        return creditCards.reduce(0) { $0 + ($1.creditCardDetails?.creditLimit ?? 0) }
    }
    
    var creditCardUtilization: Double {
        return totalCreditLimit == 0 ? 0 : totalBalance / totalCreditLimit
    }
    
    var recommendedPayment: Double? {
        let value = totalBalance - (totalCreditLimit * 0.1)
        if value > 0 {
            return value
        }
        
        return nil
    }
    
    func due(_ timeframe: Timeframe) -> Bills {
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let dueCandidates = self.withoutCreditCards.filter { bill in
            bill.lifecycleState == .active
        }
        
        var bills = Bills()
        
        switch timeframe {
        case .overdue:
            bills = dueCandidates.filter {
                guard let dueDate = $0.dueDate else { return false }
                let dueDay = calendar.startOfDay(for: dueDate)
                let diff = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
                return diff < 0
            }
        case .today:
            bills = dueCandidates.filter {
                guard let dueDate = $0.dueDate else { return false }
                let dueDay = calendar.startOfDay(for: dueDate)
                let diff = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
                return diff == 0
            }
        case .tomorrow:
            bills = dueCandidates.filter {
                guard let dueDate = $0.dueDate else { return false }
                let dueDay = calendar.startOfDay(for: dueDate)
                let diff = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
                return diff == 1
            }
        case .thisWeek:
            bills = dueCandidates.filter {
                guard let dueDate = $0.dueDate else { return false }
                let dueDay = calendar.startOfDay(for: dueDate)
                let diff = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
                return diff >= 2 && diff <= 7
            }
        case .thisMonth:
            bills = dueCandidates.filter {
                guard let dueDate = $0.dueDate else { return false }
                
                let dueDay = calendar.startOfDay(for: dueDate)
                let diff = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
                
                let month = calendar.component(.month, from: today)
                var nextMonth = calendar.date(bySetting: .month, value: month + 1, of: today)
                    nextMonth = calendar.date(bySetting: .day, value: 1, of: nextMonth ?? today)
                
                
                return diff >= 8 && dueDate < nextMonth ?? dueDay
                
            }
        case .later:
            bills = dueCandidates.filter {
                guard let dueDate = $0.dueDate else { return false }
                
                let month = calendar.component(.month, from: today)
                var nextMonth = calendar.date(bySetting: .month, value: month + 1, of: today)
                    nextMonth = calendar.date(bySetting: .day, value: 1, of: nextMonth ?? today)
                
                return dueDate >= nextMonth ?? today
            }
        }
        
        return bills.sorted(by: Bill.byDate)
    }
    
}

enum Timeframe: String, Identifiable, CaseIterable {
    
    case overdue
    case today
    case tomorrow
    case thisWeek
    case thisMonth
    case later
    
    var id: Self { return self }
    
    var name: String {
        switch self {
        case .overdue:
            return "Overdue"
        case .today:
            return "Today"
        case .tomorrow:
            return "Tomorrow"
        case .thisWeek:
            return "This week"
        case .thisMonth:
            return "This month"
        case .later:
            return "Later"
        }
    }
}
