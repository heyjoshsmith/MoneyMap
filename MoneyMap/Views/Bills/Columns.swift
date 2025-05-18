//
//  Columns.swift
//  MoneyMap
//
//  Created by Josh Smith on 4/2/25.
//

import SwiftUI

typealias Columns = [GridItem]
extension Columns {
    
    init(_ number: Int, spacing: CGFloat? = nil) {
        var results = Columns()
        
        for _ in 0..<number {
            results.append(GridItem(.flexible(), spacing: spacing))
        }
        
        self = results
    }
    
}
