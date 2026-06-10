import SwiftUI
import TokenBarCore

/// In-popover settings, port of SettingsPanel.tsx. Every control binds the
/// same UserDefaults keys the cards/tray read live. Autostart, tray animation
/// and the updater arrive with their subsystems in later phases.
struct SettingsPanel: View {
    @AppStorage(TrayMode.storageKey) private var trayModeRaw = TrayMode.todayTokens.rawValue
    @AppStorage(TrayAnimator.animateKey) private var animateTray = true
    @AppStorage(TrayAnimator.styleKey) private var animationStyle = "cat"
    @AppStorage("tokenbar.limits.asUsed") private var limitsAsUsed = false
    @AppStorage("tokenbar.limits.paceMode") private var paceModeRaw = PaceMode.historical.rawValue
    @AppStorage("tokenbar.limits.layout") private var layoutRaw = LimitsLayout.full.rawValue
    @AppStorage("tokenbar.trace.detailed") private var detailedTrace = false
    @AppStorage("tokenbar.refresh.intervalMin") private var refreshIntervalMin = 30

    static let refreshIntervalOptions = [1, 5, 15, 30, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Menubar title") {
                radioGroup(
                    selection: $trayModeRaw,
                    options: TrayMode.allCases.map { ($0.rawValue, $0.label) })
            }

            section("Menubar icon") {
                toggleRow("Animate based on token usage", isOn: $animateTray)
                if animateTray {
                    radioGroup(
                        selection: $animationStyle,
                        options: [("cat", "Spinning cat"), ("parrot", "Party parrot")])
                }
                hint("The icon spins faster as the live token rate climbs (idle 2 fps, 1M tokens/min tops out at 40 fps). Dark/light frames follow the menu bar appearance.")
            }

            section("Agent limits") {
                toggleRow("Show as used", isOn: $limitsAsUsed)
                hint("On, bars count up as quota is used; off, they count down to what's left. The color always warns as quota runs low.")
                radioGroup(
                    selection: $layoutRaw,
                    options: LimitsLayout.allCases.map { ($0.rawValue, "Layout: \($0.rawValue.capitalized)") })
                hint("Full is the wide card with the pace line; Classic is the original compact layout without pace.")
                if LimitsLayout(rawValue: layoutRaw) != .classic {
                    radioGroup(
                        selection: $paceModeRaw,
                        options: PaceMode.allCases.map { ($0.rawValue, "Pace: \($0.rawValue.capitalized)") })
                    hint("The deficit/reserve marker. Historical learns your weekly usage curve and shows run-out risk, falling back to linear until enough weeks accrue; Linear paces evenly by the clock; Off hides the marker.")
                }
            }

            section("Live trace") {
                toggleRow("Split by agent / model", isOn: $detailedTrace)
                hint("Affects the live-session card only: on, each agent & model gets its own row; off, rows collapse to one per app.")
            }

            section("Data refresh") {
                radioGroup(
                    selection: Binding(
                        get: { String(refreshIntervalMin) },
                        set: { refreshIntervalMin = Int($0) ?? 30 }),
                    options: Self.refreshIntervalOptions.map {
                        (String($0), $0 == 60 ? "Every hour" : "Every \($0) min")
                    })
                hint("How often the tray re-reads your logs. The dashboard refreshes when the popover opens; live tokens/min updates every few seconds regardless.")
            }

            section("About") {
                row("Version") {
                    Text(AppInfo.version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                hint("TokenBar began as a fork of tokcat by handlecusion. Parsing & pricing come from tokscale by Junho Yeo; the menu-bar patterns reference CodexBar by Peter Steinberger. MIT licensed.")
            }
        }
    }

    // MARK: - Building blocks

    private func section(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            content()
        }
    }

    private func row(_ label: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        row(label) {
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }

    private func radioGroup(
        selection: Binding<String>, options: [(value: String, label: String)]
    ) -> some View {
        VStack(spacing: 1) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection.wrappedValue = option.value
                } label: {
                    HStack {
                        Text(option.label)
                            .font(.caption)
                        Spacer()
                        if selection.wrappedValue == option.value {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Build/version info. The bare SwiftPM executable has no bundle, so the
/// version is a constant until Phase 9 wraps it in a .app with an Info.plist.
enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
