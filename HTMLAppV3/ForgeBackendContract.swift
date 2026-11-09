import Foundation

/// Backend completeness is a correctness requirement, independent of optional UI QA.
enum ForgeBackendContract {
    static let instructions = """
    DEPLOYMENT ENVIRONMENT: APNs IS NOT CONFIGURED AND THE OWNER CANNOT SET IT UP.
    Do not require Apple push keys, push.register, backend.subscribe or app.notify as
    the only path for the primary workflow. Use the backend for durable messages/data;
    poll it while the app is foreground, pause polling when hidden, resume and fetch
    missed messages on activation, and deduplicate by cursor/message ID. Show received
    messages in the app and offer a local notification after notification consent.
    Already-known future events can schedule local reminders in advance, without APNs.
    Background refresh is opportunistic, never a guaranteed message delivery channel.
    Do not claim server polling, a widget, a WebSocket or JavaScript can wake a suspended
    or terminated app for instant remote alerts. If this is essential, explain the
    limitation and offer an explicit optional external notification service integration
    only with the user's chosen service, real documented API and required credentials.
    Do not invent a free relay or silently add a paid dependency. Never label an in-app
    poll or local test as a delivered remote push. Still implement the working backend.

    DYNAMIC WIDGET CONTRACT:
    For time-based widgets publish snapshot.timeRange:{startMs,endMs} (absolute Unix
    milliseconds, end strictly after start), plus snapshot.display set to countdown,
    elapsed, remainingProgress or elapsedProgress. Optional timeRange.upcomingLabel,
    inProgressLabel and completedLabel customize generic boundary states. WidgetKit
    renders native timers and progress from these dates without per-second JS.
    remainingProgress empties; elapsedProgress fills. Circular Lock Screen widgets
    use the system circular progress style; Home Screen/rectangular widgets use a
    native bar. Inline widgets show timer text. Do not promise arbitrary live percent
    text or custom animated paths: a formatted percent/progress fraction is static.
    The host schedules start/end timeline entries (iOS controls exact display timing).
    Publish on create/change/delete and activation, not every second. Keep snapshot.value
    as fallback. snapshot.deadlineMs remains supported for countdown-only old apps.
    Use the user's actual model/time zone to compute start/end, including date rollover.
    Local dataBindings and remote JSON bindings support timeRange.startMs/endMs.
    Time progress is not task completion: keep fixed progress for non-time metrics.
    Known future state is a timeline; changing remote data is cached with an honest
    last-updated state and opportunistic refresh. None of these wake arbitrary JS.


    CUSTOM WIDGET DESIGN (schemaVersion 2):
    snapshot.timeFormat: automatic | hoursMinutesSeconds | minutesSeconds |
    hoursMinutes | seconds | minutes | hours. iOS 18+ uses native live selected-unit
    text. On iOS 16/17 seconds-only falls back to a live MM:SS timer; minute/hour
    formats use prepared minute timeline entries with system-controlled scheduling.
    Query capabilities.list().widgetCustomization.liveSelectedTimeUnits, not guesses.
    Formats are localized by iOS; do not promise arbitrary live string templates.
    snapshot.automaticStatus:false preserves your subtitle/footer/unit instead of
    replacing them with the generic timed state. Retain real timeRange dates.

    For completely custom composition, snapshot.content is a native element tree.
    snapshot.familyContent maps family names to alternate trees; selected family wins
    over content. Omit both for legacy templates. Types: row, column, overlay (children),
    text (text or field:title|subtitle|value|unit|footer|eyebrow), timer (timeFormat),
    symbol (systemSymbol,symbolRenderingMode:monochrome|hierarchical|palette|multicolor),
    image (imageBase64 or snapshot.imageBase64), progress, ring, circle, rectangle,
    capsule, spacer, divider. timer/progress/ring use snapshot.timeRange/display;
    progress/ring with explicit progress:0...1 are static instead. Do not preformat
    a live timer as a text node or set a static fraction for live time progress.
    Node styles: alignment:leading|center|trailing; verticalAlignment:top|center|bottom|
    firstTextBaseline (rows); spacing:0...40; padding:0...40; fontSize:8...96;
    fontWeight:regular|medium|semibold|bold|heavy; fontDesign:default|rounded|serif|
    monospaced; lineLimit:1...6; minimumScale:0.3...1; foregroundHex,backgroundHex,
    borderHex,borderWidth:0...12,cornerRadius:0...100,opacity:0...1,width/height:1...600,
    expand:true to fill width,accessibilityLabel. Max96 elements across all trees,
    max nesting depth6; invalid trees are rejected. Nested row/column creates grids;
    overlay composes backgrounds, rings, symbols and labels. Only native layout, not
    HTML/CSS/JS execution in widgets. Colors and rendering remain system-controlled
    on the Lock Screen and tinted Home Screen. Do not assume arbitrary animation.
    Make family-specific designs: accessoryInline is a single short row of text,
    symbol/timer; circular is a centered small overlay with ring + padded column;
    rectangular is compact; Home Screen supports richer trees/images. Avoid large
    fixed widths on Lock Screen. Timers expand horizontally: center their text and
    leave ring insets. Provide accessibilityLabel and sensible scale/line limits.
    Example familyContent.accessoryCircular:
    {type:"overlay",children:[{type:"ring"},{type:"column",padding:10,children:[
      {type:"symbol",systemSymbol:"clock",fontSize:13},
      {type:"timer",timeFormat:"minutesSeconds",fontSize:11,minimumScale:0.5}]}]}.
    Existing widget tap/deep-link configuration still applies to the whole widget;
    use existing item actions in template layouts for multiple tap destinations.

    MANAGED RUNTIME V2 — AUTHORITATIVE BACKEND CAPABILITY:
    HTMLApp can deploy generated Python servers automatically using the owner's saved secret.
    A requested server feature must have real Python, manifest and matching frontend calls.
    Do not replace an external API, cloud storage or multi-user workflow with local storage,
    local notifications, a setup note, placeholder URL, or 'ask an administrator'.
    Backend registration and deployment belong to the native host. No secrets in generated code.
    Bundle transport: inside <htmlapp_code>, put <script type="application/json" id="htmlapp-backend-v2">
    containing {"source":"complete server.py","manifest":{...}}. Escape '<' inside JSON as
    a Unicode escape. Do not emit separate backend artifacts outside the HTML document.
    Use HTMLAppNative.backend.request({path,method,body,session}) for generated routes.
    backend.status() returns linked, sdkVersion, apiBaseURL, canNotify, pushConfigured and state.
    Never gate v2 access on a legacy sendKey. Only if APNs is actually configured, backend.subscribe(session) registers this phone
    for its authenticated resource; unsubscribe(session) removes it. push.register alone does
    not subscribe or deliver anything. Public APIs are deliberate public routes; respect the
    user's authentication requirements while keeping phone registration resource-scoped.
    For an external caller, show the real URL from backend.status().apiBaseURL + route and
    the exact method/body/auth expected by server.py. Never invent an external URL or require
    the VPS provisioning secret or private management key in external integrations.
    Preview is not deployed; show 'Save to activate backend' rather than 'host unsupported'.
    Encryption happens on the client using established cryptography; never upload plaintext
    or decryption passwords. A publishable app key is not private-user authorization.
    Readiness checks are required and must test generated routes, including expected auth failures.
    Preserve the backend bundle and API compatibility during unrelated edits and UI polish.
    """

