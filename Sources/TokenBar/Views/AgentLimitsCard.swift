import SwiftUI
import TokenBarCore

/// OAuth quota cards per agent: usage-window bars with gauge colors, reset
/// text and a pace marker. Port of AgentLimitsCard.tsx (basic version —
/// pace-mode/layout settings, drag reorder and the opencode subscription view
/// arrive in a later phase).
struct AgentLimitsCard: View {
    /// Clients requested by the active tab.
    let clients: [String]
    let trace: [TraceBucket]
    let agentUsage: AgentUsagePayload?
    var title = "Agent limits"
    var note = "OAuth quota"
    /// When true, show only the passed `clients` (single-client view) instead
    /// of unioning in every agent that has a quota snapshot.
    var restrict = false

    /// Placeholder window labels for agents we know carry quotas but have no
    /// snapshot yet (LIMIT_ROWS in the web card).
    private static let placeholderRows: [String: [String]] = [
        "codex": ["Session", "Weekly"],
        "claude": ["Session", "Weekly"],
        "gemini": ["Pro", "Flash"],
    ]

    private var snapshots: [String: AgentUsageSnapshot] {
        Dictionary(
            (agentUsage?.agents ?? []).map { ($0.clientId, $0) },
            uniquingKeysWith: { first, _ in first })
    }

    /// Clients whose live tail shows activity right now.
    private var liveClients: Set<String> {
        Set(
            trace.filter { $0.tokensPerMin > 0 }
                .map { Self.normalizeTraceClient($0.client) })
    }

    private var visibleClients: [String] {
        let snapshots = self.snapshots
        func known(_ id: String) -> Bool {
            Self.placeholderRows[id] != nil || snapshots[id] != nil
        }
        if restrict { return clients.filter(known) }
        var seen = Set<String>()
        return (clients.filter(known) + (agentUsage?.agents.map(\.clientId) ?? []))
            .filter { seen.insert($0).inserted }
    }

    var body: some View {
        DashCard(title, trailing: { noteLabel }) {
            let visible = visibleClients
            if visible.isEmpty {
                Text("No supported agents yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    ForEach(visible, id: \.self) { id in
                        agentSection(id)
                    }
                }
            }
        }
    }

    private var noteLabel: some View {
        Text(note)
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Per-agent section

    @ViewBuilder private func agentSection(_ id: String) -> some View {
        let style = ClientRegistry.style(id)
        let snapshot = snapshots[id]
        let isLive = liveClients.contains(id)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: style.color))
                    .frame(width: 14, height: 14)
                    .overlay(
                        Text(String(style.displayName.prefix(1)))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white))
                Text(style.displayName)
                    .font(.caption.weight(.semibold))
                Spacer()
                statusBadge(snapshot: snapshot, isLive: isLive)
            }
            if let detail = detailText(snapshot) {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(snapshot?.error != nil ? .red : .secondary)
                    .lineLimit(2)
                    .help(snapshot?.error ?? detail)
            }
            VStack(spacing: 8) {
                if let snapshot, !snapshot.windows.isEmpty {
                    ForEach(snapshot.windows, id: \.label) { window in
                        windowRow(window, brand: style.color)
                    }
                } else {
                    ForEach(Self.placeholderRows[id] ?? ["Limit"], id: \.self) { label in
                        placeholderRow(label, brand: style.color)
                    }
                }
            }
        }
    }

    private func statusBadge(snapshot: AgentUsageSnapshot?, isLive: Bool) -> some View {
        let text: String
        var color: Color = .secondary
        if snapshot?.error != nil {
            text = "Error"
            color = .red
        } else if let snapshot, !snapshot.windows.isEmpty {
            text = snapshot.source.uppercased()
        } else if isLive {
            text = "Live"
            color = .green
        } else {
            text = "No quota"
        }
        return Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
    }

    private func detailText(_ snapshot: AgentUsageSnapshot?) -> String? {
        guard let snapshot else { return nil }
        if let error = snapshot.error { return error }
        let parts = [snapshot.identity?.email, snapshot.identity?.plan].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Window rows

    /// A quota bar reads green when healthy, ambers under 25% left and reds
    /// under 10% (tokscale/codexbar Usage view). No quota signal → brand color.
    private func gaugeColor(remaining: Double?, brand: String) -> Color {
        guard let remaining else { return Color(hex: brand) }
        if remaining <= 10 { return Color(red: 0.937, green: 0.267, blue: 0.267) }
        if remaining <= 25 { return Color(red: 0.961, green: 0.620, blue: 0.043) }
        return Color(red: 0.133, green: 0.773, blue: 0.369)
    }

    @ViewBuilder private func windowRow(_ window: UsageWindow, brand: String) -> some View {
        let remaining = min(100, max(0, window.remainingPercent))
        let pace = UsagePace.compute(window: window, mode: .historical)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.label)
                    .font(.caption2.weight(.medium))
                Spacer()
                if let reset = window.resetText {
                    Text(reset)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            bar(
                fillPercent: remaining,
                color: gaugeColor(remaining: remaining, brand: brand),
                // The bar fills by remaining (counting down); the pace marker
                // sits on the same axis so it lines up with the fill.
                paceLeft: pace.map { min(100, max(0, 100 - $0.expectedUsedPercent)) },
                paceIsDeficit: pace?.stage.isDeficit ?? false)
            HStack {
                Text("\(Int(remaining.rounded()))% left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let pace {
                    let risk = runOutRiskLabel(window: window)
                    Text(
                        [pace.label, pace.etaText, risk]
                            .compactMap(\.self).joined(separator: " · ")
                    )
                    .font(.caption2)
                    .foregroundStyle(pace.stage.isDeficit ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                    .lineLimit(1)
                }
            }
        }
    }

    private func placeholderRow(_ label: String, brand: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption2.weight(.medium))
                Spacer()
            }
            bar(fillPercent: 0, color: Color(hex: brand), paceLeft: nil, paceIsDeficit: false)
            Text("No data")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func bar(
        fillPercent: Double, color: Color, paceLeft: Double?, paceIsDeficit: Bool
    ) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary.opacity(0.6))
                Capsule()
                    .fill(color.opacity(0.85))
                    .frame(width: geo.size.width * fillPercent / 100)
                if let paceLeft {
                    RoundedRectangle(cornerRadius: 0.75)
                        .fill(paceIsDeficit ? Color.orange : Color.secondary)
                        .frame(width: 1.5, height: geo.size.height + 4)
                        .offset(x: geo.size.width * paceLeft / 100 - 0.75)
                        .help("Expected \(Int((100 - paceLeft).rounded()))% used by now")
                }
            }
        }
        .frame(height: 6)
    }

    /// The live tail reports raw client ids; quota snapshots use short ids.
    static func normalizeTraceClient(_ id: String) -> String {
        switch id {
        case "claude-code": return "claude"
        case "codex-cli": return "codex"
        case "gemini-cli": return "gemini"
        default: return id.hasSuffix("-cli") ? String(id.dropLast(4)) : id
        }
    }
}
