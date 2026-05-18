//
//  MoneyMapWatchApp.swift
//  MoneyMapWatch
//
//  Created by Codex on 5/13/26.
//

import SwiftData
import SwiftUI

@main
struct MoneyMapWatchApp: App {
    private let modelContainer: ModelContainer = {
        (try? MoneyMapSharedContainerFactory.make()) ?? MoneyMapSharedContainerFactory.makeInMemory()
    }()

    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
                .modelContainer(modelContainer)
        }
    }
}
