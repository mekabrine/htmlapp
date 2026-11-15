import WidgetKit
import SwiftUI
import AppIntents
import UIKit

extension WidgetFamily {
    var storageName: String {
        switch self {
        case .systemSmall: return "systemSmall"
        case .systemMedium: return "systemMedium"
        case .systemLarge: return "systemLarge"
        case .systemExtraLarge: return "systemExtraLarge"
        case .accessoryInline: return "accessoryInline"
        case .accessoryCircular: return "accessoryCircular"
        case .accessoryRectangular: return "accessoryRectangular"
        @unknown default: return "unsupported"
        }
    }
}

struct HTMLAppWidgetEntry: TimelineEntry {
    let date: Date
    let definition: HTMLAppWidgetDefinition
}

enum HTMLAppWidgetTimeline {
    static func make(definition: HTMLAppWidgetDefinition, now: Date = Date()) async -> Timeline<HTMLAppWidgetEntry> {
        // Providers are read-only. A slow network response must not revert shared publications.
        let refreshed = definition // Display committed App Group content immediately; never block on HTTPS.
        // Request shorter timelines for generated widgets. WidgetKit owns
        // actual background scheduling and may delay refreshes to save power.
        let interval = max(15, refreshed.refresh?.intervalMinutes ?? 30)
        var dates = [now]
        if let range = refreshed.snapshot.nativeTimeInterval {
            dates += [range.lowerBound, range.upperBound].filter { $0 > now }
        }
        if let deadline = refreshed.snapshot.countdownDeadline, deadline > now { dates.append(deadline) }
        // Older systems cannot live-format selected units. Prepare minute changes,
        // never a per-second reload loop. iOS still controls timeline delivery.
        if #available(iOS 18.0, *) {} else if refreshed.snapshot.needsMinuteTimeline {
            let anchor = refreshed.snapshot.nativeTimeInterval.map {
                refreshed.snapshot.countsDown ? $0.upperBound : $0.lowerBound
            } ?? refreshed.snapshot.countdownDeadline ?? now
            let first = anchor.timeIntervalSince1970 + (floor(now.timeIntervalSince(anchor) / 60) + 1) * 60
            dates += (0..<120).map { Date(timeIntervalSince1970: first + Double($0 * 60)) }
        }
        let entries = Array(Set(dates)).sorted().map { date -> HTMLAppWidgetEntry in
            var value = refreshed
            value.snapshot = refreshed.snapshot.presentation(at: date)
            return .init(date: date, definition: value)
        }
        return Timeline(entries: entries,
                        policy: .after(now.addingTimeInterval(TimeInterval(interval * 60))))
    }
}

struct HTMLAppPrimaryWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HTMLAppWidgetEntry {
        .init(date: Date(), definition: .placeholder())
    }

    func getSnapshot(in context: Context, completion: @escaping (HTMLAppWidgetEntry) -> Void) {
        completion(.init(date: Date(), definition: HTMLAppWidgetResolver.load(selectedID: nil, family: context.family.storageName, phase: "snapshot")))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HTMLAppWidgetEntry>) -> Void) {
        Task {
            let definition = HTMLAppWidgetResolver.load(selectedID: nil, family: context.family.storageName, phase: "timeline")
            completion(await HTMLAppWidgetTimeline.make(definition: definition))
        }
    }
}

@available(iOS 17.0, *)
struct HTMLAppWidgetEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "HTMLApp Widget"
    static var defaultQuery = HTMLAppWidgetEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

@available(iOS 17.0, *)
struct HTMLAppWidgetEntityQuery: EntityQuery {
    private var choices: [HTMLAppWidgetEntity] {
        do {
            let available = try HTMLAppWidgetStore.readAll().map {
                HTMLAppWidgetEntity(id: $0.id, name: $0.name)
            }
            return [HTMLAppWidgetEntity(id: HTMLAppWidgetResolver.primaryID, name: "Selected Primary (choose in HTMLApp)")] + available
        } catch {
            return [HTMLAppWidgetEntity(id: HTMLAppWidgetResolver.primaryID, name: "Storage unavailable — open HTMLApp diagnostics")]
        }
    }

    func entities(for identifiers: [HTMLAppWidgetEntity.ID]) async throws -> [HTMLAppWidgetEntity] {
        let available = choices
        return identifiers.map { id in
            available.first { $0.id == id } ?? HTMLAppWidgetEntity(id: id, name: "Unavailable widget — republish or choose Primary")
        }
    }

