import AppKit
import SwiftUI
import SwitcherCore

/// Standard menu items allow macOS to own the material, spacing and selection.
struct NativeAccountMenu: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Codex Account Switcher")
        if !model.activeIdentityConfirmed {
            Text(model.text("active_unconfirmed"))
        }
        Divider()
        if model.accounts.isEmpty { Text(model.text("no_accounts")) }
        ForEach(model.accounts) { account in
            Toggle(isOn: Binding(
                get: { account.id == model.activeAccountID && model.activeIdentityConfirmed },
                set: { selected in if selected { confirmSwitch(account) } }
            )) {
                Text(verbatim: accountTitle(account))
            }
            .disabled(model.isMutating || updater.isInstalling)
        }
        Divider()
        Button(model.text("manage") + "…") { showWindow("accounts") }
            .keyboardShortcut("m", modifiers: .command)
            .disabled(model.isMutating || updater.isInstalling)
        Button(model.text("settings") + "…") { showWindow("settings") }
            .keyboardShortcut(",", modifiers: .command)
        if let error = model.visibleError {
            Divider()
            Button(model.text(error.titleKey) + "…") {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = model.text(error.titleKey)
                alert.informativeText = error.messageKey.map(model.text) ?? error.message
                alert.addButton(withTitle: model.text("ok"))
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
                model.dismissError()
            }
        }
        if let version = updater.availableVersion {
            Divider()
            Button(model.format("update_available", version) + "…") { updater.checkForUpdates() }
                .disabled(model.isMutating || model.isAddingAccount || updater.isInstalling)
        }
        Divider()
        Button(model.text("quit")) { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private func accountTitle(_ account: AccountProfile) -> String {
        var title = account.displayName
        if let usage = model.usageStates[account.id]?.displayedUsage {
            if model.settings.showsFiveHourUsage, let fiveHour = usage.fiveHourRemainingPercent {
                title += "   ·   5h \(fiveHour)% / 7d \(usage.remainingPercent)%"
            } else {
                title += "   ·   \(usage.remainingPercent)%"
            }
        }
        return title
    }

    private func showWindow(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func confirmSwitch(_ account: AccountProfile) {
        guard account.id != model.activeAccountID, !model.isMutating, !updater.isInstalling else { return }
        let alert = NSAlert()
        alert.messageText = model.format("switch_title", account.displayName)
        alert.informativeText = model.text("switch_body")
        alert.addButton(withTitle: model.text("switch"))
        alert.addButton(withTitle: model.text("cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await model.switchAccount(to: account.id) }
    }
}

struct AccountUtilityWindow: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdater
    let settings: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let error = model.visibleError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(model.text(error.titleKey), systemImage: "exclamationmark.triangle")
                        Text(error.messageKey.map(model.text) ?? error.message)
                            .foregroundStyle(.secondary)
                        Button(model.text("ok")) { model.dismissError() }
                    }
                    .padding()
                    Divider()
                }
                if settings {
                    SettingsView(model: model, updater: updater, showsHeader: false) { dismiss() }
                } else {
                    ManageAccountsView(model: model, showsHeader: false) { dismiss() }
                        .disabled(updater.isInstalling)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
