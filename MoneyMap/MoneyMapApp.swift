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

        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.heyjoshsmith.MoneyMap") else {
            return Self.makeInMemoryContainer(for: schema)
        }

        let storeURL = containerURL.appendingPathComponent("shared.sqlite")

        if let cloudContainer = try? ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .private("iCloud.com.heyjoshsmith.MoneyMap"))
            ]
        ) {
            return cloudContainer
        }

        if let localContainer = try? ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            ]
        ) {
            return localContainer
        }

        return Self.makeInMemoryContainer(for: schema)
    }()
    
    var body: some Scene {
        WindowGroup {
            let context = modelContainer.mainContext
            ContentView()
                .environmentObject(PaydayManager(context: context))
                .modelContainer(modelContainer)
                .onOpenURL(perform: handleURL)
        }
    }
    
    func handleURL(url: URL) {
        
    }
    
    private static func makeInMemoryContainer(for schema: Schema) -> ModelContainer {
        if let container = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ) {
            return container
        }
        preconditionFailure("Could not create any SwiftData container configuration.")
    }
}

#Preview("MoneyMap") {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    ContentView()
        .environmentObject(paydayManager)
        .modelContainer(container)
}
