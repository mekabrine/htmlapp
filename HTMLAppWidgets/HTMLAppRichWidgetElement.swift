import SwiftUI

/// Serializable SwiftUI paths and shapes. Animation only follows a delivered
/// content update; these views never start a loop or request repeated reloads.
struct HTMLAppRichWidgetElement: View {
    let node: HTMLAppWidgetElement
    let progress: Double
    let accent: String

    private var color: Color { Color(htmlAppHex: node.foregroundHex ?? accent) }
    private var fill: LinearGradient {
        LinearGradient(colors: (node.colors ?? [node.foregroundHex ?? accent, node.foregroundHex ?? accent]).map { Color(htmlAppHex: $0) },
                       startPoint: .leading, endPoint: .trailing)
    }
    private var fraction: Double { min(1, max(0, node.progress ?? progress)) }
    private var samples: [Double] {
        let input = node.samples ?? []
        let low = node.minimum ?? min(0, input.min() ?? 0)
        let high = node.maximum ?? max(low + 1, input.max() ?? 1)
        return input.map { min(1, max(0, ($0 - low) / max(0.0001, high - low))) }
    }
    private var points: [HTMLAppWidgetPoint] {
        if let points = node.points { return points }
        let values = samples
        return values.enumerated().map { index, value in
            HTMLAppWidgetPoint(x: Double(index) / Double(max(1, values.count - 1)), y: 1 - value)
        }
    }

    var body: some View {
        drawing
            .frame(maxWidth: .infinity)
            .frame(height: CGFloat(node.height ?? defaultHeight))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(node.accessibilityLabel ?? node.type)
            .accessibilityValue(Text(node.samples == nil ? fraction.formatted(.percent.precision(.fractionLength(0))) : "\(samples.count) samples"))
    }

    private var defaultHeight: Double { node.type == "segmentedMeter" || node.type == "gradient" ? 16 : 52 }

    @ViewBuilder private var drawing: some View {
        switch node.type {
        case "barChart", "waveform":
            GeometryReader { proxy in
                HStack(alignment: node.type == "waveform" ? .center : .bottom, spacing: CGFloat(node.spacing ?? 3)) {
                    ForEach(samples.indices, id: \.self) { index in
                        Capsule().fill(fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: max(2, proxy.size.height * CGFloat(samples[index])))
                    }
                }
                .frame(height: proxy.size.height)
            }
        case "segmentedMeter":
            let count = node.segments ?? 16
            HStack(spacing: CGFloat(node.spacing ?? 3)) {
                ForEach(0..<count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2).fill(fill)
                        .opacity(Double(index) < fraction * Double(count) ? 1 : 0.18)
                }
            }
        case "gauge":
            ZStack {
                HTMLAppGaugeArc(fraction: 1).stroke(color.opacity(0.2), style: StrokeStyle(lineWidth: CGFloat(node.lineWidth ?? 7), lineCap: .round))
                HTMLAppGaugeArc(fraction: fraction).stroke(fill, style: StrokeStyle(lineWidth: CGFloat(node.lineWidth ?? 7), lineCap: .round))
            }
            .padding(CGFloat(node.lineWidth ?? 7) / 2)
        case "gradient":
            RoundedRectangle(cornerRadius: CGFloat(node.cornerRadius ?? 8)).fill(fill)
        default:
            GeometryReader { proxy in
                let inset = CGFloat(node.lineWidth ?? 3) / 2 + 3
                let width = max(1, proxy.size.width - inset * 2)
                let height = max(1, proxy.size.height - inset * 2)
                let line = HTMLAppPolyline(points: points, closed: node.closed == true)
                ZStack(alignment: .topLeading) {
                    if node.closed == true { line.fill(fill).opacity(0.18) }
                    line.stroke(fill, style: StrokeStyle(lineWidth: CGFloat(node.lineWidth ?? 3), lineCap: .round, lineJoin: .round))
                    if node.type == "route" {
                        let marker = HTMLAppPolyline.location(at: fraction, points: points, closed: node.closed == true)
                        Circle().fill(color).frame(width: 8, height: 8)
                            .position(x: CGFloat(marker.x) * width, y: CGFloat(marker.y) * height)
                    }
                }
                .frame(width: width, height: height)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
    }
}

struct HTMLAppGaugeArc: Shape {
    var fraction: Double
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width / 2, rect.height / 1.72)
        let center = CGPoint(x: rect.midX, y: rect.minY + radius)
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(135), endAngle: .degrees(135 + 270 * min(1, max(0, fraction))), clockwise: false)
        return path
    }
}

struct HTMLAppPolyline: Shape {
    let points: [HTMLAppWidgetPoint]
    var closed = false
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            let position = CGPoint(x: rect.minX + rect.width * CGFloat(point.x), y: rect.minY + rect.height * CGFloat(point.y))
            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
        }
        if closed { path.closeSubpath() }
        return path
    }

    static func location(at fraction: Double, points input: [HTMLAppWidgetPoint], closed: Bool = false) -> HTMLAppWidgetPoint {
        var points = input
        if closed, let first = input.first, input.last != first { points.append(first) }
        guard let first = points.first, points.count > 1 else { return points.first ?? .init(x: 0.5, y: 0.5) }
        let lengths = zip(points, points.dropFirst()).map { start, end in hypot(end.x - start.x, end.y - start.y) }
        var remaining = min(1, max(0, fraction)) * lengths.reduce(0, +)
        for (index, length) in lengths.enumerated() {
            if remaining <= length, length > 0 {
                let part = remaining / length
                return .init(x: points[index].x + (points[index + 1].x - points[index].x) * part,
                             y: points[index].y + (points[index + 1].y - points[index].y) * part)
            }
            remaining -= length
        }
        return points.last ?? first
    }
}
