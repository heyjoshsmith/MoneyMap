//
//  CardView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/17/25.
//

import SwiftUI
import SwiftData

struct GoalRowView: View {
    let goal: Goal

    private var progressValue: Double {
        min(max(goal.progress(), 0), 1)
    }

    private var title: String {
        goal.name ?? "Savings Goal"
    }

    private var deadlineText: String {
        guard let deadline = goal.deadline else { return "No deadline set" }
        return "By \(MoneyMapFormatters.mediumDateString(for: deadline))"
    }

    private var progressText: String {
        progressValue.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            GoalThumbnail(goal: goal, size: 48)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(progressText)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(progressValue >= 1 ? MoneyMapDesign.calmGreen : .secondary)
                }

                ProgressView(value: progressValue)
                    .tint(progressValue >= 1 ? MoneyMapDesign.calmGreen : .accentColor)

                HStack(spacing: 12) {
                    Label(deadlineText, systemImage: "calendar")
                    Label("\(MoneyMapFormatters.currencyString(for: goal.remainingAmount)) left", systemImage: "dollarsign.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct GoalThumbnail: View {
    let goal: Goal
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let uiImage = goal.uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "target")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(MoneyMapDesign.calmGreen)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MoneyMapDesign.controlBackground)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: MoneyMapDesign.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MoneyMapDesign.cornerRadius)
                .stroke(MoneyMapDesign.separator, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

struct CardView: View {
    
    init(for goal: Goal) {
        self.goal = goal
    }
    
    let goal: Goal

    private var progressValue: Double {
        min(max(goal.progress(), 0), 1)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            ZStack(alignment: .topLeading) {
                GeometryReader { proxy in
                    if let uiImage = goal.uiImage {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: 200)
                            .clipped()
                    } else {
                        ZStack {
                            MoneyMapDesign.moneyGradient
                            Image(systemName: "target")
                                .font(.system(size: 56, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                        .frame(width: proxy.size.width, height: 200)
                    }
                }
                .frame(height: 200)
                
                Gauge(value: progressValue, in: 0...1) {
                    Text("Progress")
                } currentValueLabel: {
                    Text(progressValue.formatted(.percent.precision(.fractionLength(0))))
                }
                .tint(goal.imageData == nil ? .white : MoneyMapDesign.calmGreen)
                .gaugeStyle(.accessoryCircularCapacity)
                .padding(12)
                
            }
            .clipShape(RoundedRectangle(cornerRadius: MoneyMapDesign.cornerRadius))
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(goal.name ?? "Savings Goal")
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    MoneyMapMoneyText(amount: goal.targetAmount ?? 0, font: .headline)
                }

                ProgressView(value: progressValue)
                    .tint(MoneyMapDesign.calmGreen)

                HStack(spacing: 12) {
                    Label("\(MoneyMapFormatters.currencyString(for: goal.amountSaved)) saved", systemImage: "banknote")
                    Label("\(MoneyMapFormatters.currencyString(for: goal.remainingAmount)) left", systemImage: "dollarsign.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .padding(12)
        .background(MoneyMapDesign.surfaceBackground, in: RoundedRectangle(cornerRadius: MoneyMapDesign.sectionCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MoneyMapDesign.sectionCornerRadius)
                .stroke(MoneyMapDesign.separator, lineWidth: 1)
        }
        .foregroundStyle(Color.primary)
        .accessibilityElement(children: .combine)
    }
}
