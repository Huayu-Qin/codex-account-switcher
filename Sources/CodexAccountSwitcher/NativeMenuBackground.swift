import AppKit
import SwiftUI

/// Use the system menu material so the tint follows the desktop and appearance.
struct NativeMenuBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = MenuMaterialView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    private final class MenuMaterialView: NSVisualEffectView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Let the system material provide the surface instead of an opaque fill.
            window?.isOpaque = false
            window?.backgroundColor = .clear
        }
    }
}
