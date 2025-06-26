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

enum BillCategory: String, CaseIterable, Codable {
    case utilities
    case creditCard
    case rent
    case insurance
    case subscription
    case groceries
    case transportation
    case phone
    case internet
    case entertainment
    case other

    var name: String {
        switch self {
        case .utilities:      return "Utilities"
        case .creditCard:     return "Credit Card"
        case .rent:           return "Rent"
        case .insurance:      return "Insurance"
        case .subscription:   return "Subscription"
        case .groceries:      return "Groceries"
        case .transportation: return "Transportation"
        case .phone:          return "Phone"
        case .internet:       return "Internet"
        case .entertainment:  return "Entertainment"
        case .other:          return "Other"
        }
    }

    var icon: String {
        switch self {
        case .utilities:      return "lightbulb"
        case .creditCard:     return "creditcard"
        case .rent:           return "house"
        case .insurance:      return "shield"
        case .subscription:   return "tv"
        case .groceries:      return "cart"
        case .transportation: return "car"
        case .phone:          return "phone"
        case .internet:       return "wifi"
        case .entertainment:  return "gamecontroller"
        case .other:          return "ellipsis"
        }
    }

    var color: Color {
        switch self {
        case .utilities:      return .yellow
        case .creditCard:     return .blue
        case .rent:           return .green
        case .insurance:      return .orange
        case .subscription:   return .purple
        case .groceries:      return .red
        case .transportation: return .pink
        case .phone:          return .mint
        case .internet:       return .indigo
        case .entertainment:  return .teal
        case .other:          return .gray
        }
    }
    
    static func < (lhs: BillCategory, rhs: BillCategory) -> Bool {
        return lhs.name < rhs.name
    }
}

// MARK: - Recurrence Unit

enum RecurrenceUnit: String, CaseIterable, Codable {
    case day
    case week
    case month
    case year
}

// MARK: - Credit Card Details

struct CreditCardDetails: Codable {
    var creditLimit: Double
    var cardBalance: Double
    
    var utilization: Double {
        return cardBalance / creditLimit
    }
    
    var overExcellentThreshold: Bool {
        utilization > 0.1
    }
    
    var overUtilized: Bool {
        utilization > 0.3
    }
    
    var recommendedPayment: Double {
        if overUtilized {
            return roundedToCents(cardBalance - (creditLimit * 0.3))
        } else if overExcellentThreshold {
            return roundedToCents(cardBalance - (creditLimit * 0.1))
        } else {
            return 0
        }
    }
    
