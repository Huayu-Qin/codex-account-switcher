import SwitcherCore
import AppKit
import SwiftUI

@main
struct SwitcherApp: App {
    @StateObject private var model = AppModel.live()
    @StateObject private var updater = AppUpdater()

    var body: some Scene {
        MenuBarExtra {
            NativeAccountMenu(model: model, updater: updater)
        } label: {
            HStack(spacing: 4) {
                MenuBarLogo()
                    .overlay(alignment: .topTrailing) {
                        if updater.availableVersion != nil {
                            Circle().fill(.blue).frame(width: 5, height: 5)
                                .offset(x: 2, y: -1)
                        }
                    }
                Text(verbatim: menuBarTitle)
                    .monospacedDigit()

            }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(menuBarAccessibilityLabel)
                .task {
                    updater.start()
                    await model.start()
                    model.refreshWeeklyUsage()
                    await model.startBackgroundUsageRefresh()
                }
                .onChange(of: model.isMutating || model.isAddingAccount) { _, busy in
                    updater.accountOperationInProgress = busy
                }
        }
        .menuBarExtraStyle(.menu)
        .commands {
            QuitApplicationCommands(title: model.text("quit"))
        }

        Window("Manage Accounts", id: "accounts") {
            AccountUtilityWindow(model: model, updater: updater, settings: false)
        }
        .defaultSize(width: 440, height: 520)
        .windowResizability(.contentMinSize)

        Window("Settings", id: "settings") {
            AccountUtilityWindow(model: model, updater: updater, settings: true)
        }
        .defaultSize(width: 440, height: 540)
        .windowResizability(.contentMinSize)
    }

    // MenuBarExtra extracts a single text title from its label. Multiple Text
    // siblings can drop the percentage after the account name.
    private var menuBarTitle: String {
        var parts: [String] = []
        if let name = model.activeAccountName { parts.append(name) }
        if model.settings.showsMenuBarPercentage {
            parts.append(model.activeFiveHourRemainingPercent.map { "\($0)%" } ?? "—%")
        }
        return parts.joined(separator: "  ")
    }

    private var menuBarAccessibilityLabel: String {
        let updateStatus = updater.availableVersion.map { ", " + model.format("update_available", $0) } ?? ""
        guard model.settings.showsMenuBarPercentage,
              let remainingPercent = model.activeFiveHourRemainingPercent
        else {
            return "Codex Account Switcher" + updateStatus
        }
        return "Codex Account Switcher, \(model.activeAccountName ?? ""), 5-hour remaining \(remainingPercent)%" + updateStatus
    }
}

private struct MenuBarLogo: View {
    private static let logicalSize = NSSize(width: 17.5, height: 17.5)

    private static let image: NSImage = {
        let resourceBundleName = "CodexAccountSwitcher_CodexAccountSwitcher.bundle"
        let resourceBundle = [Bundle.main.resourceURL, Bundle.main.bundleURL]
            .compactMap { $0 }
            .map { $0.appending(path: resourceBundleName) }
            .compactMap { Bundle(url: $0) }
            .first
        guard let url = resourceBundle?.url(
            forResource: "account-switcher-logo",
            withExtension: "png"
        ), let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing account-switcher-logo.png")
        }
        image.size = logicalSize
        image.isTemplate = true
        return image
    }()

    var body: some View {
        Image(nsImage: Self.image)
            .frame(width: 17.5, height: 17.5)
            .accessibilityHidden(true)
    }
}

private struct QuitApplicationCommands: Commands {
    let title: String

    var body: some Commands {
        CommandGroup(replacing: .appTermination) {
            Button(title) {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
