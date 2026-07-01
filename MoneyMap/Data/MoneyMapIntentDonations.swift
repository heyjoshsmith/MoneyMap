//
//  MoneyMapIntentDonations.swift
//  MoneyMap
//
//  Created by Codex on 6/16/26.
//

import AppIntents
import Foundation

enum MoneyMapIntentDonations {
    static func donateOpenBill(_ bill: Bill) {
        Task {
            let intent = OpenBillIntent()
            intent.bill = BillEntity(bill)
            _ = try? await IntentDonationManager.shared.donate(intent: intent)
        }
    }

    static func donateOpenGoal(_ goal: Goal) {
        Task {
            let intent = OpenGoalIntent()
            intent.goal = GoalEntity(goal)
            _ = try? await IntentDonationManager.shared.donate(intent: intent)
        }
    }

    static func donateMarkBillPaid(_ bill: Bill, paymentAmount: Double? = nil) {
        Task {
            let intent = MarkBillPaidIntent()
            intent.bill = BillEntity(bill)
            intent.paymentAmount = paymentAmount
            _ = try? await IntentDonationManager.shared.donate(intent: intent)
        }
    }

    static func donatePaycheckPlan(availableCash: Double?) {
        Task {
            let intent = GetPaycheckRecommendationIntent()
            intent.availableCash = availableCash
            _ = try? await IntentDonationManager.shared.donate(intent: intent)
        }
    }

    static func donateSavingsSummary(goal: Goal? = nil) {
        Task {
            let intent = GetSavingsSummaryIntent()
            intent.goal = goal.map(GoalEntity.init)
            _ = try? await IntentDonationManager.shared.donate(intent: intent)
        }
    }

    static func donateBillDueDate(_ bill: Bill) {
        Task {
            let intent = GetBillDueDateIntent()
            intent.bill = BillEntity(bill)
            _ = try? await IntentDonationManager.shared.donate(intent: intent)
        }
    }

    static func donateNextPayday() {
        Task {
            let intent = GetNextPaydayIntent()
            _ = try? await IntentDonationManager.shared.donate(intent: intent)
        }
    }

    static func donateCashAfterBills() {
        Task {
            let intent = GetCashAfterBillsIntent()
            _ = try? await IntentDonationManager.shared.donate(intent: intent)
        }
    }
}