    private func roundedToCents(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

// MARK: - Bill Model

@Model
class Bill {
    
    var id: UUID = UUID()
    var name: String?
    var amount: Double?
    var dueDate: Date?
    var datePaid: Date?
    var category: BillCategory?
    var recurrenceInterval: Int?
    var recurrenceUnit: RecurrenceUnit?
    var creditCardDetails: CreditCardDetails?
    var status: Status?
    var imageData: Data?
    
    var image: Image? {
        #if os(iOS) || os(tvOS) || os(watchOS)
        guard let data = imageData, let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #elseif os(macOS)
        guard let data = imageData, let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #else
        return nil
        #endif
    }
    
    #if os(iOS) || os(tvOS) || os(watchOS)
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

    init(name: String?, amount: Double?, dueDate: Date?, category: BillCategory?, recurrenceInterval: Int?, recurrenceUnit: RecurrenceUnit?, creditCardDetails: CreditCardDetails? = nil, imageData: Data? = nil) {
        self.name = name
        self.amount = amount
        self.dueDate = dueDate
        self.category = category
        self.recurrenceInterval = recurrenceInterval
        self.recurrenceUnit = recurrenceUnit
        self.creditCardDetails = creditCardDetails
        self.imageData = imageData
    }
    
    func makePayment(of amount: Double) {
        if let currentBalance = self.creditCardDetails?.cardBalance {
            self.creditCardDetails?.cardBalance = currentBalance - amount
        }
        datePaid = .now
        status = .paid
        checkStatus()
    }

}

enum Status: Codable, Equatable {
    
    case paid
    case overdue
    case upcoming(date: Date)
    
    static func == (lhs: Status, rhs: Status) -> Bool {
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
    
    var name: String {
        switch self {
        case .paid:
            return "Paid"
        case .overdue:
            return "Overdue"
        case .upcoming(let date):
            return date.daysUntil
        }
    }
    
    var color: Color {
        switch self {
        case .paid:
            return .green
        case .overdue:
            return .red
        case .upcoming(let date):
            
            let daysDifference = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
            
            switch daysDifference {
            case 0...7:
                return .orange
            case 8...14:
                return .yellow
            default:
                return .blue
            }
        }
    }
    
}

extension Bill {
    
    // MARK: - Sorting
    
    static func byDate(lhs: Bill, rhs: Bill) -> Bool {
        let lhsDate = Calendar.current.startOfDay(for: lhs.dueDate ?? .distantPast)
        let rhsDate = Calendar.current.startOfDay(for: rhs.dueDate ?? .distantPast)
        if lhsDate == rhsDate {
            return (lhs.amount ?? 0) > (rhs.amount ?? 0)
        }
        return lhsDate < rhsDate
    }
    
    static func byName(lhs: Bill, rhs: Bill) -> Bool {
        if lhs.name == rhs.name {
            return (lhs.amount ?? 0) > (rhs.amount ?? 0)
        }
        return (lhs.name ?? "") < (rhs.name ?? "")
    }
    
    static func byBalance(lhs: Bill, rhs: Bill) -> Bool {
        let lhsBalance = lhs.creditCardDetails?.cardBalance ?? 0
        let rhsBalance = rhs.creditCardDetails?.cardBalance ?? 0
        if lhsBalance == rhsBalance {
            return (lhs.amount ?? 0) > (rhs.amount ?? 0)
        }
        return lhsBalance < rhsBalance
    }
    
    static func byLimit(lhs: Bill, rhs: Bill) -> Bool {
        let lhsLimit = lhs.creditCardDetails?.creditLimit ?? 0
        let rhsLimit = rhs.creditCardDetails?.creditLimit ?? 0
        if lhsLimit == rhsLimit {
            return (lhs.amount ?? 0) > (rhs.amount ?? 0)
        }
        return lhsLimit < rhsLimit
    }
    
    static func byStatusDateUtilization(lhs: Bill, rhs: Bill) -> Bool {
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
    
    func checkStatus() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let dueDate = self.dueDate else {
            status = .overdue
            return
        }
        let dueDay = calendar.startOfDay(for: dueDate)

        // Automatically mark non-credit card bills as paid if due date is today or earlier
        if category != .creditCard && dueDay <= today {
            datePaid = dueDate
        }

        if let _ = datePaid {
            // If the bill is paid, check if the current billing period has ended
            if today > dueDay {
                guard
                    let recurrenceUnit = recurrenceUnit,
                    let recurrenceInterval = recurrenceInterval,
                    let currentDueDate = self.dueDate
                else {
                    status = .overdue
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
    
    static func calculateTotal(for category: BillCategory?) async throws -> Double {
        let bills = sampleBills()
        if let billCategory = category {
            let filteredBills = bills.filter { $0.category == billCategory }
            return filteredBills.totalAmount
        }
        return bills.totalAmount
    }
    
    
    // MARK: - Sample Data
    
    static func sampleBills(type: BillCategory? = nil) -> Bills {
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
    
    static func getSampleCreditCard(name: String) -> Bill {
        
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

#if DEBUG
extension Bill {
    @MainActor static var preview: ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Bill.self, configurations: config)
        let context = container.mainContext
        // Insert sample bills into the context
        for bill in Bill.sampleBills() {
            context.insert(bill)
        }
        return container
    }
}
#endif

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

typealias Bills = [Bill]
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
        
        var bills = Bills()
        
        switch timeframe {
        case .overdue:
            bills = self.withoutCreditCards.filter {
                guard let dueDate = $0.dueDate else { return false }
                let dueDay = calendar.startOfDay(for: dueDate)
                let diff = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
                return diff < 0
            }
        case .today:
            bills = self.withoutCreditCards.filter {
                guard let dueDate = $0.dueDate else { return false }
                let dueDay = calendar.startOfDay(for: dueDate)
                let diff = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
                return diff == 0
            }
        case .tomorrow:
            bills = self.withoutCreditCards.filter {
                guard let dueDate = $0.dueDate else { return false }
                let dueDay = calendar.startOfDay(for: dueDate)
                let diff = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
                return diff == 1
            }
        case .thisWeek:
            bills = self.withoutCreditCards.filter {
                guard let dueDate = $0.dueDate else { return false }
                let dueDay = calendar.startOfDay(for: dueDate)
                let diff = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
                return diff >= 2 && diff <= 7
            }
        case .thisMonth:
            bills = self.withoutCreditCards.filter {
                guard let dueDate = $0.dueDate else { return false }
                
                let dueDay = calendar.startOfDay(for: dueDate)
                let diff = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
                
                let month = calendar.component(.month, from: today)
                var nextMonth = calendar.date(bySetting: .month, value: month + 1, of: today)
                    nextMonth = calendar.date(bySetting: .day, value: 1, of: nextMonth ?? today)
                
                
                return diff >= 8 && dueDate < nextMonth ?? dueDay
                
            }
        case .later:
            bills = self.withoutCreditCards.filter {
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

