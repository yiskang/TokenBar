import AppKit
import SwiftUI
import TokenBarCore

/// Popover root: view-switch row + lens router over a shared DashboardModel.
/// Per-client tabs join in a later phase.
struct PopoverView: View {
    /// Set by the status-item controller from the screen size.
    var popoverHeight: CGFloat = 480

    @State private var model = DashboardModel()
    @State private var tokensPerMin: Double?
    /// `--settings` opens straight onto the settings panel (debug/screenshot aid).
    @State private var showSettings = CommandLine.arguments.contains("--settings")
    /// True while Cmd has been held alone for a beat — shows shortcut pins.
    @State private var cmdHeld = false
    @State private var keyMonitor: Any?
    @State private var flagsMonitor: Any?
    @State private var cmdHintTask: Task<Void, Never>?
    @AppStorage("tokenbar.chart.view") private var chartViewRaw = "2d"
    @AppStorage("tokenbar.view") private var activeViewRaw = AppView.overview.rawValue
    @AppStorage("tokenbar.bridge.dismissed") private var bridgeDismissed = false
    /// "overview" or a client id. Not persisted, matching the Tauri app.
    /// `--tab=<id>` preselects a client tab (debug/screenshot aid).
    @State private var activeTab =
        CommandLine.arguments
            .first(where: { $0.hasPrefix("--tab=") })
            .map { String($0.dropFirst("--tab=".count)) } ?? "overview"

