import SwiftUI

struct HTMLAppSyncConflict: Codable, Identifiable, Sendable {
    var id: String
    var name: String
    var receivedAt = Date()
    var cloudApp: SavedHTMLApp?
    var cloudData: [String: String]?
    var localSourceHash: String?
    var localDataHash: String?
}

struct HTMLAppSyncStatusView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.isSyncing {
                ProgressView("Checking iCloud…")
            } else {
                Label(store.syncStatus, systemImage: store.syncIssue == nil ? "icloud" : "exclamationmark.icloud")
                    .font(.subheadline)
            }
            if let date = store.lastSyncCheck {
                Text("Last completed check: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if store.syncPendingChanges { Text("Local changes are waiting to sync.").font(.caption) }
            if let issue = store.syncIssue {
                Text(issue).font(.caption).foregroundStyle(.secondary)
            }
            if !store.syncConflicts.isEmpty {
                NavigationLink("Review \(store.syncConflicts.count) sync change\(store.syncConflicts.count == 1 ? "" : "s")") {
                    HTMLAppSyncReviewView()
                }
            }
            Button("Check iCloud Now") { store.requestICloudSync() }
                .disabled(store.isSyncing || !HTMLAppICloudPreferences.enabled)
        }
    }
}

struct HTMLAppSyncReviewView: View {
    @EnvironmentObject private var store: AppStore
    @State private var preview: HTMLAppSyncConflict?
    @State private var selected: HTMLAppSyncConflict?
    @State private var useCloud = false
    @State private var resolving = false
    @State private var resolutionError: String?
    var body: some View {
        List {
            Section {
                Text("Both versions are kept until you choose. Before a replacement, HTMLApp saves a recovery backup of the local app and its portable data.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if store.syncConflicts.isEmpty { Text("No changes need review.") }
            ForEach(store.syncConflicts) { conflict in
                Section(conflict.name) {
                    if conflict.cloudApp != nil {
                        Button("Compare App Versions") { preview = conflict }
                    }
                    if let cloudData = conflict.cloudData {
                        let local = HTMLAppPortableDataStore.all(appID: conflict.id)
                        HTMLAppSyncDataComparison(local: local, cloud: cloudData)
                    }
                    Button("Keep This Device’s Version") { selected = conflict; useCloud = false }
                    Button("Use iCloud Version") { selected = conflict; useCloud = true }
                }
            }
            Section("Recovery") {
                if let url = store.latestSyncRecoveryURL {
                    Button("Export Latest Recovery Backup") { SharePresenter.present(items: [url]) }
                    Text("Import this backup from Backup & Transfer using Merge as New Copies to inspect earlier data without replacing your Library.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Recovery backups appear here after a sync replacement.").foregroundStyle(.secondary)
                }
            }
        }
        .disabled(resolving)
        .overlay { if resolving { ProgressView("Resolving sync change…") } }
        .navigationTitle("Review Sync Changes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $preview) { conflict in
            if let local = store.apps.first(where: { $0.id == conflict.id }), let cloud = conflict.cloudApp {
                HTMLAppVersionComparisonView(before: local.html, after: cloud.html,
                                             beforeTitle: "This Device", afterTitle: "iCloud")
            }
        }
        .confirmationDialog(useCloud ? "Use the iCloud version?" : "Keep this device’s version?",
                            isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), titleVisibility: .visible) {
            Button(useCloud ? "Use iCloud Version" : "Keep This Device’s Version") {
                guard let conflict = selected else { return }
                selected = nil
                resolving = true
                Task {
                    do { try await store.resolveSyncConflict(conflict, useCloud: useCloud) }
                    catch { resolutionError = error.localizedDescription }
                    resolving = false
                }
            }
            Button("Cancel", role: .cancel) { selected = nil }
        } message: {
            Text("This applies to the app code and saved data shown above. A local recovery backup is created first. The chosen version will be used for future syncs.")
        }
        .alert("Couldn’t resolve this change", isPresented: Binding(
            get: { resolutionError != nil }, set: { if !$0 { resolutionError = nil } }
        )) { Button("OK") { resolutionError = nil } } message: { Text(resolutionError ?? "") }
    }
}

private struct HTMLAppSyncDataComparison: View {
    let local: [String: String]
    let cloud: [String: String]
    private var changedKeys: [String] {
        Set(local.keys).union(cloud.keys).filter { local[$0] != cloud[$0] }.sorted()
    }
    var body: some View {
        DisclosureGroup("Compare saved data (\(changedKeys.count) changed keys)") {
            Text("This device: \(local.count) keys. iCloud: \(cloud.count) keys. An empty store can mean entries were deliberately cleared.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(changedKeys.prefix(12)), id: \.self) { key in
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(key.prefix(80))).font(.caption.bold())
                    Text("This device: " + (local[key].map { String($0.prefix(160)) } ?? "No value"))
                    Text("iCloud: " + (cloud[key].map { String($0.prefix(160)) } ?? "No value"))
                }.font(.caption).textSelection(.enabled)
            }
            if changedKeys.count > 12 { Text("Showing the first 12 changed keys.").font(.caption) }
        }
    }
}
