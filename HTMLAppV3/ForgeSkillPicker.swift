import SwiftUI
import UniformTypeIdentifiers

private struct ForgeImportedSkill: Codable, Identifiable {
    let attachment: ForgeAttachment
    let title: String
    let importedAt: Date

    private static let maximumBytes = 512_000

    var id: UUID { attachment.id }

    static func title(in markdown: String, fallback: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            for key in ["title", "name"] {
                let prefix = key + ":"
                for line in lines[1..<end] where line.lowercased().hasPrefix(prefix) {
                    let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !value.isEmpty && !["|", ">", "|-", ">-"].contains(value) { return value }
                }
            }
        }
        for line in lines where line.hasPrefix("# ") {
            let value = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return fallback
    }

    static func read(_ url: URL) throws -> Self {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard url.pathExtension.lowercased() == "md",
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              (1...maximumBytes).contains(size) else {
            throw ForgeAttachment.Failure.message("Choose a Markdown (.md) file up to 512 KB.")
        }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8),
              !text.contains("\0"), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ForgeAttachment.Failure.message("This file must contain readable UTF-8 Markdown.")
        }
        let title = Self.title(in: text, fallback: url.deletingPathExtension().lastPathComponent)
        return Self(attachment: ForgeAttachment(name: url.lastPathComponent, text: text, jpeg: nil, skillTitle: title),
                    title: title, importedAt: Date())
    }
}

struct ForgeSkillPicker: View {
    let selected: ([ForgeAttachment]) -> Void
    @State private var selection: [ForgeAttachment]

    init(initialSelection: [ForgeAttachment] = [], selected: @escaping ([ForgeAttachment]) -> Void,
         cancel: @escaping () -> Void) {
        self.selected = selected
        self.cancel = cancel
        _selection = State(initialValue: initialSelection)
    }
    let cancel: () -> Void
    @State private var skills: [ForgeImportedSkill] = []
    @State private var search = ""
    @State private var importing = false
    @State private var error: String?

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp/ForgeSkills", isDirectory: true)
    }

    private var filteredSkills: [ForgeImportedSkill] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return skills.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) ||
                $0.attachment.name.localizedCaseInsensitiveContains(query)
        }.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.importedAt > $1.importedAt : order == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search skills", text: $search)
                        .autocorrectionDisabled()
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Button { importing = true } label: {
                    Label("Import New Skill", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 16)

                List {
                    Section {
                        if filteredSkills.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "book.closed").font(.title2)
                                Text(skills.isEmpty ? "No skills imported yet" : "No matching skills")
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        }
                        ForEach(filteredSkills) { skill in
                            let checked = selection.contains { $0.id == skill.id }
                            Button {
                                if checked { selection.removeAll { $0.id == skill.id } }
                                else { selection.append(skill.attachment) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "book.closed.fill")
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 36, height: 36)
                                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(skill.title).font(.subheadline.weight(.semibold))
                                        Text("Imported \(skill.importedAt.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(checked ? Color.accentColor : Color.secondary)
                                }
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(checked ? .isSelected : [])
                        }
                    } header: {
                        Text("Imported skills")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Skills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selection.isEmpty ? "Done" : "Done (\(selection.count))") { selected(selection) }
                }
            }
        }
        .task { load() }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText]) { result in
            do {
                let skill = try ForgeImportedSkill.read(result.get())
                try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
                let destination = Self.directory.appendingPathComponent(skill.id.uuidString + ".json")
                try JSONEncoder().encode(skill).write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                skills.append(skill)
                search = ""
            } catch { self.error = error.localizedDescription }
        }
        .alert("Skills", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: Self.directory.path) else { return }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)
            skills = files.filter { $0.pathExtension == "json" }.compactMap {
                guard let data = try? Data(contentsOf: $0) else { return nil }
                return try? JSONDecoder().decode(ForgeImportedSkill.self, from: data)
            }
        } catch { self.error = error.localizedDescription }
    }
}
