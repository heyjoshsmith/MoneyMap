// AppModelContainerFactory.swift
// MoneyMap
// Provides the app-facing shim for the shared SwiftData container builder.

import Foundation
import SwiftData

enum SharedModelContainerFactory {
    static func make() throws -> ModelContainer {
        try MoneyMapSharedContainerFactory.make()
    }

    static func makeInMemory() -> ModelContainer {
        MoneyMapSharedContainerFactory.makeInMemory()
    }
}
