import AppKit
import Testing
@testable import CodexAccountSwitcher

struct PopoverWindowSizerTests {
    @Test @MainActor func shrinksAndGrowsWithoutMovingMenuAnchor() {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let top = window.frame.maxY
        let center = window.frame.midX
        for size in [CGSize(width: 326, height: 180), CGSize(width: 326, height: 500),
                     CGSize(width: 280, height: 120)] {
            PopoverWindowSizer.resize(window, to: size)
            #expect(window.contentView?.bounds.size == size)
            #expect(window.frame.maxY == top)
            #expect(window.frame.midX == center)
        }
        let frame = window.frame
        PopoverWindowSizer.resize(window, to: .zero)
        #expect(window.frame == frame)
    }
}