    func suggestedEntities() async throws -> [HTMLAppWidgetEntity] {
        choices
    }

    func defaultResult() async -> HTMLAppWidgetEntity? {
        choices.first
    }
}

@available(iOS 17.0, *)
struct HTMLAppWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose HTMLApp Widget"
    static var description = IntentDescription("Choose a widget published by one of your saved HTMLApps.")

    @Parameter(title: "Widget")
    var widget: HTMLAppWidgetEntity?
}

@available(iOS 17.0, *)
struct HTMLAppConfiguredWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HTMLAppWidgetEntry {
        .init(date: Date(), definition: .placeholder())
    }

    func snapshot(for configuration: HTMLAppWidgetConfigurationIntent, in context: Context) async -> HTMLAppWidgetEntry {
        .init(date: Date(), definition: HTMLAppWidgetResolver.load(selectedID: configuration.widget?.id, family: context.family.storageName, phase: "snapshot"))
    }

    func timeline(for configuration: HTMLAppWidgetConfigurationIntent, in context: Context) async -> Timeline<HTMLAppWidgetEntry> {
        let definition = HTMLAppWidgetResolver.load(selectedID: configuration.widget?.id, family: context.family.storageName, phase: "timeline")
        return await HTMLAppWidgetTimeline.make(definition: definition)
    }


}

