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

struct ForgeMicTestTarget: View {
    let microphoneTranslation: CGSize
    let size: CGSize

    static func frame(in size: CGSize) -> CGRect {
        let width = min(124, size.width)
        return CGRect(x: (size.width - width) / 2, y: max(0, size.height - 100),
                      width: width, height: 76)
    }

    static func hit(_ translation: CGSize, in size: CGSize) -> Bool {
        let microphone = ForgeAttachmentTarget.microphoneFrame(translation: translation)
        return frame(in: size).contains(CGPoint(x: microphone.midX, y: microphone.midY))
    }

    var body: some View {
        let frame = Self.frame(in: size)
        let highlighted = Self.hit(microphoneTranslation, in: size)
        VStack(spacing: 6) {
            Image(systemName: "waveform").font(.title2)
            Text("Test Mic").font(.caption.weight(.semibold))
        }
        .frame(width: frame.width, height: frame.height)
        .modifier(ForgeContextSurface(cornerRadius: 20))
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: 20).strokeBorder(.primary, lineWidth: 2)
            }
        }
        .position(x: frame.midX, y: frame.midY)
    }
}

struct ForgeAttachmentTargets: View {
    let active: Bool
    let microphoneTranslation: CGSize
    @AppStorage("htmlapp.dictationEngine") private var dictationEngine = "apple"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let microphone = ForgeAttachmentTarget.microphoneFrame(translation: microphoneTranslation)
            let targets = ForgeAttachmentTarget.allCases
            HStack(spacing: ForgeAttachmentTarget.spacing) {
                ForEach(targets.indices, id: \.self) { index in
                    let target = targets[index]
                    VStack(spacing: 6) {
                        Image(systemName: target.symbol).font(.system(size: 26, weight: .semibold))
                        Text(target.rawValue.capitalized).font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
                    .modifier(ForgeContextSurface(cornerRadius: 20))
                    .modifier(ForgeContextTileFlight(progress: active ? 1 : 0,
                                                     microphone: microphone,
                                                     destination: target.frame(in: proxy.size.width),
                                                     stagger: reduceMotion ? 0 : Double(index) * 0.045))
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.76),
                       value: active)
            .padding(.horizontal, ForgeAttachmentTarget.horizontalInset)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay {
                if active && dictationEngine == "whisper" {
                    ForgeMicTestTarget(microphoneTranslation: microphoneTranslation, size: proxy.size)
                }
            }
            .overlay {
                let target = active ? ForgeAttachmentTarget.hit(microphoneTranslation: microphoneTranslation,
                                                                width: proxy.size.width) : nil
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
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Keep tiles mounted so retracting and re-opening mid-drag reverses the same animation.
private struct ForgeContextTileFlight: AnimatableModifier {
    var progress: Double
    let microphone: CGRect
    let destination: CGRect
    let stagger: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let phase = CGFloat(max(0, min(1, (progress - stagger) / (1 - stagger))))
        let springOvershoot = CGFloat(max(0, progress - 1))
        let dx = destination.isNull ? 0 : destination.midX - microphone.midX
        let dy = destination.isNull ? 0 : destination.midY - microphone.midY
        let angle = Angle(radians: atan2(Double(dy), Double(dx)))
        let stretch = sin(phase * .pi) * 0.32
        let size = 0.22 + phase * 0.78
        return content
            .rotationEffect(.radians(-angle.radians))
            .scaleEffect(x: size * (1 + stretch), y: size * (1 - stretch * 0.48))
            .rotationEffect(angle)
            .offset(x: dx * (phase + springOvershoot - 1), y: dy * (phase + springOvershoot - 1))
            .opacity(destination.isNull ? 0 : Double(min(1, phase * 4)))
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
