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
    @StateObject private var notificationManager = NotificationManager()
    @StateObject private var paydayManager: PaydayManager
    @State private var sceneRouter = MoneyMapSceneRouter()
    private let modelContainer: ModelContainer
    @State private var didConfigureServices = false

    init() {
        let container = (try? SharedModelContainerFactory.make()) ?? SharedModelContainerFactory.makeInMemory()
        modelContainer = container
        _paydayManager = StateObject(wrappedValue: PaydayManager(context: container.mainContext))
        BackgroundTransactionSyncManager.register(modelContainer: container)
    }

    var body: some Scene {
        WindowGroup("MoneyMap", for: MoneyMapWindowContent.self) { $content in
            MoneyMapWindowRoot(sceneRouter: sceneRouter, initialContent: content)
                .environmentObject(paydayManager)
                .environmentObject(notificationManager)
                .modelContainer(modelContainer)
                .task {
                    guard !didConfigureServices else { return }
                    didConfigureServices = true
                    syncSharedAppearanceSetting()
                    WatchThemeSync.shared.start()
                    notificationManager.attach(sceneRouter: sceneRouter)
                    BackgroundTransactionSyncManager.scheduleAppRefresh()
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    try? Tips.configure([
                        .displayFrequency(.daily)
                    ])
                }
        }
        .commands { InspectorCommands() }
    }

    private func syncSharedAppearanceSetting() {
        let rawValue = UserDefaults.standard.string(forKey: MoneyMapDesign.appearanceStyleKey)
            ?? MoneyMapAppearanceStyle.warm.rawValue
        MoneyMapSharedDesign.setAppearanceStyleRawValue(rawValue)
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
