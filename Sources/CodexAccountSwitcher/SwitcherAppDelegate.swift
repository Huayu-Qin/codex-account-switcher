import AppKit
import Combine
import SwiftUI

@MainActor
final class SwitcherAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel.live()
    let updater = AppUpdater()
    let tiboForecast = TiboForecastModel()

    private var utilityWindows: [Bool: NSWindow] = [:]
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

    func showAccounts() { showUtilityWindow(settings: false) }

    func showSettings() { showUtilityWindow(settings: true) }

    private func showUtilityWindow(settings: Bool) {
        let window = utilityWindows[settings] ?? makeUtilityWindow(settings: settings)
        // Rebuild closed windows so each explicit open starts on the first page.
        if !window.isVisible {
            window.contentViewController = NSHostingController(rootView: utilityContent(settings: settings))
            window.setContentSize(NSSize(width: 440, height: settings ? 540 : 520))
            window.center()
        }
        window.title = model.text(settings ? "settings" : "manage")
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeUtilityWindow(settings: Bool) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: utilityContent(settings: settings)))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 400, height: 320)
        utilityWindows[settings] = window
        return window
    }

    private func utilityContent(settings: Bool) -> some View {
        AccountUtilityWindow(model: model, updater: updater, settings: settings) { [weak self] in
            self?.utilityWindows[settings]?.close()
        }
        .onExitCommand { [weak self] in self?.utilityWindows[settings]?.close() }
    }
}
