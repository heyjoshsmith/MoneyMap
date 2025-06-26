//
//  MoneyMapApp.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/11/25.
//

import SwiftUI
import SwiftData
import MoneyMapShared

@main
struct MoneyMapApp: App {
    
    var modelContainer: ModelContainer = {
        let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.heyjoshsmith.MoneyMap")!

        let storeURL = containerURL.appendingPathComponent("shared.sqlite")
        let schema = Schema([Goal.self, PaydayConfig.self, Bill.self])
        do {
            if let container = try? ModelContainer(
                for: schema,
                configurations: [
                    ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .private("iCloud.com.heyjoshsmith.MoneyMap"))
                ]
            ) {
                return container
            } else {
                return try ModelContainer(
                    for: schema,
                    configurations: [
                        ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
                    ]
                )
            }
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