struct HTMLAppWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HTMLAppWidgetEntry

    private var snapshot: HTMLAppWidgetSnapshot { entry.definition.snapshot }
    private var dynamicValue: some View {
        HTMLAppWidgetTimerText(snapshot: snapshot, date: entry.date, format: snapshot.timeFormat)
    }

    @ViewBuilder
    private var timeProgress: some View {
        if let range = snapshot.nativeTimeInterval, snapshot.showsTimeProgress {
            ProgressView(timerInterval: range, countsDown: snapshot.countsDown) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(accent)
            .accessibilityLabel(snapshot.title ?? "Time progress")
        }
    }

    var body: some View {
        Group {
            if #available(iOS 17.0, *) {
                widgetContent
                    .containerBackground(for: .widget) { background }
            } else {
                widgetContent
                    .background(background)
            }
        }
        .widgetURL(deepLink)
    }

    @ViewBuilder
    private var widgetContent: some View {
        if let content = snapshot.customContent(for: family.storageName) {
            HTMLAppWidgetElementView(node: content, snapshot: snapshot, date: entry.date)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .font(.caption)
                .foregroundStyle(foreground)
        } else {
        switch family {
        case .accessoryInline:
            inlineView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .systemSmall:
            compactCard
        case .systemMedium:
            mediumCard
        case .systemLarge, .systemExtraLarge:
            largeCard
        @unknown default:
            compactCard
        }
        }
    }

    private var inlineView: some View {
        HStack(spacing: 4) {
            if let symbol = snapshot.systemSymbol, !symbol.isEmpty {
                Image(systemName: symbol)
            }
            if snapshot.nativeTimeInterval != nil || snapshot.countdownDeadline != nil {
                Text(snapshot.title ?? entry.definition.name).lineLimit(1)
                dynamicValue.lineLimit(1).minimumScaleFactor(0.6)
            } else {
                Text([snapshot.title, snapshot.value].compactMap { $0 }.joined(separator: " ")).lineLimit(1)
            }
        }
    }

    private var circularView: some View {
        GeometryReader { geometry in
        ZStack {
            if snapshot.showsTimeProgress {
                timeProgress.progressViewStyle(.circular)
                circularCenter
            } else if let progress = snapshot.progress {
                Gauge(value: min(max(progress, 0), 1)) {
                    EmptyView()
                } currentValueLabel: {
                    circularCenter
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                circularCenter
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
    }

    @ViewBuilder
    private var circularCenter: some View {
        VStack(spacing: 1) {
            if let symbol = snapshot.systemSymbol, !symbol.isEmpty {
                Image(systemName: symbol)
            }
            if snapshot.hasDisplayValue {
                dynamicValue.font(.caption2.bold()).lineLimit(1).minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if let symbol = snapshot.systemSymbol, !symbol.isEmpty {
                    Image(systemName: symbol)
                }
                Text(snapshot.title ?? entry.definition.name)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            if snapshot.hasDisplayValue {
                dynamicValue
                    .font(.headline)
                    .lineLimit(1)
            }
            if snapshot.showsTimeProgress { timeProgress.progressViewStyle(.linear) }
            if let footer = snapshot.footer ?? snapshot.subtitle, !footer.isEmpty {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Spacer(minLength: 0)
            if snapshot.showsTimeProgress {
                heroValue
                timeProgress.progressViewStyle(.linear)
            } else if snapshot.layout?.lowercased() == "ring",
               let progress = snapshot.progress {
                ZStack {
                    Circle().stroke(accent.opacity(0.20), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: min(max(progress, 0), 1))
                        .stroke(accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    heroValue
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(5)
            } else {
                heroValue
                if let progress = snapshot.progress {
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(accent)
                }
            }
            footer
        }
        .padding(14)
        .foregroundStyle(foreground)
    }

    private var mediumCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                header
                Spacer(minLength: 0)
                heroValue
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if snapshot.showsTimeProgress {
                timeProgress.progressViewStyle(.linear).frame(maxWidth: 140)
            } else if snapshot.layout?.lowercased() == "image", let image = decodedImage {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 108, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else if snapshot.layout?.lowercased() == "ring",
                      let progress = snapshot.progress {
                ZStack {
                    Circle().stroke(accent.opacity(0.2), lineWidth: 12)
                    Circle().trim(from: 0, to: min(max(progress, 0), 1))
                        .stroke(accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if snapshot.hasDisplayValue {
                        dynamicValue.font(.title3.bold()).lineLimit(1)
                    }
                }
                .frame(width: 110, height: 110)
            } else {
                itemList(limit: 3)
                    .frame(maxWidth: 140, alignment: .leading)
            }
        }
        .padding(14)
        .foregroundStyle(foreground)
    }

    private var largeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if snapshot.nativeTimeInterval != nil { heroValue }
            if snapshot.layout?.lowercased() == "image", let image = decodedImage {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if snapshot.nativeTimeInterval == nil {
                heroValue
            }
            if snapshot.showsTimeProgress {
                timeProgress.progressViewStyle(.linear)
            } else if let progress = snapshot.progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(accent)
            }
            itemList(limit: 6)
            Spacer(minLength: 0)
            footer
        }
        .padding(16)
        .foregroundStyle(foreground)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if let symbol = snapshot.systemSymbol, !symbol.isEmpty {
                Image(systemName: symbol)
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                if let eyebrow = snapshot.eyebrow, !eyebrow.isEmpty {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                        .opacity(0.72)
                }
                Text(snapshot.title ?? entry.definition.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var heroValue: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if snapshot.hasDisplayValue {
                    dynamicValue
                        .font(.system(size: family == .systemSmall ? 30 : 36, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                }
                if let unit = snapshot.unit, !unit.isEmpty {
                    Text(unit)
                        .font(.caption.bold())
                        .opacity(0.72)
                }
            }
            if let subtitle = snapshot.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .opacity(0.78)
                    .lineLimit(family == .systemSmall ? 2 : 1)
            }
        }
    }

    @ViewBuilder
    private func itemList(limit: Int) -> some View {
        let items = Array((snapshot.items ?? []).prefix(limit))
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(items) { item in
                    if (family == .systemMedium || family == .systemLarge || family == .systemExtraLarge),
                       let action = item.action, let url = actionURL(action, itemID: item.id) {
                        Link(destination: url) { widgetItemRow(item) }
                    } else {
                        widgetItemRow(item)
                    }
                }
            }
        }
    }

    private func widgetItemRow(_ item: HTMLAppWidgetItem) -> some View {
                    HStack(spacing: 7) {
                        if let symbol = item.systemSymbol, !symbol.isEmpty {
                            Image(systemName: symbol)
                                .font(.caption)
                                .foregroundStyle(accent)
                                .frame(width: 15)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label)
                                .font(.caption2)
                                .opacity(0.72)
                                .lineLimit(1)
                            if let detail = item.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: 9))
                                    .opacity(0.55)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(item.value)
                                .font(.caption.bold()).lineLimit(1)
                            if let progress = item.progress {
                                ProgressView(value: min(max(progress, 0), 1))
                                    .tint(accent)
                                    .frame(width: 55)
                            }
                        }
                    }
    }

    @ViewBuilder
    private var footer: some View {
        if let footer = snapshot.footer, !footer.isEmpty {
            Text(footer)
                .font(.caption2)
                .opacity(0.62)
                .lineLimit(1)
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(htmlAppHex: snapshot.backgroundHex ?? "#15171B"),
                Color(htmlAppHex: snapshot.backgroundSecondaryHex ?? snapshot.backgroundHex ?? "#15171B")
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var foreground: Color {
        Color(htmlAppHex: snapshot.foregroundHex ?? "#FFFFFF")
    }

    private var accent: Color {
        Color(htmlAppHex: snapshot.accentHex ?? "#65A9FF")
    }

    private var decodedImage: Image? {
        guard let encoded = snapshot.imageBase64 else { return nil }
        let raw = encoded.components(separatedBy: ",").last ?? encoded
        guard raw.count <= 1_500_000,
              let data = Data(base64Encoded: raw),
              let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
    }

    private var deepLink: URL? {
        guard entry.definition.appID != "placeholder" else { return nil }
        var components = URLComponents()
        components.scheme = "htmlapp"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "id", value: entry.definition.appID)]
        if entry.definition.openBehavior == "action", let action = entry.definition.action {
            return actionURL(action, itemID: nil)
        }
        return components.url
    }

    private func actionURL(_ action: HTMLAppWidgetAction, itemID: String?) -> URL? {
        var parts = URLComponents()
        parts.scheme = "htmlapp"
        parts.host = "open"
        var params = [
            URLQueryItem(name: "id", value: entry.definition.appID),
            URLQueryItem(name: "widget", value: entry.definition.widgetID),
            URLQueryItem(name: "action", value: action.id)
        ]
        if let itemID { params.append(URLQueryItem(name: "item", value: itemID)) }
        guard let signature = HTMLAppWidgetActionLink.signature(
            appID: entry.definition.appID,
            widgetID: entry.definition.widgetID,
            actionID: action.id, itemID: itemID) else { return nil }
        params.append(URLQueryItem(name: "signature", value: signature))
        parts.queryItems = params
        return parts.url
    }
}

struct HTMLAppPrimaryWidget: Widget {
    let kind = "HTMLAppPrimaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HTMLAppPrimaryWidgetProvider()) { entry in
            HTMLAppWidgetView(entry: entry)
        }
        .configurationDisplayName("HTMLApp Primary")
        .description("Shows the latest primary widget published by a saved HTMLApp.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
            .accessoryInline, .accessoryCircular, .accessoryRectangular
        ])
    }
}


