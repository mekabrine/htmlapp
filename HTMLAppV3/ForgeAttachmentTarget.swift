import SwiftUI

enum ForgeAttachmentTarget: String, Identifiable, CaseIterable {
    case camera, photos, files, skills
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .camera: return "camera.fill"
        case .photos: return "photo.on.rectangle"
        case .files: return "folder.fill"
        case .skills: return "book.closed"
        }
    }

    static let horizontalInset: CGFloat = 16
    static let spacing: CGFloat = 8

    static func hit(_ point: CGPoint, width: CGFloat) -> Self? {
        let tileWidth = (width - 2 * horizontalInset - CGFloat(allCases.count - 1) * spacing) / CGFloat(allCases.count)
        guard tileWidth > 0 else { return nil }
        return allCases.enumerated().first { index, _ in
            let x = horizontalInset + CGFloat(index) * (tileWidth + spacing)
            return CGRect(x: x, y: 8, width: tileWidth, height: 88).contains(point)
        }?.element
    }
}

struct ForgeAttachmentTargets: View {
    let active: Bool
    var body: some View {
        HStack(spacing: ForgeAttachmentTarget.spacing) {
            ForEach(ForgeAttachmentTarget.allCases) { target in
                VStack(spacing: 6) {
                    Image(systemName: target.symbol).font(.system(size: 26, weight: .semibold))
                    Text(target.rawValue.capitalized).font(.caption)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 88)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .padding(.horizontal, ForgeAttachmentTarget.horizontalInset)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(active ? 1 : 0)
        .allowsHitTesting(false)
    }
}
