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
    
    var overUtilized: Bool {
        utilization > 0.3
    }
}

// MARK: - Bill Model

@Model
class Bill {
    var id: UUID = UUID()
    var name: String
    var amount: Double
    var dueDate: Date
    var datePaid: Date?
    var category: BillCategory
    var recurrenceInterval: Int
    var recurrenceUnit: RecurrenceUnit
    var creditCardDetails: CreditCardDetails?
    var status: Status?

    init(name: String, amount: Double, dueDate: Date, category: BillCategory, recurrenceInterval: Int, recurrenceUnit: RecurrenceUnit, creditCardDetails: CreditCardDetails? = nil) {
        self.name = name
        self.amount = amount
        self.dueDate = dueDate
        self.category = category
        self.recurrenceInterval = recurrenceInterval
        self.recurrenceUnit = recurrenceUnit
        self.creditCardDetails = creditCardDetails
    }
    
    func makePayment(of amount: Double) {
        self.creditCardDetails?.cardBalance -= amount
        datePaid = .now
        status = .paid
        checkStatus()
    }

}

enum Status: Codable {
    
    case paid
    case overdue
    case upcoming(days: Int)
    
    var name: String {
        switch self {
        case .paid:
            return "Paid"
        case .overdue:
            return "Overdue"
        case .upcoming(let days):
            return "\(days) days"
        }
    }
    
    var color: Color {
        switch self {
        case .paid:
            return .green
        case .overdue:
            return .red
        case .upcoming(let days):
            switch days {
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
        return lhs.dueDate < rhs.dueDate
    }
    
    static func byName(lhs: Bill, rhs: Bill) -> Bool {
        return lhs.name < rhs.name
    }
    
    static func byBalance(lhs: Bill, rhs: Bill) -> Bool {
        return lhs.creditCardDetails?.cardBalance ?? 0 < rhs.creditCardDetails?.cardBalance ?? 0
    }
    
    static func byLimit(lhs: Bill, rhs: Bill) -> Bool {
        return lhs.creditCardDetails?.creditLimit ?? 0 < rhs.creditCardDetails?.creditLimit ?? 0
    }
    
    
    // MARK: - Functions
    
    func checkStatus() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDay = calendar.startOfDay(for: dueDate)
        
        if let _ = datePaid {
            // If the bill is paid, check if the current billing period has ended
            if today > dueDay {
                // Billing period ended; update dueDate to the next period
                switch recurrenceUnit {
                case .day:
                    dueDate = calendar.date(byAdding: .day, value: recurrenceInterval, to: dueDate)!
                case .week:
                    dueDate = calendar.date(byAdding: .day, value: 7 * recurrenceInterval, to: dueDate)!
                case .month:
                    dueDate = calendar.date(byAdding: .month, value: recurrenceInterval, to: dueDate)!
                case .year:
                    dueDate = calendar.date(byAdding: .year, value: recurrenceInterval, to: dueDate)!
                }
                // Clear the payment date since we're starting a new billing cycle
                datePaid = nil
                
                let newDueDay = calendar.startOfDay(for: dueDate)
                let daysDifference = calendar.dateComponents([.day], from: today, to: newDueDay).day ?? 0
                
                if daysDifference >= 0 {
                    status = .upcoming(days: daysDifference)
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
                status = .upcoming(days: daysDifference)
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
    
    static func sampleBills() -> Bills {
        return [
            Bill(name: "Electricity", amount: 100.0, dueDate: Date(), category: .utilities, recurrenceInterval: 1, recurrenceUnit: .month),
            Bill(name: "Water", amount: 50.0, dueDate: Date(), category: .utilities, recurrenceInterval: 1, recurrenceUnit: .month),
            Bill(name: "Rent", amount: 1200.0, dueDate: Date(), category: .rent, recurrenceInterval: 1, recurrenceUnit: .month)
        ]
    }
    
    static var sampleCreditCard: Bill {
        
        let limit = Double.random(in: 1_000...50_000)
        let balance = Double.random(in: 0...limit)
        let details = CreditCardDetails(creditLimit: limit, cardBalance: balance)
        
        return Bill(
            name: "American Express",
            amount: 200,
            dueDate: .now,
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: details
        )
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

typealias Bills = [Bill]
extension Bills {
    
    var totalAmount: Double {
        reduce(0) { $0 + $1.amount }
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
        return totalBalance / totalCreditLimit
    }
}
