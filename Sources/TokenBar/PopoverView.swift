import AppKit
import SwiftUI
import TokenBarCore

/// Popover root: view-switch row + lens router over a shared DashboardModel.
/// Per-client tabs join in a later phase.
struct PopoverView: View {
    @State private var model = DashboardModel()
    @State private var tokensPerMin: Double?
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
            if let stats = model.stats, stats.presentClients.count > 1 {
                DashboardTabs(clients: stats.presentClients, active: $activeTab)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            ViewSwitch(active: activeView)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            Divider()
            ScrollView {
                content
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
            Text(activeView.wrappedValue.label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