    private var activeView: Binding<AppView> {
        Binding(
            get: { AppView(rawValue: activeViewRaw) ?? .overview },
            set: { activeViewRaw = $0.rawValue })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if BridgeBuild.isActive && !bridgeDismissed {
                bridgeBanner
            }
            if !showSettings {
                if let stats = model.stats, stats.presentClients.count > 1 {
                    DashboardTabs(
                        clients: stats.presentClients, active: $activeTab,
                        kbdHints: cmdHeld)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                ViewSwitch(active: activeView)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            Divider()
            ScrollView {
                Group {
                    if showSettings {
                        SettingsPanel(agentUsage: model.agentUsage)
                            // Navigation-push feel: settings slide in from
                            // the right while the dashboard yields left.
                            .transition(
                                .move(edge: .trailing).combined(with: .opacity))
                    } else {
                        content
                            .transition(
                                .move(edge: .leading).combined(with: .opacity))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OverlayScrollerEnforcer())
            }
            .clipped()
            Divider()
            footer
        }
        .frame(width: 360, height: popoverHeight)
        .animation(.easeInOut(duration: 0.22), value: showSettings)
        .animation(.easeOut(duration: 0.16), value: activeViewRaw)
        .animation(.easeOut(duration: 0.16), value: activeTab)
        .background(PopoverBackdrop().ignoresSafeArea())
        .task { await model.load() }
        .task(id: activeViewRaw) {
            await model.ensureData(for: activeView.wrappedValue)
        }
        .task { await pollTokensPerMin() }
        .task { await model.pollAgentUsage() }
        .task { await model.pollTrace() }
        .onAppear { installKeyMonitors() }
        .onDisappear { removeKeyMonitors() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            BrandMark()
                .frame(width: 19, height: 19)
            Text("TokenBar")
                .font(.headline)
            Spacer()
            liveRateBadge
            if !showSettings {
                yearMenu
            }
            refreshButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Year filter for every lens — the Tauri HeaderBar's year select. "All"
    /// (nil) is the native default; concrete years come from the payloads
    /// seen so far.
    @ViewBuilder private var yearMenu: some View {
        if !model.knownYears.isEmpty {
            Menu {
                Picker("Year", selection: Binding(
                    get: { model.year ?? "" },
                    set: { value in
                        Task { await model.setYear(value.isEmpty ? nil : value) }
                    }
                )) {
                    Text("All years").tag("")
                    ForEach(model.knownYears, id: \.self) { year in
                        Text(year).tag(year)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text(model.year ?? "All")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .help("Filter usage by year")
        }
    }

    /// Shown only on the final beta build (1.0 on the .beta id): one tap runs
    /// the cask install that graduates this install to the release app.
    private var bridgeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.forward.app.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("You're on the beta build")
                    .font(.caption.weight(.semibold))
                Text("Switch to the TokenBar 1.0 release — keeps your data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Switch") { BridgeBuild.switchToRelease() }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            Button {
                bridgeDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06))
    }

    /// Manual refresh (also ⌘R): forces a full log re-read.
    private var refreshButton: some View {
        Button {
            Task { await model.refresh() }
        } label: {
            if model.refreshing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.refreshing)
        .help("Refresh usage data (⌘R)")
    }

    private var liveRateBadge: some View {
        HStack(spacing: 4) {
            activityLED
            Text(tokensPerMin.map { "\(Format.compactTokens(Int64($0.rounded()))) tok/min" } ?? "— tok/min")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// Network-LED behavior: steady dim gray when idle, and when tokens are
    /// flowing, a green light that flickers irregularly like a router's
    /// activity light — mostly lit, with brief pseudo-random off-blinks
    /// (hash of the 90ms time slot, denser at higher rates).
    @ViewBuilder private var activityLED: some View {
        let rate = tokensPerMin ?? 0
        if rate > 0 {
            TimelineView(.periodic(from: .now, by: 0.09)) { timeline in
                let slot = UInt64(timeline.date.timeIntervalSinceReferenceDate / 0.09)
                let hash = (slot &* 0x9E37_79B9_7F4A_7C15) >> 33
                // Blink-off chance grows with the rate: ~25% near idle,
                // ~45% at 1M tok/min — busier traffic, busier light.
                let offChance = 25 + min(20, Int(rate / 50_000))
                let lit = Int(hash % 100) >= offChance
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .opacity(lit ? 1 : 0.25)
                    .shadow(color: .green.opacity(lit ? 0.8 : 0), radius: 2)
            }
        } else {
            Circle()
                .fill(.secondary.opacity(0.4))
                .frame(width: 6, height: 6)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading usage…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        case .ready:
            lens
        }
    }

    /// Lens router. The client tab picks *which* data (clientIds slice), the
    /// view switch picks *how* it is broken down; the two compose. Switching
    /// either crossfades with a subtle scale (id swap drives the transition).
    @ViewBuilder private var lens: some View {
        lensContent
            .id("\(activeTab)|\(activeViewRaw)")
            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
    }

    @ViewBuilder private var lensContent: some View {
        if let payload = model.payload, let stats = model.stats {
            let singleClient = activeTab == "overview" ? nil : activeTab
            let clientIds = singleClient.map { [$0] } ?? stats.presentClients
            let activeStats = singleClient == nil
                ? stats
                : UsageStats(payload: payload, selectedClients: Set(clientIds))
            switch activeView.wrappedValue {
            case .overview:
                OverviewView(
                    payload: payload, clientIds: clientIds, stats: activeStats,
                    modelReport: model.modelReport, colors: model.colors,
                    trace: model.trace, agentUsage: model.agentUsage,
                    singleClient: singleClient, year: model.year)
            case .models:
                ModelsView(
                    report: model.modelReport, clientIds: clientIds, colors: model.colors)
            case .daily:
                DailyView(payload: payload, clientIds: clientIds, colors: model.colors)
            case .hourly:
                HourlyView(
                    report: model.hourly, clientIds: clientIds,
                    filtered: singleClient != nil)
            case .stats:
                StatsView(
                    payload: payload, clientIds: clientIds, stats: activeStats,
                    modelReport: model.modelReport, colors: model.colors,
                    year: model.year)
            case .agents:
                AgentsView(report: model.agents, clientIds: clientIds)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(showSettings ? "Settings" : activeView.wrappedValue.label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            if let version = UpdaterService.shared.availableVersion {
                Button {
                    UpdaterService.shared.checkForUpdates()
                } label: {
                    Label("Update \(version)", systemImage: "arrow.down.circle.fill")
                        .font(.caption.weight(.medium))
                }
                .controlSize(.small)
                .tint(.accentColor)
                .help("A new version is ready — click to install")
            }
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: showSettings ? "chevron.backward" : "gearshape")
            }
            .controlSize(.small)
            .help(showSettings ? "Back to dashboard" : "Settings")
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Keyboard shortcuts

    /// The web app's Cmd shortcuts (App.tsx onKeyDown), as local NSEvent
    /// monitors scoped to the popover's key window: ⌘1-9 tabs, ⌘[/⌘] cycle,
    /// ⌘, settings, ⌘R refresh, ⌘G 2D/3D, ⌘W/Esc close, ⌘Q quit. Holding Cmd
    /// alone for 400ms reveals the tab pins (system chords like ⌘⇧4 don't).
    private func installKeyMonitors() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event) ? nil : event
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handleFlagsChanged(event)
            return event
        }
    }

    private func removeKeyMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        keyMonitor = nil
        flagsMonitor = nil
        cmdHintTask?.cancel()
        cmdHeld = false
    }

    /// Returns true when the event was consumed.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Esc: settings page first, else the popover
            if showSettings {
                showSettings = false
            } else {
                event.window?.performClose(nil)
            }
            return true
        }
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard mods == .command, let chars = event.charactersIgnoringModifiers?.lowercased()
        else { return false }

        let tabs = ["overview"] + (model.stats?.presentClients ?? [])
        switch chars {
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            let index = Int(chars)! - 1
            guard index < tabs.count else { return true }
            activeTab = tabs[index]
            showSettings = false
        case "[", "]":
            let current = tabs.firstIndex(of: activeTab) ?? 0
            let step = chars == "]" ? 1 : tabs.count - 1
            activeTab = tabs[(current + step) % tabs.count]
            showSettings = false
        case ",":
            showSettings = true
        case "w":
            if showSettings {
                showSettings = false
            } else {
                event.window?.performClose(nil)
            }
        case "q":
            NSApp.terminate(nil)
        case "r":
            Task { await model.refresh() }
        case "g":
            chartViewRaw = chartViewRaw == "2d" ? "3d" : "2d"
        default:
            return false
        }
        return true
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if mods == .command {
            guard cmdHintTask == nil, !cmdHeld else { return }
            cmdHintTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                if !Task.isCancelled { cmdHeld = true }
                cmdHintTask = nil
            }
        } else {
            cmdHintTask?.cancel()
            cmdHintTask = nil
            cmdHeld = false
        }
    }

    // MARK: - Live rate

    /// Poll the live rate every 10s while the popover content is on screen;
    /// `.task` cancels this loop when the popover closes.
    private func pollTokensPerMin() async {
        while !Task.isCancelled {
            let rate = try? await Task.detached(priority: .utility) {
                try TBCore.tokensPerMin()
            }.value
            if Task.isCancelled { break }
            tokensPerMin = rate
            try? await Task.sleep(for: .seconds(10))
        }
    }
}
