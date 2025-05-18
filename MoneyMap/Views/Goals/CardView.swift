//
//  CardView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/17/25.
//

import SwiftUI
import SwiftData
import MoneyMapShared

struct CardView: View {
    
    init(for goal: Goal) {
        self.goal = goal
    }
    
    let goal: Goal
    
    var body: some View {
        VStack(spacing: 0) {
            
            ZStack(alignment: .topLeading) {
                GeometryReader { proxy in
                    if let image = goal.loadImage() {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: 200)
                    } else {
                        Image(systemName: "target")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.white)
                            .padding(30)
                            .frame(width: proxy.size.width, height: 200)
                            .background(Color.green.gradient)
                    }
                }
                .frame(height: 200)
                
                Gauge(value: goal.progress(), in: 0...1) {
                    Text("Progress")
                } currentValueLabel: {
                    Text("\(Int(goal.progress() * 100))%")
                }
                .tint(goal.imageFileName == nil ? .white : .green)
                .gaugeStyle(.accessoryCircularCapacity)
                .shadow(radius: 15)
                .padding()
                
            }
            
            HStack {
                
                Text(goal.name ?? "Unknown")
                    .font(.title2.weight(.semibold))
                
                Spacer()
                
                Text(goal.targetAmount, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .foregroundStyle(.secondary)
                
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .foregroundStyle(Color.primary)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .clipShape(.rect(cornerRadius: 15))
    }
}
