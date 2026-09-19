#if os(iOS) || os(watchOS)
import Foundation
import WatchConnectivity

/// App-group defaults do not cross devices; WatchConnectivity transfers appearance only.
final class WatchThemeSync: NSObject, WCSessionDelegate {
    static let shared = WatchThemeSync()
    private var started = false
    func start() {
        guard !started, WCSession.isSupported() else { return }
        started = true
        WCSession.default.delegate = self
        WCSession.default.activate()
        #if os(iOS)
        NotificationCenter.default.addObserver(self, selector: #selector(sendTheme), name: UserDefaults.didChangeNotification, object: nil)
        #endif
    }
    @objc private func sendTheme() {
        #if os(iOS)
        let session = WCSession.default
        guard session.activationState == .activated, session.isWatchAppInstalled else { return }
        let raw = UserDefaults.standard.string(forKey: "moneyMapAppearanceStyle") ?? "warm"
        guard session.applicationContext["appearance"] as? String != raw else { return }
        try? session.updateApplicationContext(["appearance": raw])
        #endif
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        sendTheme()
        #if os(watchOS)
        apply(session.receivedApplicationContext)
        #endif
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { apply(applicationContext) }
    private func apply(_ values: [String: Any]) {
        #if os(watchOS)
        guard UserDefaults.standard.object(forKey: "watchFollowPhoneTheme") as? Bool ?? true,
              let raw = values["appearance"] as? String, MoneyMapSharedAppearanceStyle(rawValue: raw) != nil else { return }
        DispatchQueue.main.async { MoneyMapSharedDesign.setAppearanceStyleRawValue(raw); UserDefaults.standard.set(raw, forKey: "moneyMapAppearanceStyle") }
        #endif
    }
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
#endif
