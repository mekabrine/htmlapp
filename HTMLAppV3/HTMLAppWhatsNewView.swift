import SwiftUI

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
    static let compiledVersion = "1.9.23"
    static let compiledBuild = "128"

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
            Entry(id: "release-history", title: "See what changed since your last version",
                  description: "Expand the release history below to catch up on versions you skipped.",
                  symbol: "clock.arrow.circlepath", tint: .blue),
            Entry(id: "forge-skills", title: "Bring your own Forge skills",
                  description: "Import Markdown skills once, then search and attach them to creation and edit requests from Additional context.",
                  symbol: "book.closed", tint: .purple),
            Entry(id: "discord-ipa", title: "Versioned Discord builds",
                  description: "IPA attachments and their Discord messages now identify the exact release.",
                  symbol: "arrow.down.doc", tint: .green)
        ]
    }
}

struct HTMLAppWhatsNewView: View {
    let previousVersion: String?
    let onDone: () -> Void
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

    private struct Release: Decodable, Identifiable {
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
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(releases) { release in
                        Text("**\(release.version)** · \(release.summary)")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 8)
            }
        }
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

