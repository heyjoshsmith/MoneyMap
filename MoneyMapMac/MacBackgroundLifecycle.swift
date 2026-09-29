import AppKit
import CoreServices
import OSLog
import SwiftUI

@MainActor
final class MacBackgroundLifecycle: NSObject, NSApplicationDelegate, ObservableObject {
    static let keepRunningKey = "mac.keepSyncRunningAfterClosing"
    static let menuBarOnlyKey = "mac.menuBarOnly"
    @Published private(set) var isInMenuBar = UserDefaults.standard.bool(forKey: menuBarOnlyKey) || ProcessInfo.processInfo.arguments.contains("--menu-bar-only")
    private let logger = Logger(subsystem: "com.heyjoshsmith.MoneyMap.Mac", category: "BackgroundLifecycle")
    var openMainWindow: (() -> Void)?
    private var quitFully = false
    private var activity: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?
    private var visibilityObserver: NSObjectProtocol?
    private weak var mainWindow: NSWindow?
    var keepsRunning: Bool { UserDefaults.standard.object(forKey: Self.keepRunningKey) as? Bool ?? true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Continue processing user-requested bank updates while hidden, without blocking idle sleep.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Keep bank sync and iPhone update requests available")
        if isInMenuBar { moveToMenuBar() }
    }

    func register(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        mainWindow = window
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self, weak window] _ in
            Task { @MainActor in
                if self?.isInMenuBar == true { window?.orderOut(nil) }
            }
        }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.keepsRunning else { return }
                self.moveToMenuBar()
            }
        }
        if isInMenuBar { window.orderOut(nil); NSApp.setActivationPolicy(.accessory) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !keepsRunning }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWorkspace()
        return false
    }

    func moveToMenuBar() {
        isInMenuBar = true
        UserDefaults.standard.set(true, forKey: Self.menuBarOnlyKey)
        // Include Settings and attached sheets; leave the menu bar extra itself alone.
        for window in NSApp.windows where window.level == .normal && window.canBecomeMain { window.orderOut(nil) }
        NSApp.setActivationPolicy(.accessory)
        if NSApp.activationPolicy() == .accessory { logger.info("Menu bar mode active; bank service remains running without a Dock icon.") }
    }

    func showWorkspace() {
        isInMenuBar = false
        UserDefaults.standard.set(false, forKey: Self.menuBarOnlyKey)
        NSApp.setActivationPolicy(.regular)
        openMainWindow?()
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWorkspaceOrQuit() {
        if keepsRunning { moveToMenuBar() }
        else { quitCompletely() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Dock Quit follows the same preference as Command-Q. System logout, restart,
        // shutdown, and Quit All carry a reason and must never be canceled.
        let systemQuit = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil
        if quitFully || !keepsRunning || systemQuit { return .terminateNow }
        moveToMenuBar()
        return .terminateCancel
    }

    func quitCompletely() {
        quitFully = true
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }
}

struct MacWorkspaceWindowBridge: NSViewRepresentable {
    let lifecycle: MacBackgroundLifecycle
    let openWindow: () -> Void
    func makeNSView(context: Context) -> WindowObserver {
        let view = WindowObserver()
        view.lifecycle = lifecycle
        lifecycle.openMainWindow = openWindow
        return view
    }
    func updateNSView(_ view: WindowObserver, context: Context) {
        lifecycle.openMainWindow = openWindow
    }
    final class WindowObserver: NSView {
        weak var lifecycle: MacBackgroundLifecycle?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { lifecycle?.register(window) }
        }
    }
}
