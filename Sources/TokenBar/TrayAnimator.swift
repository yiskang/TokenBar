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

    private weak var controller: StatusItemController?
    /// Frame sets keyed by "<style>|<dark|light>".
    private let frames: [String: [NSImage]]
    private var animationTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    /// RunCat load signal in [0, 100]: tokens/min ÷ 10K, so 1M tok/min = 100.
    private var load: Double = 0

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
    }

    func stop() {
        animationTask?.cancel()
        loadTask?.cancel()
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
                let set = self.currentFrames()
                let style = UserDefaults.standard.string(forKey: Self.styleKey) ?? "cat"
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
