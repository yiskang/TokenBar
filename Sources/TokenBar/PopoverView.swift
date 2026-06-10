import AppKit
import SwiftUI
import TokenBarCore

/// Phase 3 placeholder dashboard: proves graph + live-rate data flow through
/// the FFI into SwiftUI. The real dashboard lenses arrive in later phases.
struct PopoverView: View {
    private enum GraphState {
        case loading
        case loaded(UsagePayload)
        case failed(String)
    }

    @State private var graphState: GraphState = .loading
    @State private var tokensPerMin: Double?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                content
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 360, height: 480)
        .background(GlassBackground().ignoresSafeArea())
        .task { await loadGraph() }
        .task { await pollTokensPerMin() }
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
        switch graphState {
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
        case let .loaded(graph):
            stats(for: graph)
        }
    }

    private func stats(for graph: UsagePayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            statRow("Total tokens", Format.compactTokens(graph.summary.totalTokens))
            statRow("Total cost", Format.usd(graph.summary.totalCost))
            statRow("Active days", "\(graph.summary.activeDays)")
            statRow("Top client", topClient(of: graph) ?? "—")
            statRow("Today", Format.compactTokens(Format.todayTokens(in: graph)))
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            Text("Phase 3 shell")
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

    // MARK: - Data

    /// Client with the highest all-time token total (summary.clients is
    /// unordered, so aggregate from the daily breakdowns).
    private func topClient(of graph: UsagePayload) -> String? {
        var totals: [String: Int64] = [:]
        for day in graph.contributions {
            for client in day.clients {
                let tokens = client.tokens.input + client.tokens.output
                    + client.tokens.cacheRead + client.tokens.cacheWrite
                    + client.tokens.reasoning
                totals[client.client, default: 0] += tokens
            }
        }
        return totals.max(by: { $0.value < $1.value })?.key
    }

    /// TBCore is blocking — hop off the main actor for the FFI call.
    private func loadGraph() async {
        do {
            let graph = try await Task.detached(priority: .userInitiated) {
                try TBCore.graph()
            }.value
            graphState = .loaded(graph)
        } catch {
            graphState = .failed("Failed to load usage: \(error)")
        }
    }

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