#if !WIDGET_TESTING
@main
struct HTMLAppWidgetsBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        HTMLAppPrimaryWidget()
        HTMLAppVoiceCreateWidget()
        // Removed broken picker-based widget variants. The primary widget
        // always displays the latest snapshot and needs no manual app selection.
        if #available(iOS 16.2, *) {
            HTMLAppLiveActivityWidget()
            HTMLAppForgeActivityWidget()
        }
        if #available(iOS 18.0, *) {
            HTMLAppOpenControl()
            HTMLAppButtonControl()
            HTMLAppToggleControl()
        }
    }
}

#endif

extension Color {
    init(htmlAppHex raw: String) {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)

        let red, green, blue, alpha: Double
        switch value.count {
        case 8:
            red = Double((number >> 24) & 0xFF) / 255
            green = Double((number >> 16) & 0xFF) / 255
            blue = Double((number >> 8) & 0xFF) / 255
            alpha = Double(number & 0xFF) / 255
        case 6:
            red = Double((number >> 16) & 0xFF) / 255
            green = Double((number >> 8) & 0xFF) / 255
            blue = Double(number & 0xFF) / 255
            alpha = 1
        default:
            red = 0.08
            green = 0.09
            blue = 0.11
            alpha = 1
        }
        self.init(red: red, green: green, blue: blue, opacity: alpha)
    }
}


/// Native time text shared by templates and the declarative layout renderer.
struct HTMLAppWidgetTimerText: View {
    let snapshot: HTMLAppWidgetSnapshot
    let date: Date
    var format: String? = nil

