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
        let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.heyjoshsmith.MoneyMap")!

        let storeURL = containerURL.appendingPathComponent("shared.sqlite")
        // [DEV ONLY] Delete the store before SwiftData opens it. Remove for production!
//        deleteAndPrintStoreURL()

        let schema = Schema([Goal.self, PaydayConfig.self, Bill.self])
        do {
            if let container = try? ModelContainer(
                for: schema,
                configurations: [
                    ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .private("iCloud.com.heyjoshsmith.MoneyMap"))
                ]
            ) {
                // Diagnostics after container creation
                do {
                    let context = container.mainContext
                    
                    let billFetch = FetchDescriptor<Bill>()
                    let bills = try context.fetch(billFetch)
                    print("📝 [Diagnostics] Bills count: \(bills.count)")
                    for bill in bills {
                        print("📝 Bill - id: \(bill.id), name: \(bill.name), category: \(bill.category), dueDate: \(String(describing: bill.dueDate))")
                    }
                    
                    let goalFetch = FetchDescriptor<Goal>()
                    let goals = try context.fetch(goalFetch)
                    print("📝 [Diagnostics] Goals count: \(goals.count)")
                    for goal in goals {
                        print("📝 Goal - id: \(goal.id), name: \(goal.name), deadline: \(String(describing: goal.deadline))")
                    }
                } catch {
                    print("⚠️ [Diagnostics] Error fetching Bills or Goals: \(error)")
                }
                
                return container
            } else {
                let container = try ModelContainer(
                    for: schema,
                    configurations: [
                        ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
                    ]
                )
                
                // Diagnostics after container creation
                do {
                    let context = container.mainContext
                    
                    let billFetch = FetchDescriptor<Bill>()
                    let bills = try context.fetch(billFetch)
                    print("📝 [Diagnostics] Bills count: \(bills.count)")
                    for bill in bills {
                        print("📝 Bill - id: \(bill.id), name: \(bill.name), category: \(bill.category), dueDate: \(String(describing: bill.dueDate))")
                    }
                    
                    let goalFetch = FetchDescriptor<Goal>()
                    let goals = try context.fetch(goalFetch)
                    print("📝 [Diagnostics] Goals count: \(goals.count)")
                    for goal in goals {
                        print("📝 Goal - id: \(goal.id), name: \(goal.name), deadline: \(String(describing: goal.deadline))")
                    }
                } catch {
                    print("⚠️ [Diagnostics] Error fetching Bills or Goals: \(error)")
                }
                
                return container
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

