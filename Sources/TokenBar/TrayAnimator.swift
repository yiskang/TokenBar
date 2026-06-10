import AppKit
import TokenBarCore

/// RunCat-style menu-bar animation, port of src-tauri's animation.rs: the
/// cat (or parrot) spins faster as the live token rate climbs. Frame sets
/// come in dark/light pairs and follow the menu bar's effective appearance —
/// `anim-*` are white glyphs for a dark menu bar, `anim-*-light` black ones
/// for a light menu bar.
@MainActor
final class TrayAnimator {
    static let animateKey = "tokenbar.tray.animate"
    static let styleKey = "tokenbar.tray.animationStyle"

    static let quotaSourceKey = "tokenbar.quota.source"

    private weak var controller: StatusItemController?
    /// Frame sets keyed by "<style>|<dark|light>".
    private let frames: [String: [NSImage]]
    private var animationTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var quotaTask: Task<Void, Never>?
    /// RunCat load signal in [0, 100]: tokens/min ÷ 10K, so 1M tok/min = 100.
    private var load: Double = 0
    /// Latest OAuth quota snapshot — feeds the gauge icon styles and the
    /// quota title mode (AppDelegate reads it through `quotaRemaining`).
    private(set) var quota: AgentUsagePayload?

    init(controller: StatusItemController) {
        self.controller = controller
        var sets: [String: [NSImage]] = [:]
        for (style, dir) in [("cat", "anim-cat2"), ("parrot", "anim-parrot")] {
            sets["\(style)|dark"] = Self.loadFrames(directory: dir)
            sets["\(style)|light"] = Self.loadFrames(directory: "\(dir)-light")
        }
        frames = sets
    }

    /// PNG frames sorted by name (frame-00 … frame-NN), sized for the bar.
    private static func loadFrames(directory: String) -> [NSImage] {
        let urls = Bundle.module.urls(
            forResourcesWithExtension: "png", subdirectory: directory) ?? []
        return urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let image = NSImage(contentsOf: url) else { return nil }
                image.size = NSSize(width: 18, height: 18)
                return image
            }
    }

    func start() {
        startAnimationLoop()
        startLoadPolling()
        startQuotaPolling()
    }

    func stop() {
        animationTask?.cancel()
        loadTask?.cancel()
        quotaTask?.cancel()
    }

    /// Last successfully resolved remaining percent — a transient fetch
    /// failure (or a provider erroring) must never zero/blank the display.
    private var cachedQuotaRemaining: Double?

    /// The selected quota window's remaining percent, holding the last good
    /// value across failed refreshes (nil only before any data ever arrived).
    var quotaRemaining: Double? {
        let selection = UserDefaults.standard.string(forKey: Self.quotaSourceKey)
            ?? QuotaResolver.auto
        if let value = QuotaResolver.resolve(payload: quota, selection: selection)?
            .window.remainingPercent
        {
            cachedQuotaRemaining = value
            return value
        }
        return cachedQuotaRemaining
    }

    private func currentFrames() -> [NSImage] {
        let style = UserDefaults.standard.string(forKey: Self.styleKey) ?? "cat"
        let dark = controller?.isDarkAppearance ?? true
        return frames["\(style)|\(dark ? "dark" : "light")"]
            ?? frames["cat|dark"] ?? []
    }

    private var animateEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.animateKey) == nil
            || UserDefaults.standard.bool(forKey: Self.animateKey)
    }

    /// animation.rs: `speed = max(1, load/5)`, `interval = 500ms / speed` —
    /// idle 2 fps, full load 40 fps.
    private var frameInterval: Duration {
        .milliseconds(Int(500.0 / max(1.0, load / 5.0)))
    }

    private func startAnimationLoop() {
        animationTask = Task { [weak self] in
            var index = 0
            var lastKey = ""
            while !Task.isCancelled {
                guard let self else { break }
                let style = UserDefaults.standard.string(forKey: Self.styleKey) ?? "cat"
                // Gauge styles: redraw from the latest quota every couple of
                // seconds (cheap vector image; also tracks appearance flips).
                if let gaugeStyle = QuotaIconStyle(rawValue: style) {
                    let coloring = IconColoring(
                        rawValue: UserDefaults.standard.string(forKey: IconColoring.storageKey) ?? ""
                    ) ?? .warningOnly
                    self.controller?.setFrame(
                        TrayIcons.image(
                            style: gaugeStyle, remaining: self.quotaRemaining,
                            dark: self.controller?.isDarkAppearance ?? true,
                            coloring: coloring))
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }
                let set = self.currentFrames()
                if style != lastKey {
                    index = 0
                    lastKey = style
                }
                guard !set.isEmpty else {
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }
                if !self.animateEnabled {
                    index = 0
                    self.controller?.setFrame(set[0])
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }
                self.controller?.setFrame(set[index % set.count])
                index = (index + 1) % set.count
                try? await Task.sleep(for: self.frameInterval)
            }
        }
    }

    /// OAuth quota fetch is network-bound (~30s worst case across four
    /// providers), so refresh on a 5-minute cadence — quota windows move
    /// slowly and the popover has its own faster loop while open.
    private func startQuotaPolling() {
        quotaTask = Task { [weak self] in
            while !Task.isCancelled {
                let payload = try? await Task.detached(priority: .utility) {
                    try TBCore.agentUsage()
                }.value
                guard let self, !Task.isCancelled else { break }
                if let payload { self.quota = payload }
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    /// The staticlib's tail re-parses at most every 10s, so poll the live
    /// rate on that cadence to feed the spin speed.
    private func startLoadPolling() {
        loadTask = Task { [weak self] in
            while !Task.isCancelled {
                let rate = try? await Task.detached(priority: .utility) {
                    try TBCore.tokensPerMin()
                }.value
                guard let self, !Task.isCancelled else { break }
                if let rate { self.load = min(rate / 10_000.0, 100.0) }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }
}
