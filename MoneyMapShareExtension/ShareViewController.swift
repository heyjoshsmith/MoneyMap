//
//  ShareViewController.swift
//  MoneyMapShareExtension
//
//  Created by Josh Smith on 4/27/25.
//

import UIKit
import SwiftUI
import SwiftData
import MoneyMapShared

class ShareViewController: UIViewController {
    
    private lazy var container: ModelContainer = {
        let storeURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.heyjoshsmith.MoneyMap")!
            .appendingPathComponent("shared.sqlite")
        let config = ModelConfiguration(url: storeURL)
        let schema = Schema([Goal.self])
        return try! ModelContainer(for: schema, configurations: [config])
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // 4️⃣ Pass the actual context into your SwiftUI view
        let shareView = ShareView(context: extensionContext!).modelContainer(container)
        let host = UIHostingController(rootView: shareView)

        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