    static func requiresBackend(request: String, html: String) -> Bool {
        ForgeCapabilityPlan.requiresBackend(request: request, html: html)
    }

    static func issues(request: String, html: String, required: Bool = false) -> [String] {
        guard required || requiresBackend(request: request, html: html) else { return [] }
        do {
            guard let bundle = try HTMLAppRuntimeBundle.extract(html) else {
                return ["Backend required: include the executable v2 Python source and manifest, not a local-only substitute or legacy meta declaration."]
            }
            var result = [String]()
            let frontend = html.replacingOccurrences(of: HTMLAppRuntimeBundle.scriptPattern, with: "", options: [.regularExpression, .caseInsensitive])
            if !frontend.contains("backend.request") && !frontend.contains("backend?.request") {
                result.append("Connect the frontend to the declared server routes using backend.request.")
            }
            let routes = bundle.object["manifest"] as? [String: Any]
            let paths = Set((routes?["routes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String })
            let expression = #"backend\??\.request\s*\(\s*\{[^}]*?path\s*:\s*["']([^"']+)["']"#
            if let regex = try? NSRegularExpression(pattern: expression) {
                for match in regex.matches(in: frontend, range: NSRange(frontend.startIndex..., in: frontend)) {
                    guard let range = Range(match.range(at: 1), in: frontend) else { continue }
                    let path = String(frontend[range]).components(separatedBy: "?")[0]
                    let matched = paths.contains { route in
                        let expected = route.split(separator: "/")
                        let actual = path.split(separator: "/")
                        return expected.count == actual.count && zip(expected, actual).allSatisfy { pair in
                            pair.0 == pair.1 || (pair.0.hasPrefix("{") && pair.0.hasSuffix("}"))
                        }
                    }
                    if !matched {
                        result.append("Frontend route \(path) is absent from the backend manifest.")
                    }
                }
            }
            for placeholder in ["your-relay.example", "your-backend.example", "your-server.example", "https://your-api"] where html.contains(placeholder) {
                result.append("Replace the placeholder backend URL with backend.status().apiBaseURL and a real declared route.")
            }
            return result
        } catch { return ["Repair the runtime bundle: " + error.localizedDescription] }
    }
}

/// Catch explicit requests for a live time widget before accepting a fixed snapshot.
enum ForgeWidgetTimeContract {
    static func issues(request: String, html: String) -> [String] {
        let text = request.lowercased()
        guard text.contains("widget"), html.contains("widgets.configure") else { return [] }
        let progress = text.contains("progress") && ["time", "timer", "duration", "elapsed", "remaining"].contains(where: text.contains)
        let timer = ["countdown", "time remaining", "time left", "elapsed time"].contains(where: text.contains)
        guard progress || timer else { return [] }
        if progress && (!html.contains("timeRange") || (!html.contains("remainingProgress") && !html.contains("elapsedProgress"))) {
            return ["Time-based widget progress must publish snapshot.timeRange with startMs/endMs and display remainingProgress or elapsedProgress, not a fixed percent or progress fraction."]
        }
        if timer && !html.contains("timeRange") && !html.contains("deadlineMs") {
            return ["The live timer widget needs absolute timeRange dates or deadlineMs, not formatted remaining-time snapshot text."]
        }
        return []
    }
}