    private var selectedFormat: String { format ?? snapshot.timeFormat ?? "automatic" }
    private var interval: ClosedRange<Date>? {
        snapshot.nativeTimeInterval ?? snapshot.countdownDeadline.map { min(date, $0)...$0 }
    }
    var body: some View {
        value.monospacedDigit()
    }
    @ViewBuilder private var value: some View {
        if let range = interval {
            if ["automatic", "hoursMinutesSeconds", "minutesSeconds"].contains(selectedFormat) {
                Text(timerInterval: range, countsDown: snapshot.countsDown, showsHours: selectedFormat != "minutesSeconds")
            } else if date < range.lowerBound || date >= range.upperBound {
                Text(snapshot.formattedTime(at: date, format: selectedFormat))
            } else if #available(iOS 18.0, *) {
                // System-provided discrete format styles are serializable by WidgetKit;
                // custom formatter closures or preformatted strings do not tick live.
                Text(.currentDate, format: .offset(
                    to: snapshot.countsDown ? range.upperBound : range.lowerBound,
                    allowedFields: fields, maxFieldCount: 2, sign: .never))
            } else if selectedFormat == "seconds" {
                // iOS 16/17 have no seconds-only native live format. Keep a working
                // bounded MM:SS timer instead of a frozen seconds snapshot.
                Text(timerInterval: range, countsDown: snapshot.countsDown, showsHours: false)
            } else {
                Text(snapshot.formattedTime(at: date, format: selectedFormat))
            }
        } else {
            Text(snapshot.value ?? "—")
        }
    }
    @available(iOS 18.0, *)
    private var fields: Set<Date.ComponentsFormatStyle.Field> {
        switch selectedFormat {
        case "seconds": return [.second]
        case "minutes": return [.minute]
        case "hours": return [.hour]
        default: return [.hour, .minute]
        }
    }
}

/// Recursive value views are type-erased at each node to bound Swift's generic
/// type graph. Input is validated to 96 nodes / six levels at publication.
struct HTMLAppWidgetElementView: View {
    let node: HTMLAppWidgetElement
    let snapshot: HTMLAppWidgetSnapshot
    let date: Date

