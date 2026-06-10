import AppKit
import SwiftUI

/// Owns the NSStatusItem and its NSPopover (AppKit-hosted icon, SwiftUI
/// popover content — the codexbar pattern). Later phases talk to it through
/// `updateTitle(_:)` and `showPopover()`.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 480)
        let host = NSHostingController(rootView: PopoverView())
        // The SwiftUI root has a fixed frame; let the popover keep our size
        // instead of chasing intrinsic-size updates.
        host.sizingOptions = []
        popover.contentViewController = host

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "chart.bar.fill",
                accessibilityDescription: "TokenBar")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeft
            button.toolTip = "TokenBar"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
    }

    /// Swaps the menu-bar icon image (an animation frame).
    func setFrame(_ image: NSImage) {
        statusItem.button?.image = image
    }

    /// Whether the menu bar around the item renders dark (picks the white
    /// frame set over the black one). Status-item buttons report *vibrant*
    /// appearances (NSAppearanceNameVibrantDark), which bestMatch against
    /// [.darkAqua, .aqua] misses — match on the name instead.
    var isDarkAppearance: Bool {
        let appearance = statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        return appearance.name.rawValue.localizedCaseInsensitiveContains("dark")
    }

    /// Sets the text shown next to the menu-bar icon ("" = icon only).
    func updateTitle(_ title: String) {
        guard let button = statusItem.button else { return }
        // Leading space keeps a gap between the template icon and the text.
        let value = title.isEmpty ? "" : " \(title)"
        if button.title != value {
            button.title = value
        }
        button.imagePosition = value.isEmpty ? .imageOnly : .imageLeft
    }

    func showPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
        // Accessory apps are never frontmost; activate so the transient
        // popover gets key status and closes on outside clicks.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func closePopover() {
        popover.performClose(nil)
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }
}
