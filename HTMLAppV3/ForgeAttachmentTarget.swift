import SwiftUI

enum ForgeAttachmentTarget: String, Identifiable, CaseIterable {
    case camera, photos, files
    var id: String { rawValue }
    var symbol: String { self == .camera ? "camera.fill" : self == .photos ? "photo.on.rectangle" : "folder.fill" }
    static func hit(_ point: CGPoint, width: CGFloat) -> Self? {
        for (index, target) in Self.allCases.enumerated() {
            let x = width / 2 + CGFloat(index - 1) * 100
            if CGRect(x: x - 44, y: 8, width: 88, height: 100).contains(point) { return target }
        }
        return nil
    }
}

struct ForgeAttachmentTargets: View {
    let active: Bool
    var body: some View {
        HStack(spacing: 12) {
            ForEach(ForgeAttachmentTarget.allCases) { target in
                VStack(spacing: 6) {
                    Image(systemName: target.symbol).font(.system(size: 32, weight: .semibold))
                    Text(target.rawValue.capitalized).font(.caption)
                }
                .frame(width: 88, height: 88)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(active ? 1 : 0)
        .allowsHitTesting(false)
    }
}
