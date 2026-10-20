import AppKit
import SwiftUI

/// Keep the menu window fitted to its current page, including when that page shrinks.
struct PopoverWindowSizer: NSViewRepresentable {
    let contentSize: CGSize

    func makeNSView(context: Context) -> SizingView { SizingView() }

    func updateNSView(_ view: SizingView, context: Context) {
        view.contentSize = contentSize
        view.scheduleResize()
    }

    final class SizingView: NSView {
        var contentSize: CGSize = .zero

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleResize()
        }

        func scheduleResize() {
            // Resize after SwiftUI finishes layout, using the latest measurement.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                PopoverWindowSizer.resize(window, to: self.contentSize)
            }
        }
    }

    static func resize(_ window: NSWindow, to contentSize: CGSize) {
        guard contentSize.width.isFinite, contentSize.height.isFinite,
              contentSize.width > 0, contentSize.height > 0 else { return }
        let oldFrame = window.frame
        let size = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        guard abs(oldFrame.width - size.width) > 0.5 ||
              abs(oldFrame.height - size.height) > 0.5 else { return }
        // Keep the popup's top edge and horizontal center anchored to its menu item.
        window.setFrame(NSRect(x: oldFrame.midX - size.width / 2,
                               y: oldFrame.maxY - size.height,
                               width: size.width, height: size.height), display: true)
    }
}
