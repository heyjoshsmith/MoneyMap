import AppKit
import Foundation

@main struct MacBackgroundLifecycleFixtures {
    @MainActor static func main() throws {
        let application = NSApplication.shared
        let defaults = UserDefaults.standard
        let keys = [MacBackgroundLifecycle.keepRunningKey, MacBackgroundLifecycle.menuBarOnlyKey]
        let original = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, original) { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
        func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: message, code: 1) }
        }
        defaults.set(false, forKey: MacBackgroundLifecycle.menuBarOnlyKey)
        defaults.set(true, forKey: MacBackgroundLifecycle.keepRunningKey)
        let lifecycle = MacBackgroundLifecycle()
        try check(!lifecycle.applicationShouldTerminateAfterLastWindowClosed(application), "Last window does not stop background service")
        try check(lifecycle.applicationShouldTerminate(application) == .terminateCancel, "Ordinary Quit preserves service")
        try check(lifecycle.isInMenuBar && application.activationPolicy() == .accessory, "Background mode removes Dock presence")
        var reopened = false
        lifecycle.openMainWindow = { reopened = true }
        lifecycle.showWorkspace()
        try check(reopened && !lifecycle.isInMenuBar && application.activationPolicy() == .regular, "Open restores workspace and Dock presence")
        defaults.set(false, forKey: MacBackgroundLifecycle.keepRunningKey)
        try check(lifecycle.applicationShouldTerminate(application) == .terminateNow, "Opting out restores full Quit")
        try check(lifecycle.applicationShouldTerminateAfterLastWindowClosed(application), "Opting out allows termination after last window")
        print("PASS: 6 background lifecycle checks against actual AppKit activation policy")
    }
}
