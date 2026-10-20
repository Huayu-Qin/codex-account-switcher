import SwitcherCore
import AppKit
import SwiftUI

@main
struct SwitcherApp: App {
    @NSApplicationDelegateAdaptor(SwitcherAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            NativeAccountMenu(model: appDelegate.model, updater: appDelegate.updater,
                              onManage: appDelegate.showAccounts, onSettings: appDelegate.showSettings)
        } label: {
            MenuBarStatusLabel(model: appDelegate.model, updater: appDelegate.updater)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            QuitApplicationCommands(model: appDelegate.model)
        }

    }
}

private struct MenuBarStatusLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdater

    var body: some View {
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
    }

    // MenuBarExtra extracts a single text title from its label.
    private var menuBarTitle: String {
        var parts: [String] = []
        if let name = model.activeAccountName { parts.append(name) }
        if model.settings.showsMenuBarPercentage {
            parts.append(model.activeRemainingPercent.map { "\($0)%" } ?? "—%")
        }
        return parts.joined(separator: "  ")
    }

    private var menuBarAccessibilityLabel: String {
        let updateStatus = updater.availableVersion.map { ", " + model.format("update_available", $0) } ?? ""
        guard model.settings.showsMenuBarPercentage,
              let remainingPercent = model.activeRemainingPercent
        else {
            return "Codex Account Switcher" + updateStatus
        }
        return "Codex Account Switcher, \(remainingPercent)%" + updateStatus
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
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appTermination) {
            Button(model.text("quit")) {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
