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
        let frame = microphoneFrame(translation: microphoneTranslation)
        return hit(CGPoint(x: frame.midX, y: frame.midY), width: width)
    }

    static func microphoneFrame(translation: CGSize) -> CGRect {
        CGRect(x: -24 + translation.width, y: 68 + translation.height, width: 63, height: 63)
    }

    func frame(in width: CGFloat) -> CGRect {
        let targets = Self.allCases
        let tileWidth = (width - 2 * Self.horizontalInset - CGFloat(targets.count - 1) * Self.spacing) / CGFloat(targets.count)
        guard tileWidth > 0, let index = targets.firstIndex(of: self) else { return .null }
        return CGRect(x: Self.horizontalInset + CGFloat(index) * (tileWidth + Self.spacing),
                      y: 8, width: tileWidth, height: 88)
    }

    static func hit(_ point: CGPoint, width: CGFloat) -> Self? {
        allCases.first { $0.frame(in: width).contains(point) }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            if active {
                HStack(spacing: ForgeAttachmentTarget.spacing) {
                    ForEach(ForgeAttachmentTarget.allCases) { target in
                        VStack(spacing: 6) {
                            Image(systemName: target.symbol).font(.system(size: 26, weight: .semibold))
                            Text(target.rawValue.capitalized).font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 88)
                        .modifier(ForgeContextSurface(cornerRadius: 20))

                    }
                }
                .padding(.horizontal, ForgeAttachmentTarget.horizontalInset)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .overlay {
                    let target = ForgeAttachmentTarget.hit(microphoneTranslation: microphoneTranslation,
                                                           width: proxy.size.width)
                    let destination = target?.frame(in: proxy.size.width)
                        ?? ForgeAttachmentTarget.microphoneFrame(translation: microphoneTranslation)
                    JellyContextOutline(frame: destination, destination: destination, stretches: !reduceMotion)
                        .stroke(.background, lineWidth: 5)
                        .overlay {
                            JellyContextOutline(frame: destination, destination: destination, stretches: !reduceMotion)
                                .stroke(.primary, lineWidth: 2)
                        }
                        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.72),
                                   value: destination)
                        .opacity(target == nil ? 0 : 1)
                        .animation(reduceMotion ? nil : target == nil
                                   ? .easeOut(duration: 0.23).delay(0.08)
                                   : .easeOut(duration: 0.12), value: target == nil)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}


/// The position springs toward the destination. Its leading edge reaches out
/// ahead of the rest of the outline, then returns to the settled dimensions.
private struct JellyContextOutline: Shape {
    var frame: CGRect
    let destination: CGRect
    let stretches: Bool

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(.init(frame.minX, frame.minY), .init(frame.width, frame.height)) }
        set {
            frame = CGRect(x: newValue.first.first, y: newValue.first.second,
                           width: newValue.second.first, height: newValue.second.second)
        }
    }

    func path(in bounds: CGRect) -> Path {
        var outline = frame.insetBy(dx: 3, dy: 3)
        if stretches {
            let reachX = min(38, max(-38, (destination.midX - frame.midX) * 0.48))
            let reachY = min(38, max(-38, (destination.midY - frame.midY) * 0.48))
            outline = outline.union(outline.offsetBy(dx: reachX, dy: reachY))
        }
        return Path(roundedRect: outline, cornerRadius: 17)
    }
}
