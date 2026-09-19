//
//  NotificationViewController.swift
//  MoneyMapNotificationExtension
//
//  Created by Codex on 8/12/26.
//

import SwiftUI
import UIKit
import UserNotifications
import UserNotificationsUI

final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private var hostingController: UIHostingController<BillNotificationPreview>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        let preview = BillNotificationPreview(
            title: value(for: "bill_name", in: content.userInfo) ?? content.title,
            amount: value(for: "bill_amount", in: content.userInfo) ?? "",
            dueDate: value(for: "bill_due_date_text", in: content.userInfo) ?? "",
            paymentState: value(for: "bill_payment_state", in: content.userInfo) ?? content.subtitle,
            paymentDetail: value(for: "bill_payment_detail", in: content.userInfo) ?? ""
        )

        if let hostingController {
            hostingController.rootView = preview
            return
        }

        let hostingController = UIHostingController(rootView: preview)
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
        self.hostingController = hostingController
    }

    private func value(for key: String, in userInfo: [AnyHashable: Any]) -> String? {
        userInfo[key] as? String
    }
}

struct BillNotificationPreview: View {
    let title: String
    let amount: String
    let dueDate: String
    let paymentState: String
    let paymentDetail: String

    private var isAutopay: Bool {
        paymentState.localizedCaseInsensitiveContains("auto")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isAutopay ? "arrow.triangle.2.circlepath.circle.fill" : "hand.tap.fill")
                    .font(.title2)
                    .foregroundStyle(isAutopay ? .green : .orange)
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(paymentState)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isAutopay ? .green : .orange)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                previewMetric("Amount", amount.isEmpty ? "Not set" : amount, systemImage: "dollarsign.circle")
                previewMetric("Due", dueDate.isEmpty ? "No date" : dueDate, systemImage: "calendar")
            }

            if !paymentDetail.isEmpty {
                Label(paymentDetail, systemImage: "wallet.pass")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func previewMetric(_ title: String, _ value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
