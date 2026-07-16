import SwiftUI
import TokenBarCore

/// "Monthly" lens: one row per calendar month (most recent first) with
/// msgs / tokens / cost. Buckets by the FULL "YYYY-MM" prefix — not
/// month-of-year — so the shared year filter composes for free: a selected
/// year yields ≤12 rows, "All years" yields one row per calendar month with
/// no cross-year conflation. Selecting a month drills into the month's
/// per-model split, merged across its days (same "model|provider" key the
/// Daily drill-down uses) with saturating folds.
struct MonthlyView: View {
    let payload: UsagePayload
    /// Restrict to these clients (strict membership). Empty = show nothing —
    /// consistent with DailyView/DayBars/UsageStats — so an all-hidden slice
    /// can't leak the drill-down.
    var clientIds: [String] = []
    let colors: ModelColorMap

    @State private var openMonth: String?

    struct MonthRow {
        let month: String  // "YYYY-MM"
        var tokens: Int64
        var cost: Double
        var messages: Int
        var contributions: [Contribution]
    }

    struct ModelSlice {
        let key: String
        let model: String
        let provider: String
        let color: String
        var tokens: Int64
        var cost: Double
    }

    /// Pure bucketing, internal (not private) so SelfTest can pin it.
    static func monthRows(payload: UsagePayload, clientIds: [String]) -> [MonthRow] {
        let allow = Set(clientIds)
        var grouped: [String: MonthRow] = [:]
        for c in payload.contributions {
            var tokens: Int64 = 0
            var cost = 0.0
            var messages = 0
            for cc in c.clients {
                if !allow.contains(cc.client) { continue }
                tokens = tokens.saturatingAdding(cc.tokens.total)
                cost += cc.cost
                messages += cc.messages
            }
            guard tokens > 0 || cost > 0 else { continue }
            let month = String(c.date.prefix(7))
            var slot = grouped[month]
                ?? MonthRow(month: month, tokens: 0, cost: 0, messages: 0, contributions: [])
            slot.tokens = slot.tokens.saturatingAdding(tokens)
            slot.cost += cost
            slot.messages += messages
            slot.contributions.append(c)
            grouped[month] = slot
        }
        return grouped.values.sorted { $0.month > $1.month }
    }

    /// Drill-down: merge model slices across the month's days (Daily merges
    /// within ONE contribution; Monthly must fold ~31 of them).
    static func modelSlices(
        for row: MonthRow, clientIds: [String], colors: ModelColorMap
    ) -> [ModelSlice] {
        let allow = Set(clientIds)
        var grouped: [String: ModelSlice] = [:]
        for c in row.contributions {
            for cc in c.clients {
                if !allow.contains(cc.client) { continue }
                let tokens = cc.tokens.total
                if tokens <= 0 && cc.cost <= 0 { continue }
                let model = cc.modelId.isEmpty ? "unknown" : cc.modelId
                let key = "\(model)|\(cc.providerId)"
                var slot = grouped[key] ?? ModelSlice(
                    key: key, model: model, provider: cc.providerId,
                    color: colors.color(cc.providerId, model), tokens: 0, cost: 0)
                slot.tokens = slot.tokens.saturatingAdding(tokens)
                slot.cost += cc.cost
                grouped[key] = slot
            }
        }
        return grouped.values.sorted {
            $0.cost != $1.cost ? $0.cost > $1.cost : $0.tokens > $1.tokens
        }
    }

    var body: some View {
        // Placeholder until Task 3; keeps this task compiling as a View.
        EmptyView()
    }
}
