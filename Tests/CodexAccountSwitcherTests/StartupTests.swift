import AppKit
import Testing
@testable import CodexAccountSwitcher

@MainActor
struct StartupTests {
    @Test func manualLaunchShowsAccounts() {
        #expect(SwitcherAppDelegate.shouldShowAccountsOnLaunch(event: nil))
        #expect(SwitcherAppDelegate.shouldShowAccountsOnLaunch(event: openApplicationEvent()))
    }

    @Test func loginLaunchStaysInBackground() {
        let event = openApplicationEvent()
        event.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: keyAEPropData)
        #expect(!SwitcherAppDelegate.shouldShowAccountsOnLaunch(event: event))
    }

    private func openApplicationEvent() -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
                               targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
                               transactionID: AETransactionID(kAnyTransactionID))
    }
}
