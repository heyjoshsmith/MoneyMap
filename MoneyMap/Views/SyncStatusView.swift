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
                  HStack {
                      Text("Account")
                      Spacer()
                      Text(status.accountStatus.displayName)
                          .foregroundStyle(.secondary)
                  }
                  
                  if syncMgr.isSyncing {
                      ProgressView("Syncing…")
                  } else {
                      HStack {
                          Text("Last Sync")
                          Spacer()
                          Text(syncMgr.lastSyncDate.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) }
                               ?? "Never")
                          .foregroundStyle(.secondary)
                      }
                  }
              }
              
              Section("Records") {
                  if syncMgr.recordCounts.isEmpty {
                      Text("No Records Found")
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
              
              Section {
                  Button("Sync Now") {
                    syncMgr.syncNow()
                    syncMgr.refreshAllCounts()
                  }
              }
              
          }
          .refreshable {
              status.refresh()
          }
          .navigationTitle("iCloud Status")
          .onAppear {
            status.refresh()
            syncMgr.fetchRecordCount(ofType: "Goal")
            syncMgr.fetchRecordCount(ofType: "Bill")
            syncMgr.fetchRecordCount(ofType: "PaydayConfig")
          }
      }
  }
}

#Preview {
    SyncStatusView()
}
