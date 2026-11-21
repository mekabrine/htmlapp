import SwiftUI
import UIKit

/// Curated release notes travel with the app, without network access.
/// Add a new entry when shipping another release line; never infer changes
/// from a build number or claim an unavailable remote changelog.
enum HTMLAppReleaseNotes {
    struct Entry: Identifiable {
        let id: String
        let title: String
        let description: String
        let symbol: String
        let tint: Color
    }

    // Compile-time release identity. This is not computed from a possibly
    // stale IPA Info.plist or the GitHub runner's commit count.
    static let compiledVersion = "1.9.31"
    static let compiledBuild = "136"

    static var installedVersion: String { compiledVersion }
    static var installedBuild: String { compiledBuild }
    static var packagedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Missing"
    }
    static var packagedBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Missing"
    }
    static var packagingMatchesCode: Bool {
        packagedVersion == compiledVersion && packagedBuild == compiledBuild
    }

    static func entries(for version: String) -> [Entry] {
        guard version == compiledVersion else { return [] }
        return [
            Entry(id: "widget-context", title: "Add context from the Lock Screen",
                  description: "Choose camera photos, library photos, files, or skills before sending a voice request to Forge.",
                  symbol: "paperclip", tint: .blue),
            Entry(id: "widget-mic-test", title: "Test Alternative before recording",
                  description: "On the Lock Screen widget screen, say a few words and tap the purple mic. You’ll see the result, and a separate prompt recording starts right after.",
                  symbol: "mic.badge.plus", tint: .purple),
            Entry(id: "forge-current-place", title: "Build apps around your current place",
                  description: "Forge can use Apple Maps for nearby venue candidates and foreground driving estimates. Confirm your destination once and keep the estimate updated as you move.",
                  symbol: "location.fill", tint: .green),
            Entry(id: "forge-memory", title: "Forge remembers each app",
                  description: "Forge uses relevant past requests, style feedback and revision summaries. Review, exclude or pin context in What Forge Remembers.",
                  symbol: "clock.arrow.circlepath", tint: .purple),
            Entry(id: "forge-revisions", title: "Know what changed and what stayed",
                  description: "Edit History shows the requests and checks for saved changes. Restoring an earlier version updates which revisions Forge considers active.",
                  symbol: "arrow.uturn.backward", tint: .blue),
            Entry(id: "forge-screen-target", title: "Point Forge at the right screen",
                  description: "Select an element before asking for a change, or send a screen report with its last control and recent errors. Review files, skills and history in Request Context.",
                  symbol: "scope", tint: .purple),
            Entry(id: "forge-preview-compare", title: "Try both versions before saving",
                  description: "Switch between the previous and edited previews. Preview data is separate from your saved app.",
                  symbol: "rectangle.on.rectangle", tint: .blue),
            Entry(id: "forge-driving-destination", title: "Keep your confirmed destination",
                  description: "Choose a nearby venue during generation and the saved app can use it after you leave. Forge checks movement, driving estimates, denied location and route failures.",
                  symbol: "mappin.circle.fill", tint: .green),
            Entry(id: "forge-workflow-tests", title: "Check existing features after an edit",
                  description: "Forge gives complex edits more verification, checks sample records and tests declared workflows. Repair notes explain what changed and whether the retest passed.",
                  symbol: "checkmark.shield", tint: .green),
            Entry(id: "forge-resume", title: "Recover work after an interruption",
                  description: "Reopen a completed draft or rerun checks on saved source when a build is interrupted. Work History shows preview time, saved results and repair outcomes.",
                  symbol: "arrow.clockwise.circle", tint: .orange)
        ]
    }
}

struct HTMLAppWhatsNewView: View {
    let previousVersion: String?
    let onDone: () -> Void
    @State private var expandedHistoryItem: HistoryItemID?
    private var version: String { HTMLAppReleaseNotes.installedVersion }
    private var updates: [HTMLAppReleaseNotes.Entry] { HTMLAppReleaseNotes.entries(for: version) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 42, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 86, height: 86)
                            .background(
                                LinearGradient(colors: [.indigo, .purple, .pink],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 25)
                            )
                            .padding(.bottom, 8)

                        Text("What’s new in \(version)")
                            .font(.largeTitle.bold())
                            .minimumScaleFactor(0.8)
                        Text("VERSION \(version) · BUILD \(HTMLAppReleaseNotes.installedBuild)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        if !HTMLAppReleaseNotes.packagingMatchesCode {
                            Label("This IPA's packaged version does not match the app code. Please update your build process.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    if updates.isEmpty {
                        whatsNewRow(title: "You're on version \(version)",
                                    detail: "Detailed release notes have not been published for this version.",
                                    symbol: "checkmark.seal.fill", tint: .blue)
                    } else {
                        Text("Highlights in this version")
                            .font(.headline)
                        ForEach(updates) { item in
                            whatsNewRow(title: item.title, detail: item.description,
                                        symbol: item.symbol, tint: item.tint)
                        }
                    }
                    releaseHistory
                    Text("You can find this page again in Settings → What's New.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                Button(action: onDone) {
                    Text("Continue to HTMLApp")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private struct HistoryItemID: Equatable {
        let version: String
        let index: Int
    }

    private struct Release: Decodable, Identifiable {
        struct Change: Decodable {
            let title: String
            let description: String
            let symbol: String?
            let tint: String?
        }

        let changes: [Change]?
        let version: String
        let summary: String
        var id: String { version }
    }

    private static let history: [Release] = {
        guard let url = Bundle.main.url(forResource: "HTMLApp-Changelog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Release].self, from: data)) ?? []
    }()

    @ViewBuilder private var releaseHistory: some View {
        let oldVersion = previousVersion.flatMap {
            $0.isEmpty || $0.compare(version, options: .numeric) != .orderedAscending ? nil : $0
        }
        let releases = Self.history.filter { release in
            release.version.compare(version, options: .numeric) != .orderedDescending &&
                (oldVersion.map { release.version.compare($0, options: .numeric) == .orderedDescending } ?? true)
        }
        if !releases.isEmpty {
            DisclosureGroup(oldVersion.map { "What happened since \($0)" } ?? "Release history") {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(releases) { release in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(release.version)
                                .font(.subheadline.bold().monospacedDigit())
                                .accessibilityAddTraits(.isHeader)
                            if let changes = release.changes, !changes.isEmpty {
                                ForEach(changes.indices, id: \.self) { index in
                                    historyRow(changes[index], id: HistoryItemID(version: release.version, index: index))
                                }
                            } else {
                                Text(release.summary).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 16)
            }
        }
    }

    private func historyRow(_ change: Release.Change, id: HistoryItemID) -> some View {
        let isExpanded = expandedHistoryItem == id
        let tint: Color = switch change.tint {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "cyan": .cyan
        case "indigo": .indigo
        case "purple": .purple
        case "pink": .pink
        case "gray": .gray
        default: .blue
        }
        let symbol = change.symbol.flatMap { UIImage(systemName: $0) == nil ? nil : $0 } ?? "sparkles"
        return Button {
            expandedHistoryItem = isExpanded ? nil : id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(change.title).font(.footnote.weight(.semibold))
                    if isExpanded {
                        Text(change.description).font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 7)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.top, 10)
                    .accessibilityHidden(true)
            }
            .padding(8)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    private func whatsNewRow(title: String, detail: String,
                             symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 50, height: 50)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

