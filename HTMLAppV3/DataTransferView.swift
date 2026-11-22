import SwiftUI
import UniformTypeIdentifiers

struct HTMLAppDataTransferView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedIDs: Set<String> = []
    @State private var showImporter = false
    @State private var pendingImportFailures: [String] = []
    @State private var pendingImportURLs: [URL] = []
    @State private var pendingImportDirectory: URL?
    @State private var showImportMode = false
    @State private var importing = false

    private var canReplaceLibrary: Bool {
        pendingImportURLs.count == 1 && pendingImportFailures.isEmpty
    }

    var body: some View {
        List {
            Section {
                Button {
                    store.exportPortablePackage()
                } label: {
                    Label("Export Complete Library", systemImage: "shippingbox.fill")
                }

                Button {
                    showImporter = true
                } label: {
                    Label("Import HTMLApp Backup", systemImage: "square.and.arrow.down.fill")
                }
                .disabled(importing)
            } header: {
                Text("Move Between Devices")
            } footer: {
                Text("Backups are normal .zip files containing a versioned HTMLApp manifest plus offline website resources. Generated AI artwork is embedded directly in each app, so it moves with the package automatically.")
            }

            Section("Nearby Device Transfer") {
                NavigationLink("Open Nearby Transfer") {
                    NearbyAppTransferView(appIDs: selectedIDs)
                }
                Text("Select apps below to choose a nearby device. To receive, stay in the Library with HTMLApp open. Transfers are encrypted.").font(.footnote)
            }

            if !store.apps.isEmpty {
                Section {
                    HStack {
                        Button(selectedIDs.count == store.apps.count ? "Clear" : "Select All") {
                            if selectedIDs.count == store.apps.count {
                                selectedIDs.removeAll()
                            } else {
                                selectedIDs = Set(store.apps.map(\.id))
                            }
                        }
                        Spacer()
                        Text("\(selectedIDs.count) selected")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(store.orderedApps) { app in
                        Button {
                            if selectedIDs.contains(app.id) { selectedIDs.remove(app.id) }
                            else { selectedIDs.insert(app.id) }
                        } label: {
                            HStack(spacing: 12) {
                                AppIconView(app: app, size: 42)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.name).foregroundStyle(.primary)
                                    if !app.summary.isEmpty {
                                        Text(app.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: selectedIDs.contains(app.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(app.id) ? Color.accentColor : Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        store.exportPortablePackage(appIDs: selectedIDs)
                    } label: {
                        Label("Export Selected Apps", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedIDs.isEmpty)
                } header: {
                    Text("Selective Export")
                } footer: {
                    Text("Folder placement, aliases, icons, HTML, portable app data, generated widgets/background jobs, embedded generated assets, and cached website files are included. Sensitive permissions always ask again on the receiving device.")
                }
            }

            Section {
                Label("Merge is the safe default", systemImage: "plus.square.on.square")
                Text("Imported apps receive new IDs, so your existing library cannot be overwritten by a name or ID collision.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Label("Replace Library is a full restore", systemImage: "arrow.clockwise.square.fill")
                Text("Use it when moving your entire HTMLApp library to another device. Existing saved apps are removed before the backup is restored.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Import Behavior")
            }
        }
        .onDisappear { clearPendingImport() }
        .navigationTitle("Backup & Transfer")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.zip, UTType(filenameExtension: "zip")].compactMap { $0 },
            allowsMultipleSelection: true
        ) { result in
            receiveImport(result)
        }
        .confirmationDialog(
            "How should the selected backups be imported?",
            isPresented: $showImportMode,
            titleVisibility: .visible
        ) {
            Button("Merge as New Copies") { importPending(replace: false) }
            if canReplaceLibrary {
                Button("Replace Entire Library", role: .destructive) { importPending(replace: true) }
            }
            Button("Cancel", role: .cancel) { clearPendingImport() }
        } message: {
            Text(canReplaceLibrary
                 ? "Merge keeps your current library. Replace Library removes existing saved HTMLApps first."
                 : "All selected backups will be merged as new copies. Select one backup to replace the entire library.")
        }
        .overlay {
            if importing {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                    ProgressView("Importing backup…").controlSize(.large)
                }
            }
        }
    }

    private func receiveImport(_ result: Result<[URL], Error>) {
        do {
            let sources = try result.get()
            guard !sources.isEmpty else { return }
            clearPendingImport()
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("HTMLApp-Import-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            pendingImportDirectory = directory
            var failures: [String] = []
            for source in sources {
                let accessing = source.startAccessingSecurityScopedResource()
                defer { if accessing { source.stopAccessingSecurityScopedResource() } }
                do {
                    let subdirectory = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
                    let destination = subdirectory.appendingPathComponent(source.lastPathComponent)
                    try FileManager.default.copyItem(at: source, to: destination)
                    pendingImportURLs.append(destination)
                } catch { failures.append(source.lastPathComponent + ": " + error.localizedDescription) }
            }
            if pendingImportURLs.isEmpty {
                clearPendingImport()
                store.errorMessage = failures.joined(separator: "\n")
            } else {
                pendingImportFailures = failures
                showImportMode = true
            }
        } catch {
            store.errorMessage = "The selected backups could not be opened: " + error.localizedDescription
        }
    }

    private func clearPendingImport() {
        if let pendingImportDirectory { try? FileManager.default.removeItem(at: pendingImportDirectory) }
        pendingImportURLs = []
        pendingImportDirectory = nil
        pendingImportFailures = []
    }

    private func importPending(replace: Bool) {
        guard !pendingImportURLs.isEmpty, !replace || canReplaceLibrary else { return }
        importing = true
        defer { importing = false; clearPendingImport() }
        var failures = pendingImportFailures
        var imported = 0
        for url in pendingImportURLs {
            do {
                try store.importPortablePackage(from: url, replaceExisting: replace)
                imported += 1
            } catch { failures.append(url.lastPathComponent + ": " + error.localizedDescription) }
        }
        if imported > 1 { store.notice = "Imported \(imported) backups." }
        if !failures.isEmpty { store.errorMessage = failures.joined(separator: "\n") }
    }
}
