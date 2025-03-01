//
//  PaydayView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/12/25.
//

import SwiftUI

struct PaydayView: View {
    
    @EnvironmentObject var paydayManager: PaydayManager
    @State private var selectedDate = Date()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                
                Spacer()
                
                // Display a counter for days until next payday.
                if let _ = paydayManager.nextPayday {
                    
                    let daysRemaining = paydayManager.daysUntilNextPayday()
                    let dayString = String(format: "%02d", daysRemaining) // Ensures two digits (e.g., "03", "15")
                    let digits = Array(dayString) // Converts to character array ["0", "3"]
                    
                    VStack(spacing: 10) {
                        // HStack for the two digit blocks
                        HStack(spacing: 10) {
                            ForEach(digits, id: \.self) { digit in
                                Text(String(digit))
                                    .font(.system(size: 80, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity, minHeight: 120) // Equal width
                                    .background(
                                        LinearGradient(gradient: Gradient(colors: [.blue, .purple]),
                                                       startPoint: .topLeading,
                                                       endPoint: .bottomTrailing)
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        
                        // Title below the digit blocks
                        Text("Days until next payday")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .padding(.top, 5)
                    }
                    
                    Spacer()
                    
                } else {
                    Text("Please select your next payday")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(.rect(cornerRadius: 10))
                    
                    // Calendar picker for selecting the next payday.
                    DatePicker("Select Next Payday", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(GraphicalDatePickerStyle())
                        .padding()
                    
                    Spacer()
                                        
                    Button(action: {
                        paydayManager.savePayday(selectedDate)
                    }) {
                        Label("Set Next Payday", systemImage: "checkmark.circle")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                LinearGradient(gradient: Gradient(colors: [.green, .blue]),
                                               startPoint: .leading,
                                               endPoint: .trailing)
                            )
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
            .padding()
            .navigationTitle("Payday Settings")
        }
    }
}

#Preview("Goals") {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    GoalsView()
        .environmentObject(paydayManager)
        .modelContainer(container)
}
