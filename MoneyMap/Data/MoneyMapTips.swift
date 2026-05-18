//
//  MoneyMapTips.swift
//  MoneyMap
//
//  Created by Codex on 4/27/26.
//

import SwiftUI
import TipKit

struct RecommendationStrategiesTip: Tip {
    var title: Text {
        Text("Try Different Payoff Modes")
    }

    var message: Text? {
        Text("Switch between balanced, avalanche, snowball, and due-date strategies to see how your paycheck plan changes.")
    }

    var image: Image? {
        Image(systemName: "wand.and.stars")
    }
}

struct RecommendationApplyTip: Tip {
    var title: Text {
        Text("Apply the Plan in One Tap")
    }

    var message: Text? {
        Text("When a plan looks right, apply the recommended goal contributions or card payments directly from this screen.")
    }

    var image: Image? {
        Image(systemName: "checkmark.circle")
    }
}

struct AutopayBillTip: Tip {
    var title: Text {
        Text("Autopay Keeps Dates Current")
    }

    var message: Text? {
        Text("Turn on autopay for bills you don’t manually mark paid so upcoming dates keep rolling forward automatically.")
    }

    var image: Image? {
        Image(systemName: "arrow.triangle.2.circlepath")
    }
}
