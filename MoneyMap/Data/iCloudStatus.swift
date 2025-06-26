//
//  iCloudStatus.swift
//  MoneyMap
//
//  Created by Josh Smith on 5/18/25.
//

import Foundation
import CloudKit

class iCloudStatus: ObservableObject {
  @Published var accountStatus: CKAccountStatus = .couldNotDetermine

  init() { refresh() }

  func refresh() {
    CKContainer.default().accountStatus { status, error in
      DispatchQueue.main.async {
        self.accountStatus = (error == nil ? status : .couldNotDetermine)
      }
    }
  }
}

class SyncManager: ObservableObject {
  @Published var isSyncing = false
  @Published var lastSyncDate: Date?

  private let container = CKContainer(identifier: "iCloud.com.heyjoshsmith.MoneyMap")
  private let db: CKDatabase = CKContainer.default().privateCloudDatabase
  private var serverToken: CKServerChangeToken?

  func syncNow() {
    isSyncing = true

    let op = CKFetchDatabaseChangesOperation(previousServerChangeToken: serverToken)
    op.changeTokenUpdatedBlock = { newToken in
      self.serverToken = newToken
    }
    op.fetchDatabaseChangesResultBlock = { result in
      DispatchQueue.main.async {
        switch result {
        case .success(let (token, _)):
          self.serverToken = token
          self.isSyncing = false
          self.lastSyncDate = Date()
        case .failure:
          self.isSyncing = false
        }
      }
    }

    db.add(op)
  }

  @Published var recordCounts: [String:Int] = [:]

  func fetchRecordCount(ofType type: String) {
    let query = CKQuery(recordType: type, predicate: .init(value: true))
    var count = 0

    let op = CKQueryOperation(query: query)
    op.recordMatchedBlock = { _, _ in count += 1 }
    op.queryResultBlock = { result in
      DispatchQueue.main.async {
        if case .success = result {
          self.recordCounts[type] = count
        }
      }
    }

    db.add(op)
  }

  func refreshAllCounts() {
    ["Goal","Bill","PaydayConfig"].forEach(fetchRecordCount)
  }
}