    private var horizontal: HorizontalAlignment {
        node.alignment == "leading" ? .leading : node.alignment == "trailing" ? .trailing : .center
    }
    private var alignment: Alignment {
        node.alignment == "leading" ? .leading : node.alignment == "trailing" ? .trailing : .center
    }
    private var vertical: VerticalAlignment {
        switch node.verticalAlignment {
        case "top": return .top
        case "bottom": return .bottom
        case "firstTextBaseline": return .firstTextBaseline
        default: return .center
        }
    }
    private var textAlignment: TextAlignment {
        node.alignment == "leading" ? .leading : node.alignment == "trailing" ? .trailing : .center
    }
    private var weight: Font.Weight {
        switch node.fontWeight {
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        default: return .regular
        }
    }
    private var design: Font.Design {
        switch node.fontDesign {
        case "rounded": return .rounded
        case "serif": return .serif
        case "monospaced": return .monospaced
        default: return .default
        }
    }
    private var children: [HTMLAppWidgetElement] { node.children ?? [] }
    private var color: Color { Color(htmlAppHex: node.foregroundHex ?? snapshot.accentHex ?? "#65A9FF") }
    private var label: String {
        switch node.field {
        case "title": return snapshot.title ?? ""
        case "subtitle": return snapshot.subtitle ?? ""
        case "value": return snapshot.value ?? ""
        case "unit": return snapshot.unit ?? ""
        case "footer": return snapshot.footer ?? ""
        case "eyebrow": return snapshot.eyebrow ?? ""
        default: return node.text ?? ""
        }
    }
    var body: some View {
        decorated
    }
    private var decorated: AnyView {
        var view = raw
        if let size = node.fontSize { view = AnyView(view.font(.system(size: CGFloat(size), weight: weight, design: design))) }
        else if node.fontWeight != nil || node.fontDesign != nil { view = AnyView(view.font(.system(.caption, design: design).weight(weight))) }
        view = AnyView(view.lineLimit(node.lineLimit ?? 1)
            .minimumScaleFactor(CGFloat(node.minimumScale ?? 0.5))
            .multilineTextAlignment(textAlignment))
        if let hex = node.foregroundHex { view = AnyView(view.foregroundStyle(Color(htmlAppHex: hex))) }
        view = AnyView(view.padding(CGFloat(node.padding ?? 0)))
        if node.width != nil || node.height != nil {
            view = AnyView(view.frame(width: node.width.map { CGFloat($0) }, height: node.height.map { CGFloat($0) }, alignment: alignment))
        }
        if node.expand == true { view = AnyView(view.frame(maxWidth: .infinity, alignment: alignment)) }
        if let hex = node.borderHex {
            view = AnyView(view.overlay(RoundedRectangle(cornerRadius: CGFloat(node.cornerRadius ?? 0))
                .stroke(Color(htmlAppHex: hex), lineWidth: CGFloat(node.borderWidth ?? 1))))
        }
        if let hex = node.backgroundHex {
            view = AnyView(view.background(RoundedRectangle(cornerRadius: CGFloat(node.cornerRadius ?? 0)).fill(Color(htmlAppHex: hex))))
        }
        if let radius = node.cornerRadius { view = AnyView(view.clipShape(RoundedRectangle(cornerRadius: CGFloat(radius)))) }
        if let opacity = node.opacity { view = AnyView(view.opacity(opacity)) }
        if let label = node.accessibilityLabel { view = AnyView(view.accessibilityLabel(label)) }
        view = AnyView(view.animation(.easeInOut(duration: 0.35), value: node))
        view = AnyView(view.animation(.easeInOut(duration: 0.35), value: snapshot))
        return view
    }
    private var raw: AnyView {
        switch node.type {
        case "row":
            return AnyView(HStack(alignment: vertical, spacing: CGFloat(node.spacing ?? 4)) { childViews })
        case "column":
            return AnyView(VStack(alignment: horizontal, spacing: CGFloat(node.spacing ?? 4)) { childViews })
        case "overlay":
            return AnyView(ZStack(alignment: alignment) { childViews })
        case "timer":
            return AnyView(HTMLAppWidgetTimerText(snapshot: snapshot, date: date, format: node.timeFormat)
                .frame(maxWidth: .infinity, alignment: alignment))
        case "symbol":
            let symbol = node.systemSymbol ?? snapshot.systemSymbol ?? "circle"
            let mode: SymbolRenderingMode = node.symbolRenderingMode == "multicolor" ? .multicolor : node.symbolRenderingMode == "hierarchical" ? .hierarchical : node.symbolRenderingMode == "palette" ? .palette : .monochrome
            return AnyView(Image(systemName: UIImage(systemName: symbol) == nil ? "questionmark.circle" : symbol).symbolRenderingMode(mode))
        case "image":
            let encoded = node.imageBase64 ?? snapshot.imageBase64 ?? ""
            let raw = encoded.components(separatedBy: ",").last ?? encoded
            if let data = Data(base64Encoded: raw), let image = UIImage(data: data), image.size.width <= 4096, image.size.height <= 4096 {
                return AnyView(Image(uiImage: image).resizable().scaledToFit())
            }
            return AnyView(Image(systemName: "photo"))
        case "progress", "ring":
            return AnyView(progress)
        case "lineChart", "barChart", "waveform", "gauge", "segmentedMeter", "route", "path", "gradient":
            return AnyView(HTMLAppRichWidgetElement(node: node, progress: snapshot.progress ?? 0,
                                                   accent: snapshot.accentHex ?? "#65A9FF"))
        case "circle": return AnyView(Circle().fill(color))
        case "rectangle": return AnyView(Rectangle().fill(color))
        case "capsule": return AnyView(Capsule().fill(color))
        case "spacer": return AnyView(Spacer(minLength: 0))
        case "divider": return AnyView(Divider())
        default: return AnyView(Text(label))
        }
    }
    private var childViews: some View {
        ForEach(children.indices, id: \.self) { index in
            HTMLAppWidgetElementView(node: children[index], snapshot: snapshot, date: date)
        }
    }
    @ViewBuilder private var progress: some View {
        if let range = snapshot.nativeTimeInterval, node.progress == nil {
            if node.type == "ring" {
                ProgressView(timerInterval: range, countsDown: snapshot.countsDown) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.circular).tint(color)
            } else {
                ProgressView(timerInterval: range, countsDown: snapshot.countsDown) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear).tint(color)
            }
        } else if node.type == "ring" {
            Gauge(value: min(max(node.progress ?? snapshot.progress ?? 0, 0), 1)) { EmptyView() }
                .gaugeStyle(.accessoryCircularCapacity).tint(color)
        } else {
            ProgressView(value: min(max(node.progress ?? snapshot.progress ?? 0, 0), 1)).tint(color)
        }
    }
}
