//
//  CalendarView.swift
//  MoneyMap
//
//  Created by Josh Smith on 5/18/25.
//

import SwiftUI

struct CalendarView: View {
    
    init(for date: Date, priority: Bool = false, bonus: Bool = false) {
        self.date = date
        self.priority = priority
        self.bonus = bonus
    }
    
    var date: Date
    var priority: Bool = false
    var bonus: Bool = false
    
    var body: some View {
        VStack {
            if priority {
                VStack {
                    Text(date.daysUntil)
                        .font(.largeTitle.weight(.semibold))
                    Text(date.formatted(date: .long, time: .omitted))
                }
                .shadow(radius: 5)
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundStyle(.white)
                .frame(minHeight: 200)
                .background(
                    ZStack {
                        LinearGradient(colors: bonus ? [.blue, .mint] : [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                        RainingDollarSignsView()
                    }
                )
                .clipShape(.rect(cornerRadius: 15))
            } else {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.title3.weight(.medium))
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 8))
            }
        }
    }
}

enum SymbolStyle {
    case emoji, sfSymbol
}

struct SymbolModel: Identifiable {
    let id = UUID()
    let symbolName: String
    let xPosition: CGFloat
    let rotation: Double
    let duration: Double
    let delay: Double
}

struct RainingDollarSignsView: View {
    var symbolStyle: SymbolStyle = .emoji
    private let models: [SymbolModel]
    private let startDate = Date()
    
    init(symbolStyle: SymbolStyle = .emoji, count: Int = 30) {
        self.symbolStyle = symbolStyle
        self.models = (0..<count).map { index in
            let symbols = symbolStyle == .emoji
                ? ["💸","🛍️","💰","🤑","💎","👛","💳","🧾","📈","🏦"]
                : ["dollarsign.circle.fill","creditcard.fill","cart.fill","bag.fill","gift.fill","wallet.pass.fill"]
            return SymbolModel(
                symbolName: symbols.randomElement()!,
                xPosition: .random(in: 0...1),
                rotation: Double.random(in: -30...30),
                duration: Double.random(in: 3...6),
                delay: Double(index) * 0.2
            )
        }
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSince(startDate)
                ZStack {
                    ForEach(models) { model in
                        let localTime = elapsed - model.delay
                        if localTime >= 0 {
                            let cyclePosition = (localTime.truncatingRemainder(dividingBy: model.duration)) / model.duration
                            let y = -50 + (geo.size.height + 100) * CGFloat(cyclePosition)
                            Group {
                                if symbolStyle == .emoji {
                                    Text(model.symbolName).font(.title)
                                } else {
                                    Image(systemName: model.symbolName).font(.title)
                                }
                            }
                            .foregroundColor(.white.opacity(0.6))
                            .rotationEffect(.degrees(model.rotation))
                            .position(x: model.xPosition * geo.size.width, y: y)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }
        }
    }
}

#Preview {
    CalendarView(for: .now, priority: true)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
}
