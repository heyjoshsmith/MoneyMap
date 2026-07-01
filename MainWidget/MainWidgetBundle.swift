//
//  MainWidgetBundle.swift
//  MainWidget
//
//  Created by Josh Smith on 3/4/26.
//

import WidgetKit
import SwiftUI

@main
struct MainWidgetBundle: WidgetBundle {
    var body: some Widget {
        MainWidget()
        PaydayCountdownWidget()
        NextBillWidget()
        UpcomingBillsListWidget()
    }
}
