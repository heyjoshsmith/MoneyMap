//
//  Item.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/11/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
