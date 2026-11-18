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

    static func hit(microphoneTranslation: CGSize, width: CGFloat) -> Self? {
        let center = CGPoint(x: -24 + microphoneTranslation.width + 31.5,
                             y: 68 + microphoneTranslation.height + 31.5)
        return hit(center, width: width)
    }

    static func hit(_ point: CGPoint, width: CGFloat) -> Self? {
        let tileWidth = (width - 2 * horizontalInset - CGFloat(allCases.count - 1) * spacing) / CGFloat(allCases.count)
        guard tileWidth > 0 else { return nil }
        return allCases.enumerated().first { index, _ in
            let x = horizontalInset + CGFloat(index) * (tileWidth + spacing)
            return CGRect(x: x, y: 8, width: tileWidth, height: 88).contains(point)
        }?.element
    }
}

struct ForgeContextSurface: ViewModifier {
    let cornerRadius: CGFloat
    var interactive = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

struct ForgeAttachmentTargets: View {
    let active: Bool
    let microphoneTranslation: CGSize

    var body: some View {
        GeometryReader { proxy in
            if active {
                let currentTarget = ForgeAttachmentTarget.hit(microphoneTranslation: microphoneTranslation,
                                                              width: proxy.size.width)
                HStack(spacing: ForgeAttachmentTarget.spacing) {
                    ForEach(ForgeAttachmentTarget.allCases) { target in
                        VStack(spacing: 6) {
                            Image(systemName: target.symbol).font(.system(size: 26, weight: .semibold))
                            Text(target.rawValue.capitalized).font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 88)
                        .modifier(ForgeContextSurface(cornerRadius: 20))
                        .overlay {
                            if target == currentTarget {
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(.background, lineWidth: 5)
                                RoundedRectangle(cornerRadius: 20)
                                    .inset(by: 1)
                                    .strokeBorder(.primary, lineWidth: 2)
                            }
                        }
                    }
                }
                .padding(.horizontal, ForgeAttachmentTarget.horizontalInset)
                .padding(.top, 8)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
