import SwiftUI

/// Curated release notes travel with the app, without network access.
/// Add a new entry when shipping another release line; never infer changes
/// from a build number or claim an unavailable remote changelog.
enum HTMLAppReleaseNotes {
    struct Entry: Identifiable {
        let id: String
        let title: String
        let description: String
        let symbol: String
        let tint: Color
    }

    // Compile-time release identity. This is not computed from a possibly
    // stale IPA Info.plist or the GitHub runner's commit count.
    static let compiledVersion = "1.7.0"
    static let compiledBuild = "95"

    static var installedVersion: String { compiledVersion }
    static var installedBuild: String { compiledBuild }
    static var packagedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Missing"
    }
    static var packagedBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Missing"
    }
    static var packagingMatchesCode: Bool {
        packagedVersion == compiledVersion && packagedBuild == compiledBuild
    }

    static func entries(for version: String) -> [Entry] {
        if version == "1.7.0" { return [
            Entry(id: "backend-panel", title: "Connect your apps to a backend", description: "Open Developer → Backend to link a server template, see its details and keys, and manage its saved data.", symbol: "server.rack", tint: .blue),
            Entry(id: "backend-push", title: "Send notifications from a webhook", description: "Link a notification backend and register your phone. Use its send-only key from your website or automation.", symbol: "bell", tint: .purple),
            Entry(id: "backend-private-sharing", title: "Backend access stays private", description: "Nearby transfers leave out backend keys and Python source. Deleting a linked app also queues its backend for deletion.", symbol: "lock.shield", tint: .green)
        ] }

        if version == "1.6.86" { return [
            Entry(id: "smaller-ai-edits", title: "Large icons stay out of AI edits", description: "HTMLApp keeps embedded app icons out of edit requests, leaving more room for your app code. Your saved icon is kept.", symbol: "app", tint: .blue)
        ] }

        if version == "1.6.85" { return [
            Entry(id: "direct-edit-prompt", title: "Edits use your own words", description: "Forge sends your edit as you wrote or spoke it. New app ideas can still be refined before building.", symbol: "pencil", tint: .blue),
            Entry(id: "clean-app-switch", title: "Tabs stay with their app", description: "Opening a different saved app from the Home Screen clears the previous app’s tab bar.", symbol: "square.stack", tint: .green)
        ] }

        if version == "1.6.84" { return [
            Entry(id: "library-voice-launch", title: "Start building from the Library mic", description: "Release the mic to start your app without opening the prompt form. Turn on Show styles for Library voice creation in Settings if you want previews first.", symbol: "sparkles", tint: .purple),
            Entry(id: "whisper-review", title: "Check what Whisper heard", description: "Your words appear briefly after transcription. Tap them to make a correction and send.", symbol: "text.bubble", tint: .blue),
            Entry(id: "mic-audio-guard", title: "Pause music before dictating", description: "If another app is playing audio, HTMLApp asks you to pause it before opening the microphone.", symbol: "pause.circle", tint: .orange)
        ] }

        // Each new release lists only its own changes. 1.6.83 is the one
        // requested exception and also covers the previous three updates.
        if version == "1.6.83" { return [
            Entry(id: "local-ai-chat", title: "Chat with Apple Intelligence", description: "Saved apps can send recent chat messages to Apple Intelligence and display an answer generated on your device. Turn on generated-app AI access in Settings.", symbol: "bubble.left", tint: .blue),
            Entry(id: "style-music", title: "Music while styles are made", description: "Your generation music now plays during style previews. If you leave HTMLApp and the previews finish, you can get a notification.", symbol: "music.note", tint: .purple),
            Entry(id: "builder-guide", title: "A better guide for external AI", description: "The app-building guide now explains local devices, chat, dictation, native tabs and Liquid Glass.", symbol: "book", tint: .green),
            Entry(id: "library-create-mic", title: "Speak an app idea from Library", description: "Drag the Library microphone inward, speak, and release. If style previews are on, Forge shows designs first. If they are off, Forge starts building.", symbol: "sparkles", tint: .purple),
            Entry(id: "finger-tracking-mic", title: "The edit mic follows your finger", description: "Drag the mic in any direction. When you release it, it stretches and springs back as the editor opens. On iOS 26, the glass fits inside the outline and turns a translucent red while recording.", symbol: "mic.fill", tint: .blue),
            Entry(id: "native-glass-mic", title: "The same edit mic in both places", description: "The saved-app mic now matches the tilted mic in Edit with AI. Both use Apple’s Liquid Glass on iOS 26 and later.", symbol: "mic.fill", tint: .blue),
            Entry(id: "native-glass-api", title: "Real Liquid Glass for saved apps", description: "On iOS 26 and later, apps can add a native glass surface to a small area of the screen. The glass lets taps pass through.", symbol: "sparkles", tint: .purple)
        ] }
        if version == "1.6.82" { return [
            Entry(id: "native-glass-mic", title: "The same edit mic in both places", description: "The saved-app mic now matches the tilted mic in Edit with AI. Both use Apple’s Liquid Glass on iOS 26 and later.", symbol: "mic.fill", tint: .blue),
            Entry(id: "native-glass-api", title: "Real Liquid Glass for saved apps", description: "On iOS 26 and later, apps can add a native glass surface to a small area of the screen. The glass lets taps pass through.", symbol: "sparkles", tint: .purple)
        ] }
        if version == "1.6.81" { return [
            Entry(id: "drag-edit-mic", title: "Drag, speak, then release", description: "Drag the edge mic inward, hold it while you speak, and release to start the edit. Long dictation keeps earlier words when Apple Speech starts a new segment.", symbol: "mic.fill", tint: .blue),
            Entry(id: "faster-edit-start", title: "Edits start sooner", description: "Apply Change and voice edits skip the extra planning check for ordinary edits. Full rewrites still ask you first.", symbol: "bolt.fill", tint: .orange)
        ] }
        if version == "1.6.80" || version == "1.6.79" { return [
            Entry(id: "forge-edits", title: "AI edits are easier to follow", description: "Edit summaries tell you what changed in a short sentence. Forge uses the app around your edit to better understand short requests and protect features you want to keep.", symbol: "pencil", tint: .blue),
            Entry(id: "forge-generation", title: "More reliable app generation", description: "Forge catches cut-off answers and incomplete edits before using them. Stopping a request also stops its retries.", symbol: "checkmark.shield", tint: .green),
            Entry(id: "forge-style", title: "More variety in app designs", description: "Forge can try more creative layouts and add motion where it helps. Compare previews with the numbered buttons on the right. The text below the preview is gone.", symbol: "paintpalette", tint: .purple),
            Entry(id: "tab-navigation", title: "Tabs follow the screen", description: "In apps that use the new navigation, opening a screen from a button also highlights its tab. Apps can use any system icon available on your device. Missing icons show an app icon instead of a square.", symbol: "square.grid.2x2", tint: .blue),
            Entry(id: "web-glass", title: "A glass look for app controls", description: "Apps can give toolbars and other controls a see-through, frosted look. The effect respects your Reduce Transparency setting.", symbol: "sparkles", tint: .purple),
            Entry(id: "session-restore", title: "Pick up where you left off", description: "Opening a different app saves the previous app’s screen. When you return, it restores automatically. If you close HTMLApp from the app switcher, the app you had open starts fresh next time.", symbol: "arrow.uturn.backward", tint: .green),
            Entry(id: "speech-engine", title: "Your voice setting works in saved apps", description: "Apps that use dictation follow your choice of Apple Speech or Whisper in Settings. Whisper prepares while you speak, and Forge can retry a failed transcription using the same recording.", symbol: "waveform", tint: .blue),
            Entry(id: "edit-mic", title: "Keep the edit mic within reach", description: "Turn on Show edit microphone at all times in Settings. A small part of the mic stays visible at the edge of your phone screen. Drag it fully inward, speak while holding, then release to edit.", symbol: "mic.fill", tint: .orange),
            Entry(id: "widget-switch", title: "Widgets follow the app you open", description: "When you open an app with widgets, its widgets become the default. The change appears when iOS refreshes them.", symbol: "square.stack", tint: .green),
            Entry(id: "car-launcher", title: "Find recent apps faster in car display", description: "The launcher shows app icons with the most recently opened apps first.", symbol: "car.fill", tint: .orange)
        ] }

        if version == "1.6.78" { return [
            Entry(id: "managed-tab-screens", title: "Screens and tabs stay in sync", description: "Generated apps can use a built-in screen router so opening a tab destination from a button also selects its native tab.", symbol: "rectangle.on.rectangle", tint: .blue)
        ] }

        if version == "1.6.77" || version == "1.6.76" { return [
            Entry(id: "forge-intent", title: "Smarter small edits", description: "Forge ranks specific screen and component matches, avoids accidental Bluetooth matches in ordinary words, and keeps broader context for ambiguous or functional edits.", symbol: "text.magnifyingglass", tint: .blue),
            Entry(id: "forge-reliability", title: "Safer generation and patches", description: "Incomplete provider responses and unfinished patch blocks are rejected. Cancelled requests stop retrying, and visual edits protect existing screens, routes and native integrations.", symbol: "checkmark.shield", tint: .green),
            Entry(id: "forge-native-workflows", title: "More thoughtful app generation", description: "Updated generation guidance emphasizes complete workflows from short prompts, native iOS interactions, keyboard and accessibility behavior, reliable saving and recovery.", symbol: "iphone", tint: .purple)
        ] }
        if version == "1.6.75" { return [
            Entry(id: "safe-background-requests", title: "Background sync now honors network permissions", description: "Scheduled JSON refreshes require saved-app network approval and a separately approved public DNS host. Background requests use the same bounded, no-redirect, public-address-checked HTTPS transport as foreground APIs.", symbol: "lock.shield", tint: .green),
            Entry(id: "silent-push-refresh", title: "Optional APNs-triggered refresh", description: "When HTMLApp is properly signed for APNs and iOS delivers a content-available notification, the host can refresh only due, consented background jobs. Apple controls delivery and no background JavaScript is executed.", symbol: "arrow.clockwise.icloud", tint: .blue),
            Entry(id: "native-contract-refresh", title: "Stricter background API contracts", description: "The generated native bridge now requires the background job ID, public HTTPS URL and storage key and declares its network permission, helping Forge generate safer refresh behavior.", symbol: "checkmark.shield", tint: .purple)
        ] }
        if version == "1.6.74" { return [
            Entry(id: "forward-geocoding", title: "Search addresses with Apple's geocoder", description: "Saved apps can look up approximate coordinates for a user-entered address or place through HTMLAppNative.location.geocode(). This needs location permission but does not request the device's GPS position.", symbol: "mappin.and.ellipse", tint: .blue),
            Entry(id: "offline-distance", title: "Calculate distance without GPS", description: "HTMLAppNative.location.distance() computes straight-line great-circle distance between two supplied coordinate pairs entirely offline, without location permission.", symbol: "point.topleft.down.curvedto.point.bottomright.up", tint: .green),
            Entry(id: "network-path-status", title: "Wi-Fi and cellular connection awareness", description: "HTMLAppNative.network.status() provides passive iOS network-path state and sends change events, allowing saved apps to display offline and constrained-network conditions without requesting a domain.", symbol: "wifi", tint: .purple),
            Entry(id: "complete-typed-contract", title: "Native API signatures stay in sync", description: "The new methods are part of the canonical generated native bridge, TypeScript contract, Forge capability planning and automated argument tests.", symbol: "checkmark.shield", tint: .orange)
        ] }
        if version == "1.6.73" { return [
            Entry(id: "verified-mobile-look-previews", title: "No more unchecked tiny preview sketches", description: "Forge now refuses to approve a style if the mobile WebView times out or cannot be measured. Its layout checker always evaluates a real 320-point phone viewport and regenerates layouts that are too wide or unreadable.", symbol: "iphone.gen3.radiowaves.left.and.right", tint: .blue),
            Entry(id: "portable-backup-regression-tests", title: "ZIP import compatibility checks", description: "Backups now have automated tests against normal and streaming Deflate ZIPs, bad CRCs, duplicate entries, excessive file counts, unsafe paths and exports.", symbol: "archivebox.fill", tint: .green)
        ] }
        if version == "1.6.72" { return [
            Entry(id: "zip-fixture-validation", title: "More reliable HTMLApp backups", description: "ZIP handling is now isolated in a small tested module. Automated macOS tests check compressed archives, data descriptors, integrity failures, duplicate entries, path traversal and backup round trips.", symbol: "archivebox.fill", tint: .green),
            Entry(id: "simulator-import-tests", title: "Import tested across phone and tablet", description: "The continuous UI test matrix exercises the root Import screen on both iPhone and iPad simulators. Actual Files and Share Sheet handoff still depends on iOS delivery and signing.", symbol: "iphone.gen3", tint: .purple)
        ] }
        if version == "1.6.71" { return [
            Entry(id: "typed-forge-contract", title: "Forge knows the exact native APIs", description: "Forge now includes the schema-generated TypeScript native contract in its generation and editing prompts, helping prevent invented device methods and incorrect argument shapes.", symbol: "curlybraces.square", tint: .blue),
            Entry(id: "planning-cache", title: "Less repeated planning work", description: "Retrying an identical app idea can reuse an in-memory planning result from the prior twelve minutes, avoiding unnecessary repeated provider calls without saving prompts to disk.", symbol: "bolt", tint: .green),
            Entry(id: "stage-cost-estimates", title: "Optional AI work cost estimates", description: "Advanced AI Settings now lets you enter an output-token price, and the Forge stage timeline shows a clearly labeled approximate output-only cost. Estimates are not actual bills and exclude other token charges.", symbol: "chart.bar", tint: .purple),
            Entry(id: "bridge-linting", title: "Smarter native bridge checks", description: "Forge also checks literal native RPC method names against the generated registry while recognizing supported higher-level SDK helpers.", symbol: "checkmark.shield", tint: .orange)
        ] }
        if version == "1.6.70" { return [
            Entry(id: "native-list-ui", title: "Native lists and sheets for generated apps", description: "Generated HTML apps can now present genuine UIKit list sheets with accessible rows, selected-item results and native sheet transitions instead of relying only on web-styled dialogs.", symbol: "list.bullet.rectangle.portrait", tint: .blue),
            Entry(id: "native-pull-refresh", title: "Pull to refresh native lists", description: "Optional native pull-to-refresh emits an event to the saved app, which can publish updated rows using HTMLAppNative.ui.listUpdate(). Lists are foreground-only and isolated per saved app.", symbol: "arrow.clockwise", tint: .green),
            Entry(id: "private-vector-search", title: "On-device semantic search", description: "App-private SQLite documents can now be searched by semantic similarity using installed Apple NaturalLanguage sentence embeddings, with no cloud service required.", symbol: "brain", tint: .purple)
        ] }
        if version == "1.6.69" { return [
            Entry(id: "local-vector-search", title: "Private semantic document search", description: "Saved HTML apps can search their own SQLite notes by meaning using Apple's on-device sentence embeddings. The indexed vectors remain on the device and are updated when records change.", symbol: "brain", tint: .purple),
            Entry(id: "fts-vector-fallback", title: "Search that respects device capability", description: "Semantic search reports when a device lacks an embedding model instead of using cloud AI silently. Existing exact and full-text SQLite search remain available as fallbacks.", symbol: "text.magnifyingglass", tint: .blue),
            Entry(id: "forge-preview-verification", title: "More readable generated style previews", description: "Forge now checks real WebKit layout geometry for overflow or unreadably tiny text before offering a look, and retries when the sketch is broken.", symbol: "eye", tint: .green)
        ] }
        if version == "1.6.68" { return [
            Entry(id: "style-runtime-verifier", title: "Bad style sketches now get repaired", description: "Forge tests generated style previews in a real offscreen 320-point WebKit viewport. Offscreen content or unreadably small text triggers another design attempt before the look can be offered.", symbol: "eye", tint: .purple),
            Entry(id: "simulator-ui-qa", title: "Simulator import tests", description: "A new simulator UI test target exercises HTMLApp launch, a staged external HTML open, and a Share-extension inbox import on both iPhone and iPad. Tests are available in a dedicated GitHub Actions workflow.", symbol: "iphone", tint: .blue),
            Entry(id: "native-capability-progress", title: "Continued native improvements", description: "Saved apps now support AI tool conversations, live token streaming, structured on-device model responses, approved cloud fallback, and a Share-sheet import inbox.", symbol: "sparkles", tint: .green)
        ] }
        if version == "1.6.67" { return [
            Entry(id: "on-device-structured-output", title: "Reliable on-device structured answers", description: "On iOS 26 with Foundation Models, saved apps can request typed answer, summary and confidence fields using Apple's native guided generation instead of relying on unvalidated text JSON.", symbol: "curlybraces", tint: .blue),
            Entry(id: "cloud-fallback-opt-in", title: "Optional, clearly approved cloud fallback", description: "If the on-device model cannot answer, saved apps can request a one-time fallback to the configured cloud provider. HTMLApp asks for explicit confirmation before sending the current prompt.", symbol: "cloud", tint: .purple),
            Entry(id: "native-ai-metadata", title: "Documented local AI limits", description: "The bridge's contract now validates local AI inputs and documents when answers stay on-device versus when a user-confirmed fallback uses a cloud provider.", symbol: "checkmark.shield", tint: .green)
        ] }
        if version == "1.6.66" { return [
            Entry(id: "ios-share-extension", title: "Share HTML straight into HTMLApp", description: "A new iOS Share extension receives HTML file attachments into a secure shared inbox and attempts to open the app. If iOS does not allow automatic launch, the file is ready to import the next time you open HTMLApp.", symbol: "square.and.arrow.up", tint: .blue),
            Entry(id: "file-import-resume", title: "Import requests survive app switching", description: "HTMLApp now checks the shared inbox when it opens or returns to the foreground, presenting the New App or Update Existing import destination for staged documents.", symbol: "doc.badge.arrow.up", tint: .green),
            Entry(id: "live-ai-responses", title: "Watch saved-app AI answer live", description: "Live token streaming and bounded, confirmation-gated AI conversations are now available for generated HTML apps with authorized AI access.", symbol: "waveform", tint: .purple)
        ] }
        if version == "1.6.65" { return [
            Entry(id: "live-ai-streaming", title: "Live AI responses in saved apps", description: "Generated apps can now receive live provider tokens through HTMLAppNative.ai.stream(), display them as they arrive and cancel with AbortSignal. Streams stay inside the saved app's permitted foreground AI session.", symbol: "text.bubble", tint: .blue),
            Entry(id: "in-app-ai-tools", title: "AI can ask to use native tools", description: "Short, in-memory AI conversations can call selected calendars, reminders, health, location and saved-document methods with fresh permission confirmation before sensitive data goes to the provider.", symbol: "sparkles.rectangle.stack", tint: .purple),
            Entry(id: "cancelled-ai-requests", title: "Safer cancellation and request limits", description: "Foreground AI streaming follows the existing per-app permission, request budget, response-size limits and request cancellation, with no promises of background streaming.", symbol: "hand.raised", tint: .green)
        ] }
        if version == "1.6.64" { return [
            Entry(id: "tool-calling-ai-sessions", title: "AI sessions with confirmed native tools", description: "Saved apps can now create short AI conversations that request selected calendar, reminders, health, battery, location, and private document tools. Every sensitive tool call requires a new user confirmation before private results can reach the AI provider.", symbol: "sparkles.rectangle.stack", tint: .blue),
            Entry(id: "ai-private-conversation-memory", title: "Private, short-lived AI conversation context", description: "Each in-app AI session retains its recent messages only in the open WebView. Sessions include explicit clear and cancellation support and do not persist secrets or conversation history.", symbol: "bubble.left.and.bubble.right", tint: .purple),
            Entry(id: "on-device-full-text-search", title: "Search locally saved documents", description: "Generated apps can search their own SQLite documents using indexed token search or the original substring search without sharing data with outside services.", symbol: "text.magnifyingglass", tint: .green)
        ] }
        if version == "1.6.63" { return [
            Entry(id: "sqlite-fts", title: "Fast on-device full-text search", description: "Saved HTML apps can search stored JSON documents with token-ranked SQLite FTS5 using HTMLAppNative.db.searchFullText(). Indexing is local, created on demand, and updates with documents.", symbol: "text.magnifyingglass", tint: .green),
            Entry(id: "files-and-previews", title: "Files import and look previews improved", description: "Opening or sharing an HTML document now queues the root Import screen, while Forge's style previews use full-width mobile layouts instead of squeezed side-by-side views.", symbol: "rectangle.portrait", tint: .purple),
            Entry(id: "network-and-backup", title: "Safer networking and backup files", description: "Native HTTPS checks nonpublic addresses and ZIP import validates checksums, sizes, and ordinary Deflate archives while preserving cache paths.", symbol: "lock.shield", tint: .blue)
        ] }
        if version == "1.6.62" { return [
            Entry(id: "root-import-ui", title: "Files and shared HTML now open Import", description: "Incoming HTML files open the import destination screen from the app root, including cold launches and files shared from Files. The app also recognizes the .htmk file extension.", symbol: "doc.badge.arrow.up", tint: .green),
            Entry(id: "full-width-style-sketches", title: "Readable, full-width Forge previews", description: "Generated style mockups now use the full screen width with look choices below, correct mobile viewport scaling and responsive layout guidance, reducing tiny or clipped previews.", symbol: "rectangle.portrait", tint: .purple),
            Entry(id: "safer-native-networking", title: "Safer native HTTPS requests", description: "Native requests now screen DNS answers against private and local addresses and verify connection-address metadata before returning a response, with blocked redirects and stricter host-name checks.", symbol: "network.badge.shield.half.filled", tint: .blue),
            Entry(id: "robust-zip-import", title: "More compatible, safer backups", description: "Backup import now accepts standard Deflate ZIP archives, checks file integrity, rejects duplicate paths, limits archive size and handles ZIP data descriptors. Export preserves nested cache paths correctly.", symbol: "archivebox", tint: .orange)
        ] }
        if version == "1.6.61" { return [
            Entry(id: "whisper-auto-retry-status", title: "See microphone and transcription retries", description: "The floating Forge microphone now displays clear retrying status while it reconnects to the microphone or reuses captured audio to retry Whisper transcription, without blocking your drag gesture.", symbol: "mic.fill", tint: .blue),
            Entry(id: "visual-redesign-recovery", title: "Better-looking popup edits", description: "Forge detects when a redesign misaligns labels and fields, requests a corrected layout, and respects later fixes that replace the old CSS grid.", symbol: "paintbrush.pointed", tint: .pink),
            Entry(id: "keep-spoken-changes", title: "Your spoken edits stay recoverable", description: "Whisper automatically retries the original recorded audio, lets you retry the saved recording after a decoding failure, and routes recovered words back to the intended app edit.", symbol: "waveform", tint: .green)
        ] }
        if version == "1.6.60" { return [
            Entry(id: "reliable-visual-form-fixes", title: "More reliable popup redesigns", description: "Forge now recognizes when a corrected layout replaces an older bad grid rule, so valid repairs are accepted without breaking label and input alignment.", symbol: "paintbrush.pointed", tint: .pink),
            Entry(id: "whisper-rescue", title: "Retry speech without repeating it", description: "Whisper keeps the captured audio through multiple automatic transcription retries and provides a Retry using saved audio option if needed. Recovered speech still applies to the original edit or style-feedback action.", symbol: "waveform", tint: .blue),
            Entry(id: "visual-edit-recovery", title: "AI edits catch broken dialog layouts", description: "Visual changes that split labels from fields or produce no actual source change trigger a corrective patch attempt rather than being reported as finished.", symbol: "rectangle.on.rectangle", tint: .indigo)
        ] }
        if version == "1.6.59" { return [
            Entry(id: "visual-form-redesign-repair", title: "Visual edits respect your forms", description: "Forge now detects broken multi-column layouts that split labels away from their fields, then retries the visual patch from the original app. It preserves existing data and behavior instead of approving a visually broken change.", symbol: "paintbrush.pointed", tint: .pink),
            Entry(id: "spoken-edit-rescue", title: "Voice edits recover without repeating speech", description: "Whisper keeps your recorded audio through automatic transcription retries, can reload its speech model, and offers Retry using saved audio if decoding still fails. Successful retries return to the original edit or style feedback action.", symbol: "waveform", tint: .blue),
            Entry(id: "microphone-start-retries", title: "Smarter microphone retries", description: "Transient microphone startup problems show a retrying status while HTMLApp attempts to start recording again.", symbol: "mic.fill", tint: .green)
        ] }
        if version == "1.6.58" { return [
            Entry(id: "popup-redesign-guard", title: "Cleaner, more reliable AI edits", description: "Forge now checks visual edits for broken form layouts, duplicate dialog copy, and unchanged output. When a popup redesign misplaces labels and fields, Forge asks the editor to repair the patch instead of accepting the broken result.", symbol: "paintbrush.pointed", tint: .pink),
            Entry(id: "whisper-recording-retry", title: "Whisper retries without making you repeat yourself", description: "If Whisper cannot decode a recorded voice edit, it retries the same saved audio automatically and can reload its model. A Retry using saved audio action remains available if all attempts fail.", symbol: "waveform", tint: .blue),
            Entry(id: "whisper-microphone-recovery", title: "Clearer microphone recovery", description: "Transient microphone-start failures now report that recording is retrying, while the microphone only indicates active capture once recording actually starts.", symbol: "mic.fill", tint: .green)
        ] }
        if version == "1.6.57" { return [
            Entry(id: "reliable-external-html-import", title: "HTML files now open into Import reliably", description: "Opening an HTML file from Files or sharing one to HTMLApp now stages the document safely and keeps the import request until the Library is ready, including cold launches and the What's New screen.", symbol: "doc.badge.arrow.up", tint: .green),
            Entry(id: "simpler-settings", title: "Simpler Settings", description: "Everyday settings are grouped around AI & Voice, Library, iCloud, Manage, and Help, while developer and rarely used controls are tucked into Advanced Settings.", symbol: "gearshape.2", tint: .blue),
            Entry(id: "live-apple-speech-captions", title: "Watch Apple Speech appear live", description: "During Forge edits, dragging the floating microphone on-screen now shows the words you are speaking in large live captions while Apple Speech recognizes them.", symbol: "waveform", tint: .purple),
            Entry(id: "native-audio-video-color", title: "More native media and UI capabilities", description: "Saved apps can use permission-scoped native audio recording and playback, foreground camera video capture, and the native iOS color picker through the documented bridge.", symbol: "camera.metering.center.weighted", tint: .orange),
            Entry(id: "forge-manifest-planning", title: "Smarter Forge editing contracts", description: "Forge now keeps versioned app architecture metadata and uses semantic capability planning to preserve storage, screens, routes, native features, and regression requirements across edits.", symbol: "point.3.connected.trianglepath.dotted", tint: .indigo),
            Entry(id: "generated-native-bridge-contract", title: "One native bridge contract", description: "The native RPC surface now comes from one generated schema that drives Swift registration, argument checks, API documentation, TypeScript definitions, and consistency tests.", symbol: "arrow.triangle.branch", tint: .teal)
        ] }
        if version == "1.6.56" { return [
            Entry(id: "experimental-offline-snapshots", title: "Experimental offline app snapshots", description: "Saved HTML apps now collect eligible external GET resources while you use them and refresh their offline snapshot every third opening. When your device is offline, HTMLApp can use those saved resources and clearly tells you that an experimental offline copy is active.", symbol: "arrow.down.circle", tint: .blue),
            Entry(id: "state-continuity", title: "Pick up where you left off", description: "HTMLApp now checkpoints the live state of saved apps, including the rendered page, scroll positions, typed form values, editable content, local and session storage, canvas pixels, focused controls, and media position. Switching back during the same HTMLApp session restores automatically; after a later cold launch, HTMLApp asks before restoring.", symbol: "rectangle.stack.badge.play", tint: .purple),
            Entry(id: "instant-url-app-switch", title: "Faster app-to-app URL switching", description: "htmlapp://open links now save the current app state and switch directly to the requested saved app, instead of stopping on the normal app-switch confirmation.", symbol: "arrow.left.arrow.right", tint: .green),
            Entry(id: "reliable-first-three-styles", title: "More reliable first three AI looks", description: "Forge again uses the structured Editorial, Workbench, and Playful directions for the first three generated previews, improving consistency while keeping additional style generations freeform.", symbol: "paintpalette.fill", tint: .purple),
            Entry(id: "automatic-three-previews", title: "First three previews generate automatically", description: "Starting a new Forge app now automatically creates the first three style previews so you can compare directions before the full app is built.", symbol: "sparkles.rectangle.stack", tint: .blue),
            Entry(id: "subscription-ai-skill", title: "Build with a subscription AI", description: "AI & Creation includes a shareable HTMLApp skill file that explains HTMLApp capabilities, native integrations, offline limits, and how an external subscription AI can return complete HTML apps without configuring an API key inside HTMLApp.", symbol: "doc.text", tint: .indigo),
            Entry(id: "hosted-api-import-guidance", title: "Smarter hosted HTML importing", description: "When an imported HTML file depends on root-relative server APIs such as /api/build, HTMLApp now explains why an offline file cannot contain the backend and offers the hosted Website Import path instead of silently treating the API URL like a static asset.", symbol: "network", tint: .orange),
            Entry(id: "whisper-mic-reliability", title: "Clearer, more reliable dictation", description: "Offline Whisper recording retries transient microphone start failures automatically. The mic turns red only while recording and grows while held so its state stays visible under your finger.", symbol: "mic.fill", tint: .red)
        ] }
        if version == "1.6.54" { return [
            Entry(id: "experimental-offline-snapshots", title: "Experimental offline resource snapshots", description: "Saved apps refresh external GET resources every third opening and collect loaded resources during use. Cached copies activate only while offline and show a warning when used.", symbol: "arrow.down.circle", tint: .blue),
            Entry(id: "live-app-continuity", title: "Live app state continuity", description: "HTMLApp preserves scroll position, typed controls, web storage and the current rendered HTML while switching apps, with a restore choice after a later cold launch.", symbol: "rectangle.stack.badge.play", tint: .purple),
            Entry(id: "instant-url-switch", title: "Instant URL-scheme switching", description: "htmlapp://open links now checkpoint the current app and switch directly to the requested saved app.", symbol: "arrow.left.arrow.right", tint: .green)
        ] }
        if version == "1.6.53" { return [
            Entry(id: "style-reliability", title: "Reliable first three Forge looks", description: "Restored the structured first-three style system for more consistent app quality, while keeping additional looks freeform.", symbol: "paintpalette.fill", tint: .purple),
            Entry(id: "auto-first-three", title: "Three previews automatically", description: "New app generation now always starts by creating the first three style previews automatically.", symbol: "sparkles.rectangle.stack", tint: .blue)
        ] }
        if version == "1.6.52" { return [
            Entry(id: "dynamic-version-invariant", title: "Release test fix", description: "Source invariants now validate the current compiled version dynamically instead of failing after every version bump.", symbol: "checkmark.seal", tint: .green)
        ] }
        if version == "1.6.51" { return [
            Entry(id: "runner-invariants", title: "Build workflow compatibility fix", description: "Updated build source checks for selectable Intel and Apple Silicon macOS runners while retaining the Xcode 26 compatibility requirement.", symbol: "checkmark.shield", tint: .green)
        ] }
        if version == "1.6.50" { return [
            Entry(id: "runner-selector", title: "Selectable IPA build runner", description: "The manual GitHub Actions IPA workflow offers Intel macOS 26 by default, Apple Silicon macOS 26, and Intel macOS 15 to work around runner queue delays.", symbol: "desktopcomputer", tint: .blue)
        ] }
        if version == "1.6.49" { return [
            Entry(id: "subscription-ai-skill", title: "Shareable AI app-building skill", description: "AI & Creation now includes a downloadable skill explaining how a subscription AI assistant can build HTMLApp-compatible apps without an API key.", symbol: "doc.text", tint: .blue),
            Entry(id: "server-html-import", title: "Safer hosted HTML importing", description: "When an HTML file depends on server-side API routes, HTMLApp explains why offline imports cannot run the server and offers Website Import.", symbol: "network", tint: .orange),
            Entry(id: "html-open", title: "Open HTML files in HTMLApp", description: "HTMLApp remains registered as an HTML document handler for iOS Open In and Files.", symbol: "doc.badge.arrow.up", tint: .green)
        ] }
        if version == "1.6.47" { return [
            Entry(id: "car-display", title: "Car display mode", description: "A compact app launcher, visible Apps exit, safe display bounds and adaptive HTML runtime for setups that already launch HTMLApp on a car screen. Enable Car display in the Library menu when your mirroring tool reports an iPhone screen. This is compatibility mode, not Apple's native CarPlay templates.", symbol: "car.fill", tint: .blue),
            Entry(id: "free-styles", title: "More creative looks", description: "Modern/professional, technical/detailed and kiddy/easy-to-use are broad directions. AI chooses the composition freely. Look choices scroll vertically above the selection controls.", symbol: "paintpalette", tint: .orange)
        ] }
        if version == "1.6.46" { return [
            Entry(id: "whisper-retry", title: "Reliable Whisper microphone", description: "Transient microphone startup failures retry automatically while the user keeps holding, without another manual attempt.", symbol: "mic", tint: .blue),
            Entry(id: "mic-recording-status", title: "Clear recording indicator", description: "The microphone turns red only after recording begins, and enlarges while held to make its state more visible.", symbol: "waveform", tint: .orange)
        ] }
        if version == "1.6.45" { return [
            Entry(id: "forge-planner", title: "Smarter Forge planning", description: "Provider-gated creative sampling and planner-specific reasoning improve design planning without changing reliable coding defaults.", symbol: "sparkles", tint: .blue),
            Entry(id: "taste-memory", title: "Optional visual taste memory", description: "Learn small style preferences from selected designs and edits when enabled, with a clear settings switch and reset option.", symbol: "paintpalette", tint: .purple),
            Entry(id: "health-history", title: "HealthKit date ranges", description: "Generated apps can request permission to inspect bounded HealthKit history with accurate missing-data states.", symbol: "heart.text.square", tint: .red),
            Entry(id: "nfc-writing", title: "NFC text writing", description: "User-confirmed writes to compatible NDEF tags now include capacity and writable-status checks.", symbol: "wave.3.right", tint: .orange),
            Entry(id: "native-media", title: "Native document and image tools", description: "VisionKit scanning, PDF page/text inspection and file-backed Core Image filters add media functions without large WebKit data messages.", symbol: "doc.viewfinder", tint: .blue),
            Entry(id: "bluetooth-gatt", title: "Bluetooth GATT controls", description: "Bounded read, confirmed write and foreground notification subscriptions for discovered BLE devices, with app-exit cleanup.", symbol: "dot.radiowaves.left.and.right", tint: .cyan),
            Entry(id: "core-haptics", title: "Custom haptics", description: "Generated apps can play bounded Core Haptics patterns on supported devices.", symbol: "hand.tap", tint: .indigo),
            Entry(id: "offline-app-ai", title: "On-device AI for saved apps", description: "Eligible iOS 26 devices can grant permission for short local Foundation Models text and JSON responses without cloud API requests.", symbol: "apple.intelligence", tint: .purple),
            Entry(id: "gamepads-pencil", title: "Gamepads and drawing", description: "Generated apps can listen to foreground game controller events and open a native PencilKit canvas with sandboxed image output.", symbol: "gamecontroller", tint: .green)
        ] }
        if version == "1.6.44" { return [Entry(id: "forge-voice-bridge", title: "Smarter Forge instructions and voice", description: "Reordered stable AI capability instructions for provider prompt caching, added punctuation and app vocabulary to voice dictation, and expanded native bridge argument checks.", symbol: "sparkles", tint: .blue)] }
        if version == "1.6.43" { return [Entry(id: "photo-bridge-js-fix", title: "Photo bridge build fix", description: "Fixed injected JavaScript syntax in the photo importer and made bridge script tests work without a browser fetch implementation.", symbol: "checkmark.shield", tint: .green)] }
        if version == "1.6.42" { return [Entry(id: "photos-import-reliability", title: "Reliable multi-photo imports", description: "Photo import now transfers originals to generated apps in bounded WebKit chunks and prefers native file representations without unnecessary conversion. Large selections no longer require one enormous bridge response.", symbol: "photo.on.rectangle", tint: .blue)] }
        if version == "1.6.41" { return [Entry(id: "photo-picker-resilience", title: "Reliable bulk photo import", description: "Native photo picks now stage files without blocking the UI and load originals on demand, preventing oversized selection callbacks.", symbol: "photo.on.rectangle.angled", tint: .blue)] }
        if version == "1.6.40" { return [Entry(id: "road-throttle", title: "Road lookup resilience", description: "Road speed lookups now return an explicit cooling-down status rather than immediate failures on repeated GPS fixes, and favor nearby roads with speed tags.", symbol: "road.lanes", tint: .blue)] }
        if version == "1.6.39" { return [Entry(id: "road-data-reliability", title: "Road data diagnostics", description: "Improved mapped road lookup failure reporting and reduced throttling after provider outages. Each new source update now increments the release identity.", symbol: "road.lanes", tint: .blue)] }
        if version == "1.6.38" { return [Entry(id: "spotlight", title: "Spotlight indexing", description: "Saved apps can request permission to index, remove, and clear their own searchable titles and summaries.", symbol: "magnifyingglass", tint: .blue)] }
        if version == "1.6.37" { return [Entry(id: "db-search-shortcuts", title: "Search documents and run Shortcuts actions", description: "Saved apps can search their local documents and consume pending named actions from Siri Shortcuts.", symbol: "magnifyingglass", tint: .blue)] }
        if version == "1.6.36" { return [Entry(id: "portable-db-shortcuts", title: "Portable app data and Shortcuts", description: "SQLite document snapshots can be bundled with portable app data, and Shortcuts can request a named saved-app action.", symbol: "square.and.arrow.up", tint: .blue)] }
        if version == "1.6.35" { return [Entry(id: "sqlite-docs", title: "Local document database", description: "Saved apps can now store, retrieve, list, count, and delete JSON documents in an isolated SQLite database.", symbol: "externaldrive", tint: .blue)] }
        if version == "1.6.34" { return [Entry(id: "vision-tools", title: "On-device image analysis", description: "Saved HTML apps can recognize text and barcodes, classify images, and detect face rectangles using Apple Vision.", symbol: "viewfinder", tint: .blue)] }
        if version == "1.6.33" { return [Entry(id: "language-tools", title: "On-device language tools", description: "Saved HTML apps can detect languages, tokenize text, analyze sentiment and extract named entities using Apple NaturalLanguage.", symbol: "text.book.closed", tint: .blue)] }
        if version == "1.6.32" { return [Entry(id: "ai-bridge", title: "AI in saved apps", description: "Opt-in per-app AI completion and classification with permission checks and request limits. Experimental compact-output preference added.", symbol: "sparkles", tint: .blue)] }
        if version == "1.6.31" { return [
            Entry(id: "location-address-road", title: "Street addresses and road data", description: "Saved apps can resolve approximate street addresses via Apple geocoding and, with separate consent, request optional OpenStreetMap road speed tags. Unavailable data is never guessed.", symbol: "mappin.and.ellipse", tint: .blue),
            Entry(id: "offline-forge", title: "Offline Forge (experimental)", description: "Eligible iOS 26 devices can use on-device Apple Intelligence for small app generation and editing after a clear effort-and-battery warning.", symbol: "wifi.slash", tint: .indigo),
            Entry(id: "storage-write-safety", title: "Safer portable storage", description: "App data writes now report disk errors instead of falsely succeeding; clearing data produces an explicit iCloud-syncable empty state.", symbol: "internaldrive", tint: .green),
            Entry(id: "storage-developer", title: "App storage inspection (experimental)", description: "The app permissions screen now offers a developer storage inspector with portable data and SQLite document removal warnings.", symbol: "externaldrive", tint: .orange),
            Entry(id: "qa-reliability", title: "AI and QA reliability fixes", description: "Improved provider endpoint normalization, native request timeouts, offscreen touch tests, and missing Health data reporting.", symbol: "checkmark.shield", tint: .green),
            Entry(id: "health-nfc-map", title: "Health, NFC and native maps (experimental)", description: "Saved apps can request read-only daily Health totals, foreground NFC NDEF scans, and a native map modal. Supported devices and signing entitlements are required.", symbol: "heart.text.square", tint: .red),
            Entry(id: "speech-aliases", title: "Speech recognition API compatibility", description: "Saved HTML apps can call speech.recognize and speech.stopRecognizing through the existing permission-controlled foreground transcription engine.", symbol: "waveform", tint: .blue),
            Entry(id: "bridge-lint", title: "Generated app API checks", description: "Runtime verification now reports unsupported native bridge method calls and Web Bluetooth requestDevice usage.", symbol: "checkmark.shield", tint: .orange),
            Entry(id: "native-routing", title: "Native bridge reliability", description: "Corrected duplicate Vision dispatch patterns and added source regression checks.", symbol: "checkmark.shield", tint: .green),
            Entry(id: "adaptive-fade", title: "Adaptive shake exit", description: "The exit fade uses the last resting phone orientation sampled every three seconds; the torch flash uses a gentler intensity.", symbol: "iphone.radiowaves.left.and.right", tint: .blue)
        ] }
        if version == "1.6.30" { return [
            Entry(id: "capability-lookup", title: "On-demand native capability research", description: "Forge can request the complete HTMLApp capability catalog or focused sections such as Bluetooth, widgets, tabs, and device information before generating or editing apps.", symbol: "books.vertical", tint: .blue)
        ] }
        if version == "1.6.29" { return [
            Entry(id: "motion-settings", title: "Custom motion settings", description: "Set the shake time and, in Developer Mode, the fade disappearance angle. Settings displays the selected values.", symbol: "slider.horizontal.3", tint: .blue)
        ] }
        if version == "1.6.28" { return [
            Entry(id: "shake-completion", title: "More reliable face-down shake", description: "Shake progress now accumulates across natural motion impulses instead of requiring uninterrupted acceleration, allowing the exit animation and flashlight cue to trigger.", symbol: "iphone.radiowaves.left.and.right", tint: .blue)
        ] }
        if version == "1.6.27" { return [
            Entry(id: "shake-regression", title: "Shake exit build validation", description: "Regression tests now protect the new fade and flashlight exit flow instead of requiring the removed legacy gesture handler.", symbol: "checkmark.shield", tint: .blue)
        ] }
        if version == "1.6.26" { return [
            Entry(id: "tab-ci", title: "Build validation for native tabs", description: "Updated the source regression check to require tab bars to remain inside their HTML app instead of appearing in editing screens.", symbol: "checkmark.shield", tint: .blue)
        ] }
        if version == "1.6.25" { return [
            Entry(id: "native-tab-isolation", title: "Native tabs stay inside apps", description: "The real native tab bar no longer mounts onto the global app screen while editing.", symbol: "rectangle.bottomthird.inset.filled", tint: .blue),
            Entry(id: "shake-transition", title: "Shake exit transition improvements", description: "A dedicated overlay window keeps the black-and-blurred fade visible while returning to the Library.", symbol: "iphone.radiowaves.left.and.right", tint: .purple),
            Entry(id: "torch", title: "Exit flashlight cue", description: "The shake-exit flashlight now targets the rear torch for a short pulse after closing an HTML app.", symbol: "flashlight.on.fill", tint: .orange)
        ] }
        if version == "1.6.24" { return [
            Entry(id: "music-source", title: "Two ways to add generation music", description: "Switch between picking an audio file from Files and downloading audio from a direct HTTPS URL. Your previous audio URL is preserved.", symbol: "music.note.list", tint: .purple),
            Entry(id: "previous-release", title: "Recent HTMLApp improvements", description: "Includes the updated face-down shake exit, AI generation controls, photo compatibility, and improved app sharing.", symbol: "sparkles", tint: .blue)
        ] }
        if version == "1.6.23" { return [
            Entry(id: "shake-exit", title: "Face-down shake exit", description: "Shake a face-down iPhone to close the running HTML app, with a flashlight cue and a black-and-blurred screen that fades as you rotate it.", symbol: "iphone.radiowaves.left.and.right", tint: .blue),
            Entry(id: "photo-compat", title: "Photo picker compatibility", description: "Selected images are easier for both new and older HTML apps to display.", symbol: "photo.on.rectangle", tint: .green),
            Entry(id: "music-files", title: "Choose generation music from Files", description: "Pick a local audio track instead of entering a URL, with clearer guidance for background generation.", symbol: "music.note", tint: .purple),
            Entry(id: "forge-controls", title: "More AI generation controls", description: "Add three original AI looks, speed up a run with Hurry Up!, undo unsaved edits and approve rare full rewrites.", symbol: "sparkles", tint: .orange),
            Entry(id: "island", title: "Generation progress in Dynamic Island", description: "See the active AI phase and progress while a Live Activity is running.", symbol: "circle.dotted.circle", tint: .mint),
            Entry(id: "sharing", title: "Organized app actions", description: "App menus group everyday actions, sharing and developer tools. Raw code exports use HTML files.", symbol: "square.and.arrow.up", tint: .indigo)
        ] }
        if version == "1.6.22" { return [
            Entry(id: "audio", title: "More dependable generation audio", description: "Music URL prefetch and safer dictation teardown reduce interruptions. Background continuity remains best-effort and depends on iOS scheduling.", symbol: "waveform", tint: .purple),
            Entry(id: "gesture", title: "Flip and shake to close", description: "An optional face-down shake returns from a saved app to Library.", symbol: "iphone.radiowaves.left.and.right", tint: .blue),
            Entry(id: "tabs", title: "Up to seven native tabs", description: "Apps can request compact UIKit tabs with badges, JavaScript selection callbacks and animations.", symbol: "square.stack", tint: .mint),
            Entry(id: "permissions", title: "Quieter permissions", description: "Repeated requests are coalesced and abusive prompts are blocked, with permissions shown in a simpler list.", symbol: "hand.raised.fill", tint: .orange)
        ] }
        if version == "1.6.21" { return [
            Entry(id: "ai-privacy", title: "AI Generation Privacy", description: "Control whether Forge may use location, date, device, calendar, reminders or public HTTPS research. All permissions default off.", symbol: "hand.raised.shield.fill", tint: .blue),
            Entry(id: "widget-actions", title: "Actionable app widgets", description: "Generated widgets can open specific screens or deliver validated action context through signed links.", symbol: "square.grid.2x2.fill", tint: .purple),
            Entry(id: "battery-thermal", title: "Battery and thermal APIs", description: "HTML apps can read charging status, battery percentage and thermal state.", symbol: "battery.100percent.bolt", tint: .green),
            Entry(id: "clean-forge", title: "Simpler creation screen", description: "Quick mode controls appear only when Manual policy is selected; debug model and UI polish status labels are hidden.", symbol: "slider.horizontal.3", tint: .orange)
        ] }
        if version == "1.6.20" { return [
            Entry(id: "background-music", title: "Longer background playback", description: "Generation Music uses primary audio playback and safer background request handoffs when audio is interrupted.", symbol: "music.note", tint: .purple),
            Entry(id: "auto-fast", title: "Automatic Quick mode", description: "Choose Manual or Automatic AI speed selection, with the option to override the recommendation.", symbol: "bolt.fill", tint: .orange),
            Entry(id: "smarter-planner", title: "Faster planning and clearer intent", description: "Forge produces shorter planning briefs and suggests an editable purpose during style selection.", symbol: "brain", tint: .blue),
            Entry(id: "smoother-library", title: "Faster opening and setup", description: "App launching avoids a synchronous Library rewrite, and Home Screen installation now offers additional recovery options.", symbol: "apps.iphone", tint: .green),
            Entry(id: "shorter-tour", title: "A shorter welcome tour", description: "Five introduction cards plus optional permissions replace the long setup walkthrough.", symbol: "hand.tap.fill", tint: .mint)
        ] }
        if version == "1.6.19" { return [
            Entry(id: "variety", title: "More original AI looks", description: "Regenerated looks use genuinely different layout archetypes, not just different colors.", symbol: "paintpalette.fill", tint: .purple),
            Entry(id: "runtime-js", title: "JavaScript error assistant", description: "A warning icon in Forge preview can show runtime errors and offer to ask AI for a fix.", symbol: "exclamationmark.triangle.fill", tint: .orange)
        ] }
        if version == "1.6.18" { return [
            Entry(id: "generation-music", title: "Generation Music", description: "Play your own linked audio during Forge creation and editing, with cached playback, volume and preview controls.", symbol: "music.note", tint: .purple),
            Entry(id: "quick-performance", title: "Faster QUICK! creation", description: "QUICK! avoids optional web research and extra specialist icon regeneration.", symbol: "bolt.fill", tint: .orange),
            Entry(id: "instant-style-choices", title: "Instant style choices", description: "Three looks are immediately available while a small AI request can refine their product labels.", symbol: "paintpalette.fill", tint: .blue)
        ] }
        if version == "1.6.17" { return [
            Entry(id: "complete-style-mockups", title: "Complete AI style previews", description: "Forge gives preview models enough output budget to finish their HTML and retries incomplete specialist results using the main app model.", symbol: "paintpalette.fill", tint: .purple),
            Entry(id: "preview-debug", title: "Clearer provider diagnostics", description: "AI Debug now shows response finish reasons and token usage when the provider includes them, helping identify truncated mockups.", symbol: "waveform.path.ecg.rectangle", tint: .blue)
        ] }
        if version == "1.6.16" { return [
            Entry(id: "voice-widget-resume", title: "More reliable Lock Screen voice launch", description: "Cold-start widget links reopen Forge, begin recording, then switch to hold-to-talk after you tap Stop.", symbol: "mic.fill", tint: .blue),
            Entry(id: "style-sketches", title: "More relevant AI style previews", description: "Forge requests mockups for your exact idea and system light or dark appearance. Offline sketches now show realistic product content.", symbol: "paintpalette.fill", tint: .purple),
            Entry(id: "quick-run", title: "QUICK! generation and optional skips", description: "Configure a smaller model, switch QUICK! on when creating, and skip optional planning, icon or UI polish stages.", symbol: "bolt.fill", tint: .orange),
            Entry(id: "import-url", title: "Edit HTML from a link", description: "An htmlapp://import link can download a public HTTPS HTML file into an unsaved Forge AI editing session.", symbol: "link", tint: .green),
            Entry(id: "guided-practice", title: "Hands-on Forge tutorial", description: "Practice calculator testing, dragging the mic, typing changes, and saving without using AI credits.", symbol: "hand.tap.fill", tint: .mint)
        ] }
        if version == "1.6.15" { return [
            Entry(id: "lockscreen-forge", title: "Lock Screen voice goes straight to Forge", description: "The Lock Screen microphone opens the regular Generate with AI screen and starts listening. Tap the mic again to stop, or use Generate or Cancel.", symbol: "mic.fill", tint: .blue),
            Entry(id: "whisper-handoff", title: "Voice generation waits for transcription", description: "If Whisper is selected, Forge finishes transcribing before using your spoken idea.", symbol: "waveform", tint: .purple),
            Entry(id: "welcome-action", title: "A simpler What's New screen", description: "One clear Continue to HTMLApp button closes the update notes.", symbol: "arrow.right.circle.fill", tint: .green)
        ] }
        if version == "1.6.14" { return [
            Entry(id: "faithful-look", title: "More faithful generated apps", description: "Forge checks the chosen mockup's layout as well as its colors before presenting the final app.", symbol: "square.stack", tint: .purple),
            Entry(id: "fast-location", title: "Faster location responses", description: "Recently obtained accurate locations can be reused instead of waiting for GPS again.", symbol: "location.fill", tint: .blue),
            Entry(id: "whisper-ready", title: "Whisper preloading", description: "When selected, Whisper can load on opening HTMLApp instead of at the end of recording.", symbol: "waveform", tint: .orange),
            Entry(id: "forge-questions", title: "Optional Forge questions", description: "Forge can ask a quick design question and continue with its recommended answer after 20 seconds.", symbol: "questionmark.bubble", tint: .green),
            Entry(id: "voice-drafts", title: "Voice capture and draft fixes", description: "Lock Screen Generate Now uses the captured idea, while completed drafts no longer trigger recovery.", symbol: "mic", tint: .blue)
        ] }
        if version == "1.6.13" { return [
            Entry(id: "distinct-styles", title: "Three different looks", description: "Style previews now vary layout, structure and domain-specific content, not just colors.", symbol: "square.grid.3x1", tint: .purple),
            Entry(id: "functional", title: "Better working apps", description: "Forge now audits core workflows and asks the AI for real functionality instead of decorative placeholders.", symbol: "checkmark.shield", tint: .blue),
            Entry(id: "loading-states", title: "Useful loading states", description: "Generated apps include clear loading, error, retry and empty states for delayed tasks.", symbol: "hourglass", tint: .orange)
        ] }
        if version == "1.6.12" { return [
            Entry(id: "icloud-apps", title: "iCloud app syncing", description: "Opt in to mirroring your HTMLApp Library through iCloud Drive from Settings.", symbol: "icloud", tint: .blue),
            Entry(id: "icloud-data", title: "Optional HTMLApp data syncing", description: "When iCloud app syncing is enabled, choose whether each app's portable saved data also syncs.", symbol: "externaldrive", tint: .purple)
        ] }
        if version == "1.6.11" { return [
            Entry(id: "statusbar", title: "Choose the system status bar", description: "HTMLApps show the real status bar by default; immersive apps can request to hide it.", symbol: "iphone", tint: .blue),
            Entry(id: "default-prompt", title: "Simpler AI settings", description: "Forge always uses maintained built-in instructions instead of editable system prompts.", symbol: "wand.and.stars", tint: .purple),
            Entry(id: "widget-families", title: "Complete widget sizes", description: "AI generation and edits now request all three Home Screen or Lock Screen widget sizes when widgets are appropriate.", symbol: "square.grid.2x2", tint: .green)
        ] }
        if version == "1.6.10" { return [
            Entry(id: "native-tabs-mounted", title: "More reliable native tabs", description: "The iOS tab controller waits for its HTMLApp window before mounting, with native UIKit tab destinations.", symbol: "square.split.2x1", tint: .blue),
            Entry(id: "tips", title: "Helpful first-time tips", description: "Short, dismissible hints explain Library, AI generation, gestures, sharing and editing after onboarding.", symbol: "lightbulb", tint: .orange),
            Entry(id: "phone-sketches", title: "Phone-sized look previews", description: "Generated style mockups appear inside a larger rounded phone-style preview.", symbol: "iphone", tint: .purple),
            Entry(id: "simplified-menu", title: "Organized app actions", description: "Long-press actions are grouped into Everyday Usage, Sharing, Developer and Delete.", symbol: "square.grid.2x2", tint: .indigo),
            Entry(id: "faster-opening", title: "Faster first app opening", description: "HTMLApp primes its WebKit process while the Library is open.", symbol: "bolt", tint: .green),
            Entry(id: "creating-app", title: "Clearer activity labels", description: "The AI activity chart now says Creating App instead of App Tests.", symbol: "chart.bar", tint: .green)
        ] }
        if version == "1.6.9" { return [
            Entry(id: "mockup-fast", title: "Faster style previews", description: "Mockups generate in parallel using compact HTML instead of fragile JSON, with shorter first-pass requests.", symbol: "sparkles.rectangle.stack", tint: .purple),
            Entry(id: "mockup-recovery", title: "Reliable mockup choices", description: "Each style retries independently and shows a distinct local preview if the AI provider fails.", symbol: "square.grid.3x1", tint: .blue),
            Entry(id: "discard-close", title: "Discard and close", description: "Discarding an interrupted generation closes Create with AI instead of leaving the page open.", symbol: "xmark.circle", tint: .orange)
        ] }
        if version == "1.6.8" { return [
            Entry(id: "icon-renderer", title: "Reliable AI icon rendering", description: "The icon renderer supports the AI's FILL directives and inherited colors instead of repeatedly falling back to a generic icon.", symbol: "paintpalette", tint: .purple),
            Entry(id: "glass-tabs", title: "Host-owned iOS tabs", description: "Native tab navigation now uses a UITabBarController so eligible iOS 26 devices can receive Apple's system tab appearance.", symbol: "square.split.2x1", tint: .blue),
            Entry(id: "clean-ui", title: "No fake phone chrome", description: "AI generation and style mockups avoid drawing fake status bars, notches and Dynamic Islands.", symbol: "iphone", tint: .indigo),
            Entry(id: "install-guide", title: "Simpler Home Screen installation", description: "A dedicated instructions page replaces the Safari-or-export dialog.", symbol: "apps.iphone", tint: .green),
            Entry(id: "forge-warning", title: "Generation safety reminder", description: "The creation dashboard warns you to keep HTMLApp open, and Forge's Live Activity shows a return reminder.", symbol: "exclamationmark.triangle", tint: .red),
            Entry(id: "forge-arcade", title: "Easier generation mini-game", description: "Larger hit targets, streak bonuses, haptics and restart controls make the arcade easier to play.", symbol: "gamecontroller", tint: .orange)
        ] }
        if version == "1.6.7" { return [
            Entry(id: "floating-whisper", title: "Whisper for floating microphones", description: "Mockup feedback and AI edits wait for offline speech transcription before applying changes.", symbol: "waveform", tint: .blue),
            Entry(id: "picker-buttons", title: "Visible mockup choices", description: "Three larger vertical design selectors stay visible on iPhone and iPad.", symbol: "square.grid.3x1.fill", tint: .purple),
            Entry(id: "voice-prompt", title: "Reliable voice creation", description: "Lock Screen voice prompts survive dismissal and avoid duplicate creation jobs.", symbol: "mic.fill", tint: .blue),
            Entry(id: "widgets", title: "More dependable widgets", description: "Widgets show cached shared data without waiting on network, and the Lock Screen voice icon stays visible.", symbol: "square.grid.2x2", tint: .orange),
            Entry(id: "native-tabs", title: "Native iOS tabs and gestures", description: "Generated HTMLApps can request host-rendered UIKit tabs with JavaScript navigation events.", symbol: "square.split.2x1", tint: .indigo),
            Entry(id: "nearby-bluetooth", title: "Bluetooth discovery", description: "Saved apps can request time-limited nearby BLE scans with permissions; sharing screens explain Wi-Fi and Bluetooth setup.", symbol: "antenna.radiowaves.left.and.right", tint: .blue),
            Entry(id: "practice-forge", title: "Practice with real Forge screens", description: "The onboarding calculator uses the real creation and editing interface without making AI requests or saving changes.", symbol: "plus.forwardslash.minus", tint: .green),
            Entry(id: "specialists", title: "Simpler AI settings", description: "Specialist AI choices replace the advanced model-names section; enabled specialists show green status dots.", symbol: "brain", tint: .green)
        ] }
        if version == "1.6.6" { return [
            Entry(id: "voice-looks", title: "Lock Screen voice mockups", description: "Voice-created apps respect mockup selection; three looks now generate concurrently.", symbol: "paintpalette", tint: .purple),
            Entry(id: "match-style", title: "Keep the chosen look", description: "Forge uses selected mockup HTML and CSS tokens as its visual reference, even during later AI edits.", symbol: "checkmark.seal", tint: .blue),
            Entry(id: "forge-activity", title: "Forge progress on Lock Screen", description: "A red Live Activity warns about background limitations and displays the active AI stage.", symbol: "exclamationmark.triangle.fill", tint: .red),
            Entry(id: "widget-reloads", title: "Prompt widget refresh requests", description: "Widget publication and app-data changes request targeted WidgetKit reloads.", symbol: "arrow.clockwise", tint: .orange),
            Entry(id: "stable-dictation", title: "Steadier microphone recording", description: "The create microphone stays in a fixed location during long presses and changing transcription.", symbol: "mic.fill", tint: .green),
            Entry(id: "device-tools", title: "Discover more native tools", description: "Generated apps can query supported native APIs and request flashlight, brightness, or walking-step data with consent.", symbol: "iphone", tint: .blue)
        ] }
        if version == "1.6.5" { return [
            Entry(id: "sketch-progress", title: "Live style sketch previews", description: "See each sketch appear blurred while the remaining directions generate.", symbol: "paintpalette", tint: .purple),
            Entry(id: "fix-reopen", title: "Library starts in the Library", description: "Stale AI edit checkpoints no longer auto-open an existing saved app.", symbol: "books.vertical", tint: .blue),
            Entry(id: "forge-done", title: "Generation completion feedback", description: "Get a notification away from HTMLApp or three haptics while the app is active.", symbol: "bell.badge", tint: .green)
        ] }
        if version == "1.6.4" { return [
            Entry(id: "generation-recovery", title: "Recover interrupted AI work", description: "Review an unsaved generation checkpoint after reopening HTMLApp, including elapsed work time.", symbol: "arrow.clockwise.circle", tint: .blue),
            Entry(id: "background-grace", title: "Continue when switching apps", description: "Forge requests limited background execution time and preserves work if iOS suspends it.", symbol: "moon.stars", tint: .purple)
        ] }
        if version == "1.6.3" { return [
            Entry(id: "timers", title: "Self-updating Live Activity timers", description: "Countdown Live Activities can now use native deadline-based timer labels even when HTMLApp is asleep.", symbol: "timer", tint: .orange),
            Entry(id: "voice-lock", title: "Voice create from Lock Screen", description: "A dedicated Lock Screen widget opens a voice-first AI creation screen.", symbol: "mic.fill", tint: .blue)
        ] }
        if version == "1.6.2" { return [
            Entry(id: "offline-whisper", title: "Whisper offline dictation", description: "Switch between Apple Speech and local Whisper speech recognition in Settings.", symbol: "waveform", tint: .blue),
            Entry(id: "dictation-guide", title: "Test your microphone", description: "Try Apple dictation during onboarding and choose Whisper if your words do not appear.", symbol: "mic.circle", tint: .purple)
        ] }
        if version == "1.6.1" { return [
            Entry(id: "edit-history", title: "Restore AI edits", description: "Revisit saved AI edit versions from the Library and restore the HTML you want.", symbol: "clock.arrow.circlepath", tint: .blue),
            Entry(id: "regenerate-draft", title: "Start a fresh draft", description: "Regenerate an unsaved app from its original prompt.", symbol: "arrow.clockwise", tint: .purple),
            Entry(id: "edit-summary", title: "Explain each AI edit", description: "Forge records a short description of AI changes.", symbol: "text.bubble", tint: .green),
            Entry(id: "symbols", title: "SF Symbols in HTML", description: "Generated apps can search a curated native SF Symbols catalog and render supported symbols.", symbol: "star.square", tint: .orange),
            Entry(id: "onboarding-demo", title: "Calculator tutorial", description: "Practice a simulated AI build, calculator controls, and spoken edit ideas during onboarding.", symbol: "plus.forwardslash.minus", tint: .purple)
        ] }
        if version == "1.6" || version.hasPrefix("1.6.") {
            return [
                Entry(id: "safe-library", title: "Safer saved apps",
                      description: "HTMLApp protects your Library if stored data cannot be read, preserves a damaged copy, and keeps a rolling recovery backup.",
                      symbol: "externaldrive.badge.checkmark", tint: .blue),
                Entry(id: "quick-tests", title: "Faster AI app testing",
                      description: "Forge distinguishes blocking failures from advice, fixes simple document problems locally, and limits expensive AI repair retries.",
                      symbol: "bolt.fill", tint: .orange),
                Entry(id: "qa-timeline", title: "More accurate AI work history",
                      description: "A separate AI repair segment shows where time went without counting the same HTML bytes as tests or icons.",
                      symbol: "chart.pie.fill", tint: .purple),
                Entry(id: "package-version", title: "Verified IPA versions",
                      description: "Build metadata now includes the app and widget versions, with validation of the final packaged IPA.",
                      symbol: "checkmark.shield", tint: .green)
            ]
        }

        if version == "1.5" || version.hasPrefix("1.5.") {
            return [Entry(id: "version", title: "Reliable version tracking", description: "The app and packaged IPA display the same release and build numbers, checked before packaging.", symbol: "checkmark.seal", tint: .blue)]
        }
        if version == "1.4" || version.hasPrefix("1.4.") {
            return [
                Entry(id: "verified-build", title: "Check exactly which build you're running",
                      description: "Settings now shows a hardcoded app release and the actual IPA Info.plist version side by side, including warnings if they don't match.",
                      symbol: "checkmark.shield.fill", tint: .blue),
                Entry(id: "fast-qa", title: "Faster generation and dependable testing",
                      description: "Forge runs its local app checks first and asks a separate reviewer only when concrete errors need repairing.",
                      symbol: "bolt.fill", tint: .orange),
                Entry(id: "icon-check", title: "Stop blank app icons",
                      description: "Icon rendering checks for genuinely visible artwork instead of accepting a background-only image.",
                      symbol: "app.badge.fill", tint: .purple),
                Entry(id: "style-feedback", title: "Tell Forge what to change about every mockup",
                      description: "Drag the floating microphone onto the screen to dictate feedback and regenerate all mockups around it.",
                      symbol: "mic.fill", tint: .pink)
            ]
        }
        if version == "1.3" || version.hasPrefix("1.3.") {
            return [
                Entry(id: "guided-start", title: "A guided welcome",
                      description: "A clearer, six-step tour teaches you to create, open, edit, organize, and share HTML apps. Skip any step whenever you like.",
                      symbol: "hand.wave.fill", tint: .indigo),
                Entry(id: "easy-setup", title: "Set things up as you go",
                      description: "Choose your Library layout and optionally connect your AI provider during setup. Permission requests remain your choice.",
                      symbol: "slider.horizontal.3", tint: .blue),
                Entry(id: "try-menu", title: "Learn app shortcuts",
                      description: "Try the long-press menu on a safe example so you know how to favorite, edit, move, and share apps.",
                      symbol: "hand.tap.fill", tint: .orange),
                Entry(id: "release-notes", title: "Never miss an update",
                      description: "HTMLApp remembers the last installed version and displays this What's New page when a newer version opens.",
                      symbol: "sparkles.rectangle.stack", tint: .pink),
                Entry(id: "replay", title: "Help whenever you need it",
                      description: "Replay the tutorial or reopen this changelog from Settings → Help & Updates.",
                      symbol: "questionmark.circle.fill", tint: .mint)
            ]
        }
        guard version == "1.2" || version.hasPrefix("1.2.") else { return [] }
        return [
            Entry(id: "forge", title: "A smarter AI creator",
                  description: "Make an app from an idea, explore different designs, and watch its progress while Forge works.",
                  symbol: "sparkles.rectangle.stack", tint: .purple),
            Entry(id: "edit", title: "Safer AI edits",
                  description: "Forge checks the code, tries to repair mistakes, and can restore the previous app if an edit fails.",
                  symbol: "wrench.and.screwdriver.fill", tint: .blue),
            Entry(id: "share", title: "Share apps more easily",
                  description: "Nearby sending and receiving have simpler screens and automatic transfer after devices connect.",
                  symbol: "iphone.gen3.radiowaves.left.and.right", tint: .mint),
            Entry(id: "icons", title: "Fresh icons and quick actions",
                  description: "Regenerate an icon with a preview, use simpler app menus, and open saved apps using Shortcuts.",
                  symbol: "app.badge", tint: .orange),
            Entry(id: "widgets", title: "More native iOS features",
                  description: "Supported apps can show Home Screen and Lock Screen widgets, Live Activities, and Dynamic Island progress.",
                  symbol: "rectangle.on.rectangle", tint: .pink),
            Entry(id: "debug", title: "Better troubleshooting",
                  description: "Developer Mode now keeps recent AI edit logs, run timings, and app diagnostics.",
                  symbol: "ladybug.fill", tint: .indigo)
        ]
    }
}

