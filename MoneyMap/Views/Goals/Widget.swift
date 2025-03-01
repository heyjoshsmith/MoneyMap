//
//  Widget.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/28/25.
//

import SwiftUI

struct Widget: View {
    
    let action: (() -> Void)?
    
    let title: String
    let value: Double?
    let date: Date?
    let icon: String
    let color: Color
    let currency: Bool
    let columns: Int
    
    var body: some View {
        if let action {
            Button(action: action) {
                label
            }
        } else {
            label
        }
    }
    
    func isLessThanOneYearAway(from date: Date) -> Bool {
        let calendar = Calendar.current
        if let oneYearFromNow = calendar.date(byAdding: .year, value: 1, to: Date()) {
            return date < oneYearFromNow
        }
        return false
    }
    
    var label: some View {
        HStack(alignment: .center, spacing: 5) {
            
            Image(systemName: title == "Priority" ? (Priority(rawValue: value ?? 0) ?? Priority.medium).icon : icon)
                .resizable()
                .scaledToFit()
                .padding(5)
                .foregroundStyle(title == "Priority" ? (Priority(rawValue: value ?? 0) ?? Priority.medium).color.gradient : color.gradient)
                .frame(width: 40, height: 40, alignment: .center)
            
            VStack(alignment: .leading, spacing: 0) {
                
                Text(title)
                    .foregroundStyle(Color.primary)
                    .font(.callout)
                
                Group {
                    if let value {
                        if currency {
                            Text(value, format: .currency(code: "USD").precision(.fractionLength(0)))
                        } else if title == "Priority" {
                            Text(priority)
                        } else {
                            Text(value, format: .number)
                        }
                    } else if let date {
                        if isLessThanOneYearAway(from: date) {
                            Text(date, format: .dateTime.month().day())
                        } else {
                            Text(date, format: .dateTime.year())
                        }
                    }
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(title == "Priority" ? (Priority(rawValue: value ?? 0) ?? Priority.medium).color.gradient : color.gradient)
                
            }
            
            if (action != nil) {
                
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                    .padding(.trailing, 5)
            }
            
        }
        .padding(.vertical)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .foregroundColor(Color.primary)
        .cornerRadius(10)
        .gridCellColumns(columns)
    }
    
    var priority: String {
        switch value {
        case 2:
            return "High"
        case 1:
            return "Medium"
        default:
            return "Low"
        }
    }
    
    
    
    // Inits
    
    init(_ type: WidgetType, value: Double, currency: Bool = true, columns: Int = 1, action: (() -> Void)? = nil) {
        
        self.title = type.name
        self.icon = type.icon
        self.color = type.color
        
        self.value = value
        self.currency = currency
        self.columns = columns
        
        self.action = action
        
        self.date = nil
        
    }
    
    init(_ type: WidgetType, date: Date, currency: Bool = true, columns: Int = 1, action: (() -> Void)? = nil) {
        
        self.title = type.name
        self.icon = type.icon
        self.color = type.color
        
        self.date = date
        self.currency = currency
        self.columns = columns
        
        self.action = action
        
        self.value = nil
        
    }
    
    init(_ label: String, value: Double, icon: String, color: Color, currency: Bool = true, columns: Int = 1, action: (() -> Void)? = nil) {
        self.title = label
        self.value = value
        self.date = nil
        self.icon = icon
        self.color = color
        self.currency = currency
        self.columns = columns
        self.action = action
    }
    
    init(_ label: String, date: Date, icon: String, color: Color, currency: Bool = true, columns: Int = 1, action: (() -> Void)? = nil) {
        self.title = label
        self.value = nil
        self.date = date
        self.icon = icon
        self.color = color
        self.currency = currency
        self.columns = columns
        self.action = action
    }
    
}

enum WidgetType: String, CaseIterable, Identifiable {
    case targetAmount, deadline, daysUntilDeadline, numberOfPaydays, amountPerPaycheck, expectedAmount, amountSaved, remainingValue, priority
    
    var name: String {
        switch self {
        case .targetAmount:
            return "Goal"
        case .deadline:
            return "Deadline"
        case .daysUntilDeadline:
            return "Days Left"
        case .numberOfPaydays:
            return "Paydays Left"
        case .amountPerPaycheck:
            return "Per Paycheck"
        case .expectedAmount:
            return "Expected"
        case .amountSaved:
            return "Saved"
        case .remainingValue:
            return "Remaining"
        case .priority:
            return "Priority"
        }
    }
    
    var color: Color {
        switch self {
        case .targetAmount:
            return .green
        case .deadline:
            return .orange
        case .daysUntilDeadline:
            return .red
        case .numberOfPaydays:
            return .purple
        case .amountPerPaycheck:
            return .indigo
        case .expectedAmount:
            return .teal
        case .amountSaved:
            return .yellow
        case .remainingValue:
            return .blue
        case .priority:
            return .pink
        }
    }
    
    var icon: String {
        switch self {
        case .targetAmount:
            return "dollarsign.gauge.chart.leftthird.topthird.rightthird"
        case .deadline:
            return "calendar.badge.clock"
        case .daysUntilDeadline:
            return "calendar.badge.checkmark"
        case .numberOfPaydays:
            return "signature"
        case .amountPerPaycheck:
            return "square.and.arrow.down"
        case .expectedAmount:
            return "square.and.arrow.down"
        case .amountSaved:
            return "dollarsign.bank.building"
        case .remainingValue:
            return "dollarsign.arrow.trianglehead.counterclockwise.rotate.90"
        case .priority:
            return "exclamationmark.triangle"
        }
    }
    
    var id: Self { return self }
}

#Preview {
    Grid {
        GridRow {
            Widget(.targetAmount, value: 1000)
            Widget(.priority, value: 3, currency: false) {
                
            }
        }
    }
    .padding()
}
