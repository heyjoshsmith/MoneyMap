//
//  MoneyMapApp.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/11/25.
//

import SwiftUI
import SwiftData
import CoreSpotlight
import TipKit


@main
struct MoneyMapApp: App {
    @StateObject private var deepLinkManager = DeepLinkManager()
    @StateObject private var notificationManager = NotificationManager()
    
    var modelContainer: ModelContainer = {
        (try? SharedModelContainerFactory.make()) ?? SharedModelContainerFactory.makeInMemory()
    }()
    
    var body: some Scene {
        WindowGroup {
            let context = modelContainer.mainContext
            ContentView()
                .environmentObject(PaydayManager(context: context))
                .environmentObject(deepLinkManager)
                .environmentObject(notificationManager)
                .modelContainer(modelContainer)
                .onOpenURL { url in
                    deepLinkManager.handle(url: url)
                }
                .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
                    if let route = SpotlightIndexer.routeFromSearchableItemActivity(userActivity) {
                        deepLinkManager.pendingRoute = route
                    }
                }
                .task {
                    notificationManager.attach(deepLinkManager: deepLinkManager)
                    try? Tips.configure([
                        .displayFrequency(.daily)
                    ])
                }
        }
    }
    
}

#Preview("MoneyMap") {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    ContentView()
        .environmentObject(paydayManager)
        .environmentObject(DeepLinkManager())
        .environmentObject(NotificationManager())
        .modelContainer(container)
}
