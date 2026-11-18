import AppKit
import SwiftUI

private struct Release: Decodable {
    struct Change: Decodable {
        let title: String
        let description: String
        let symbol: String
        let tint: String

        var color: Color {
            switch tint {
            case "purple": return .purple
            case "indigo": return .indigo
            case "green": return .green
            case "orange": return .orange
            case "pink": return .pink
            case "red": return .red
            case "teal": return .teal
            case "cyan": return .cyan
            case "yellow": return .yellow
            case "mint": return .mint
            case "gray": return .gray
            default: return .blue
            }
        }
    }

    let version: String
    let changes: [Change]
}

@available(macOS 13.0, *)
private struct ReleaseCard: View {
    let release: Release
    let build: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .semibold))
                .frame(width: 78, height: 78)
                .background(
                    LinearGradient(colors: [.indigo, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 23)
                )

            VStack(alignment: .leading, spacing: 8) {
                Text("What’s new in \(release.version)").font(.system(size: 34, weight: .bold))
                Text("VERSION \(release.version) · BUILD \(build)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Text("Highlights in this version").font(.system(size: 19, weight: .bold))

            ForEach(release.changes.indices, id: \.self) { index in
                let change = release.changes[index]
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: NSImage(systemSymbolName: change.symbol, accessibilityDescription: nil) == nil ? "sparkles" : change.symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(change.color)
                        .frame(width: 46, height: 46)
                        .background(change.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(change.title).font(.system(size: 18, weight: .semibold))
                        Text(change.description).font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 17))
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(width: 560, alignment: .leading)
        .background(.black)
        .environment(\.colorScheme, .dark)
    }
}

@main
private struct RenderReleaseNotes {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 4, #available(macOS 13.0, *) else {
            throw CocoaError(.featureUnsupported)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
        let release = try JSONDecoder().decode(Release.self, from: data)
        let renderer = ImageRenderer(content: ReleaseCard(release: release, build: args[2]))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: URL(fileURLWithPath: args[3]), options: .atomic)
    }
}
