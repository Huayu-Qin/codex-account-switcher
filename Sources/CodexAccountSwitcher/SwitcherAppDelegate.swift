import AppKit
import Combine
import SwiftUI

@MainActor
final class SwitcherAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel.live()
    let updater = AppUpdater()
    let tiboForecast = TiboForecastModel()

    private var accountPanel: NSPanel?
    private var modelObservation: AnyCancellable?
    private var hasFinishedLaunching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        hasFinishedLaunching = true
        // A crowded menu bar can keep the label offscreen. Startup must not
        // depend on that view appearing or on the user finding its icon.
        modelObservation = model.objectWillChange.sink { [weak self] in
            guard let self else { return }
            updater.accountOperationInProgress = model.isMutating || model.isAddingAccount
        }
        updater.start()
        tiboForecast.start()
        Task { await model.startBackgroundUsageRefresh() }

        if Self.shouldShowAccountsOnLaunch(event: NSAppleEventManager.shared().currentAppleEvent) {
            showAccounts()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if hasFinishedLaunching { showAccounts() }
        return false
    }

    static func shouldShowAccountsOnLaunch(event: NSAppleEventDescriptor?) -> Bool {
        let launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        return !launchedAtLogin
    }

    private func showAccounts() {
        // Recreate the content to return to the account list on every explicit
        // open, while reusing the model and the existing three-row sizing rule.
        accountPanel?.close()
        let content = MenuBarPopover(model: model, updater: updater, tiboForecast: tiboForecast)
            .fixedSize()
            .onExitCommand { [weak self] in self?.accountPanel?.close() }
        let host = NSHostingController(rootView: content)
        let panel = NSPanel(contentViewController: host)
        panel.title = "Codex Account Switcher"
        panel.styleMask = [.titled, .closable]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.setContentSize(host.sizeThatFits(in: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)))
        panel.center()
        accountPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}
