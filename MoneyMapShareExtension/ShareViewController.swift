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
    
    private lazy var container: ModelContainer? = {
        try? MoneyMapSharedContainerFactory.make()
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        guard let context = extensionContext, let container else {
            let fallback = Text("Unable to open share extension.")
                .padding()
            let host = UIHostingController(rootView: fallback)
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
            return
        }

        // Pass the actual context into your SwiftUI view.
        let shareView = ShareView(context: context).modelContainer(container)
        let host = UIHostingController(rootView: shareView)

        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
