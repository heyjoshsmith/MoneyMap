//
//  Currency.swift
//  AddMoneyMap
//
//  Created by Josh Smith on 12/17/25.
//

import Foundation

extension Double {
    var currency: String {
        return self.formatted(.currency(code: "USD"))
    }
}
