//
//  MoneyMapApp.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/11/25.
//

import SwiftUI
import SwiftData

@main
struct MoneyMapApp: App {
    
    var modelContainer: ModelContainer = {
        let schema = Schema([Goal.self, PaydayConfig.self, Bill.self])
        let modelConfiguration = ModelConfiguration(schema: schema)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            let context = modelContainer.mainContext
            ContentView()
                .environmentObject(PaydayManager(context: context))
                .modelContainer(modelContainer)
        }
    }
}

#Preview("MoneyMap") {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    ContentView()
        .environmentObject(paydayManager)
        .modelContainer(container)
}
