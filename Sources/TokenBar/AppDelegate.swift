import AppKit
import TokenBarCore

/// App bootstrap: accessory activation policy (menu-bar only, no Dock icon),
/// the status-item controller, and the 60s tray-title refresh loop.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let titleRefreshSecs: UInt64 = 60

    private var statusController: StatusItemController?
    private var trayAnimator: TrayAnimator?
    private var titleRefreshTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = StatusItemController()
        statusController = controller
        let animator = TrayAnimator(controller: controller)
        trayAnimator = animator
        animator.start()
        startTitleRefresh()

        // Debug hook: `swift run TokenBar --open-popover` shows the popover
        // shortly after launch so it can be screenshotted without a click.
        if CommandLine.arguments.contains("--open-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                controller.showPopover()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        titleRefreshTask?.cancel()
        trayAnimator?.stop()
    }

    /// Refreshes the tray title every 60s in the user's chosen mode. Reads
    /// usually hit the <=30s staticlib cache; a full log re-read
    /// (tb_refresh_graph) is forced every "Data refresh" interval from
    /// settings. Tray animation joins in a later phase.
    private func startTitleRefresh() {
        titleRefreshTask = Task { [weak self] in
            var lastFullRefresh = Date.distantPast
            while !Task.isCancelled {
                let mode = TrayMode.current
                let intervalMin = max(1, UserDefaults.standard.object(forKey: "tokenbar.refresh.intervalMin")
                    .flatMap { $0 as? Int } ?? 30)
                let forceRefresh = Date().timeIntervalSince(lastFullRefresh) >= Double(intervalMin) * 60
                let graph = try? await Task.detached(priority: .utility) {
                    forceRefresh ? try TBCore.refreshGraph() : try TBCore.graph()
                }.value
                if forceRefresh && graph != nil { lastFullRefresh = Date() }
                let rate: Double? = mode == .tokensPerMin
                    ? try? await Task.detached(priority: .utility) {
                        try TBCore.tokensPerMin()
                    }.value
                    : nil
                guard !Task.isCancelled else { break }
                self?.statusController?.updateTitle(
                    mode.title(graph: graph, tokensPerMin: rate))
                try? await Task.sleep(for: .seconds(Double(Self.titleRefreshSecs)))
            }
        }
    }
}
