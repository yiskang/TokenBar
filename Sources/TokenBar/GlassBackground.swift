import AppKit
import SwiftUI

/// Reusable backdrop for popover/panel content. Uses Liquid Glass on
/// macOS 26+ and falls back to an `NSVisualEffectView` (.popover material,
/// behindWindow) on older systems. Apply with `.background(GlassBackground())`.
///
/// Layering note: NSPopover already draws its own vibrant chrome behind the
/// content view. We deliberately apply the material to the *content* (this
/// view) rather than trying to strip the popover's frame view — a clear glass
/// layer over the system chrome reads as one surface, while hacking the
/// popover's private background view is fragile across OS releases.
struct GlassBackground: View {
    var cornerRadius: CGFloat = 0

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            VisualEffectBackground(material: .popover)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

/// AppKit visual-effect bridge for the pre-26 fallback.
private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
