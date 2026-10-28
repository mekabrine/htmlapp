import SwiftUI

struct ForgeStarterPicker: View {
    let choose: (ForgeStarterApp, Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Start with something useful").font(.headline)
            Text("Try a working app instantly, or edit an idea before generating your own.")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(ForgeStarterApp.all) { starter in
                VStack(alignment: .leading, spacing: 8) {
                    Label(starter.title, systemImage: starter.symbol).font(.headline)
                    Text(starter.detail).font(.subheadline).foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack { starterButtons(starter) }
                        VStack(alignment: .leading) { starterButtons(starter) }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder private func starterButtons(_ starter: ForgeStarterApp) -> some View {
        Button("Try without AI") { choose(starter, true) }.buttonStyle(.borderedProminent)
        Button("Use editable idea") { choose(starter, false) }.buttonStyle(.bordered)
    }
}

struct ForgeStageStrip: View {
    let phase: String
    let working: Bool
    let hasHTML: Bool
    let failed: Bool
    var body: some View {
        let stage = ForgeBuildStage.current(phase: phase, working: working, hasHTML: hasHTML, failed: failed)
        HStack(spacing: 5) {
            ForEach(ForgeBuildStage.allCases, id: \.rawValue) { item in
                Text(item.title)
                    .font(.caption.weight(item == stage ? .bold : .regular))
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(item == stage ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08), in: Capsule())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(failed ? "Build paused. Review the error and retry." : "Build stage: \(stage.title)")
    }
}

struct HTMLAppVersionComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    let before: String
    let after: String
    var beforeTitle = "Before"
    var afterTitle = "After"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @State private var selected = 1
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Version", selection: $selected) {
                    Text(beforeTitle).tag(0)
                    Text(afterTitle).tag(1)
                }.pickerStyle(.segmented).padding(.horizontal)
                Text("Isolated preview: saved data and native permissions are unavailable. Trying a version does not change your saved app.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                HTMLWebView(html: HTMLAppTrialDocument.prepare(selected == 0 ? before : after), appID: "PREVIEW")
                    .id(selected)
                if let actionTitle, let action {
                    Button(actionTitle) { action(); dismiss() }
                        .buttonStyle(.borderedProminent).padding(.bottom)
                }
            }
            .navigationTitle("Compare Versions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
