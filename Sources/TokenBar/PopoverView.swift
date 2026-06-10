import AppKit
import SwiftUI
import TokenBarCore

/// Popover root: view-switch row + lens router over a shared DashboardModel.
/// Per-client tabs join in a later phase.
struct PopoverView: View {
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
                    } else {
                        content
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 360, height: 480)
        .background(GlassBackground().ignoresSafeArea())
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
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.secondary)
            Text("TokenBar")
                .font(.headline)
            Spacer()
            liveRateBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var liveRateBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tokensPerMin.map { $0 > 0 ? Color.green : .secondary.opacity(0.4) } ?? .secondary.opacity(0.4))
                .frame(width: 6, height: 6)
            Text(tokensPerMin.map { "\(Format.compactTokens(Int64($0.rounded()))) tok/min" } ?? "— tok/min")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
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
    /// view switch picks *how* it is broken down; the two compose.
    @ViewBuilder private var lens: some View {
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
                    singleClient: singleClient)
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
                    modelReport: model.modelReport, colors: model.colors)
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
            Task { await model.load() }
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
