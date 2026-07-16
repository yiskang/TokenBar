import SwiftUI

/// The seven-lens tab row under the header, port of ViewSwitch.tsx.
struct ViewSwitch: View {
    @Binding var active: AppView

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppView.allCases, id: \.self) { view in
                Button(view.label) { active = view }
                    .buttonStyle(.plain)
                    .font(.caption.weight(active == view ? .semibold : .regular))
                    .foregroundStyle(active == view ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(
                        active == view ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(2)
        .glassCard(cornerRadius: 8)
    }
}
