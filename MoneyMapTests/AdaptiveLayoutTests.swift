import SwiftUI
import UIKit
import XCTest
@testable import MoneyMap

@MainActor
final class AdaptiveLayoutTests: XCTestCase {
    func testResizingKeepsPrimaryDraftAndIdentityWhileCompanionAppearsAndDisappears() async {
        let recorder = LayoutRecorder()
        let controller = UIHostingController(rootView: LayoutFixture(recorder: recorder))
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            XCTFail("The app-hosted test requires a window scene")
            return
        }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = parent
        window.isHidden = false
        parent.addChild(controller)
        parent.view.addSubview(controller.view)
        controller.view.autoresizingMask = []
        controller.didMove(toParent: parent)
        defer {
            window.isHidden = true
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }

        await resize(controller, parent: parent, width: 390)
        XCTAssertFalse(recorder.companionVisible)
        XCTAssertEqual(recorder.identities.count, 1)
        let identity = recorder.identities.first
        recorder.editDraft?("1750")

        await resize(controller, parent: parent, width: 1000)
        XCTAssertTrue(recorder.companionVisible)
        XCTAssertEqual(recorder.identities, Set([identity].compactMap { $0 }))
        XCTAssertEqual(recorder.latestDraft, "1750")

        await resize(controller, parent: parent, width: 390)
        XCTAssertFalse(recorder.companionVisible)
        XCTAssertEqual(recorder.identities.count, 1)
        XCTAssertEqual(recorder.latestDraft, "1750")

        // Accessibility text collapses the same wide container without resetting its draft.
        await resize(controller, parent: parent, width: 1000)
        recorder.typeSize = .accessibility3
        await settle(controller)
        XCTAssertFalse(recorder.companionVisible)
        XCTAssertEqual(recorder.identities.count, 1)
        XCTAssertEqual(recorder.latestDraft, "1750")
    }

    private func resize<Content: View>(_ controller: UIHostingController<Content>, parent: UIViewController, width: CGFloat) async {
        controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 850)
        await settle(controller)
    }

    private func settle<Content: View>(_ controller: UIHostingController<Content>) async {
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(150))
        controller.view.layoutIfNeeded()
    }
}

@MainActor
private final class LayoutRecorder: ObservableObject {
    @Published var typeSize: DynamicTypeSize = .large
    var identities: Set<UUID> = []
    var latestDraft = ""
    var editDraft: ((String) -> Void)?
    var companionVisible = false
}

private struct LayoutFixture: View {
    @ObservedObject var recorder: LayoutRecorder

    var body: some View {
        MoneyMapCompanionLayout { _ in
            DraftProbe(recorder: recorder)
        } companion: {
            Text("Preview")
                .onAppear { recorder.companionVisible = true }
                .onDisappear { recorder.companionVisible = false }
        }
        .environment(\.horizontalSizeClass, .regular)
        .environment(\.dynamicTypeSize, recorder.typeSize)
    }
}

private struct DraftProbe: View {
    let recorder: LayoutRecorder
    @State private var identity = UUID()
    @State private var draft = "1000"

    var body: some View {
        ScrollView {
            TextField("Amount", text: $draft)
        }
        .onAppear {
            recorder.identities.insert(identity)
            recorder.latestDraft = draft
            recorder.editDraft = { draft = $0 }
        }
        .onChange(of: draft) { _, value in recorder.latestDraft = value }
    }
}
