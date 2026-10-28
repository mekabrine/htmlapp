import SwiftUI

struct HTMLAppEditHistoryView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let app: SavedHTMLApp
    @State private var comparison: AppStore.AIEditCheckpoint?
    @State private var restoring = false

    private var current: SavedHTMLApp { store.apps.first(where: { $0.id == app.id }) ?? app }
    var body: some View {
        NavigationStack {
            List {
                let history = store.editHistory(for: app)
                Section {
                    Text("Restoring changes the app's code and description. Your saved entries stay in place. The current code is kept as another checkpoint.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let latest = history.last {
                        Button { comparison = latest } label: {
                            Label("Undo Last AI Edit…", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
                if history.isEmpty {
                    Text("No AI edit checkpoints yet. Earlier versions appear after you save an AI edit.")
                        .foregroundStyle(.secondary)
                }
                Section("Saved Versions") {
                    ForEach(history.reversed()) { checkpoint in
                        Button { comparison = checkpoint } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(checkpoint.note).font(.headline).foregroundStyle(.primary)
                                Text(checkpoint.created.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                                Label("Preview and compare", systemImage: "rectangle.on.rectangle")
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }
            .disabled(restoring)
            .overlay { if restoring { ProgressView("Restoring version…") } }
            .sheet(item: $comparison) { checkpoint in
                HTMLAppVersionComparisonView(before: current.html, after: checkpoint.html,
                    beforeTitle: "Current", afterTitle: "Earlier",
                    actionTitle: "Restore This Version") {
                    restoring = true
                    Task {
                        store.errorMessage = nil
                        await store.restoreAIEdit(current, checkpointID: checkpoint.id)
                        restoring = false
                        if store.errorMessage == nil { dismiss() }
                    }
                }
            }
            .navigationTitle("AI Edit History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Couldn’t restore this version", isPresented: Binding(
                get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
            )) { Button("OK") { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
        }
    }
}

struct HTMLAppQuickAccess: View {
    let apps: [SavedHTMLApp]
    let open: (SavedHTMLApp) -> Void
    let edit: (SavedHTMLApp) -> Void
    let favorite: (SavedHTMLApp) -> Void

    private var pinned: [SavedHTMLApp] { Array(apps.filter { $0.isFavorite == true }.prefix(4)) }
    private var recent: [SavedHTMLApp] {
        Array(apps.filter { app in app.lastOpenedAt != nil && !pinned.contains(where: { $0.id == app.id }) }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }.prefix(4))
    }
    var body: some View {
        if !pinned.isEmpty || !recent.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("Quick Access").font(.headline).padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(pinned + recent) { app in
                            Button { open(app) } label: {
                                VStack(spacing: 5) {
                                    AppIconView(app: app, size: 44)
                                    Text(app.name).font(.caption).lineLimit(2).frame(width: 88)
                                    Label(app.isFavorite == true ? "Favorite" : "Recent",
                                          systemImage: app.isFavorite == true ? "star.fill" : "clock")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }.padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open \(app.name), \(app.isFavorite == true ? "favorite" : "recently used")")
                            .contextMenu {
                                Button { open(app) } label: { Label("Open", systemImage: "play") }
                                Button { edit(app) } label: { Label("Edit with AI", systemImage: "sparkles") }
                                Button { favorite(app) } label: {
                                    Label(app.isFavorite == true ? "Remove Favorite" : "Favorite", systemImage: "star")
                                }
                            }
                        }
                    }.padding(.horizontal, 16)
                }
            }.padding(.top, 8)
        }
    }
}
