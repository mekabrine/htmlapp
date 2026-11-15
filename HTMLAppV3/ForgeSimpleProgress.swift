import SwiftUI

struct ForgeSimpleProgress: View {
    let title: String
    let explanation: String
    let active: Bool
    let runs: [ForgeWorkRun]
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ForgeWorkRing(runs: runs, active: active)
                .frame(height: 205)
            VStack(spacing: 12) {
                Text(title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                Text(explanation).font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 520)
            .accessibilityElement(children: .combine)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}