/// Presented for a newly detected installed version, or manually from Settings.
struct HTMLAppWhatsNewView: View {
    let previousVersion: String?
    let onDone: () -> Void
    private var version: String { HTMLAppReleaseNotes.installedVersion }
    private var updates: [HTMLAppReleaseNotes.Entry] { HTMLAppReleaseNotes.entries(for: version) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 42, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 86, height: 86)
                            .background(
                                LinearGradient(colors: [.indigo, .purple, .pink],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 25)
                            )
                            .padding(.bottom, 8)

                        Text(previousVersion == nil ? "What's New in HTMLApp" : "HTMLApp was updated!")
                            .font(.largeTitle.bold())
                            .minimumScaleFactor(0.8)
                        Text(previousVersion.map { "You went from version \($0) to \(version)." }
                             ?? "Discover the latest features in your installed version.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("VERSION \(version) · BUILD \(HTMLAppReleaseNotes.installedBuild)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        if !HTMLAppReleaseNotes.packagingMatchesCode {
                            Label("This IPA's packaged version does not match the app code. Please update your build process.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    if updates.isEmpty {
                        whatsNewRow(title: "You're on version \(version)",
                                    detail: "Detailed release notes have not been published for this version.",
                                    symbol: "checkmark.seal.fill", tint: .blue)
                    } else {
                        Text("Highlights in this version")
                            .font(.headline)
                        ForEach(updates) { item in
                            whatsNewRow(title: item.title, detail: item.description,
                                        symbol: item.symbol, tint: item.tint)
                        }
                    }
                    Text("You can find this page again in Settings → What's New.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                Button(action: onDone) {
                    Text("Continue to HTMLApp")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func whatsNewRow(title: String, detail: String,
                             symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 50, height: 50)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}


