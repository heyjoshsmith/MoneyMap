//
//  SyncStatusView.swift
//  MoneyMap
//
//  Created by Josh Smith on 5/18/25.
//


import SwiftUI
import CloudKit

private extension CKAccountStatus {
  var displayName: String {
    switch self {
    case .available: return "Available"
    case .noAccount: return "No iCloud Account"
    case .restricted: return "Restricted"
    case .couldNotDetermine: return "Unknown"
    case .temporarilyUnavailable: return "Temporarily Unavailable"
    @unknown default: return "Unknown"
    }
  }
}

struct SyncStatusView: View {
  @StateObject private var status = iCloudStatus()
  @StateObject private var syncMgr = SyncManager()

  var body: some View {
      NavigationStack {
          List {
              Section {
                  MoneyMapSummaryRow(
                      title: "Account",
                      value: status.accountStatus.displayName,
                      detail: syncMgr.isSyncing ? "Syncing" : lastSyncText,
                      systemImage: status.accountStatus == .available ? "icloud" : "exclamationmark.icloud",
                      tint: status.accountStatus == .available ? MoneyMapDesign.calmGreen : MoneyMapDesign.warningGold
                  )
                  
                  if syncMgr.isSyncing {
                      ProgressView("Syncing…")
                  }
              }
              .listRowBackground(MoneyMapDesign.surfaceBackground)
              
              Section("Records") {
                  if syncMgr.recordCounts.isEmpty {
                      MoneyMapEmptyState(
                          title: "No Records Found",
                          message: "CloudKit records will appear here after sync.",
                          systemImage: "tray"
                      )
                  } else {
                      ForEach(syncMgr.recordCounts.sorted { $0.key < $1.key }, id: \.key) { type, count in
                          HStack {
                              Text("\(type)s:")
                              Text("\(count)")
                              Spacer()
                          }
                      }
                  }
              }
              .listRowBackground(MoneyMapDesign.surfaceBackground)
              
              Section {
                  Button {
                    syncMgr.syncNow()
                    syncMgr.refreshAllCounts()
                  } label: {
                      MoneyMapActionListRow(
                          title: "Sync Now",
                          detail: "Refresh iCloud record counts.",
                          systemImage: "arrow.triangle.2.circlepath",
                          tint: MoneyMapDesign.calmGreen
                      )
                  }
                  .buttonStyle(.plain)
              }
              .listRowBackground(MoneyMapDesign.surfaceBackground)
              
          }
          .refreshable {
              status.refresh()
          }
          .listStyle(.insetGrouped)
          .scrollContentBackground(.hidden)
          .background(MoneyMapDesign.groupedBackground)
          .navigationTitle("iCloud Status")
          .onAppear {
            status.refresh()
            syncMgr.fetchRecordCount(ofType: "Goal")
            syncMgr.fetchRecordCount(ofType: "Bill")
            syncMgr.fetchRecordCount(ofType: "PaydayConfig")
          }
      }
  }

  private var lastSyncText: String {
      syncMgr.lastSyncDate.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "Never synced"
  }
}

#Preview {
    SyncStatusView()
}
