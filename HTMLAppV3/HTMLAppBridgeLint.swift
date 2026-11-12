import Foundation

/// Local repairs run before QA and never call a model or request permissions.
enum ForgeLocalFixers {
    static func repair(_ html: String) -> String {
        var result = html
        // Only exact, known aliases inside inline scripts. Never guess arguments
        // or rename arbitrary user functions, storage keys or external scripts.
        let aliases = ["vision.detectFace": "vision.detectFaces",
                       "vision.recogniseText": "vision.recognizeText",
                       "vision.detectBarcodes": "vision.scanCodes"]
        if let scripts = try? NSRegularExpression(pattern: #"(?is)<script\b[^>]*>.*?</script\s*>"#) {
            for match in scripts.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                var script = String(result[range])
                for (wrong, correct) in aliases {
                    let pattern = #"\bHTMLAppNative\."# + NSRegularExpression.escapedPattern(for: wrong) + #"(?=\s*\()"#
                    script = script.replacingOccurrences(of: pattern, with: "HTMLAppNative." + correct, options: .regularExpression)
                }
                result.replaceSubrange(range, with: script)
            }
        }
        if result.contains("FaceDetector"), !result.contains("data-htmlapp-vision-fixer"),
           let head = result.range(of: #"<head\b[^>]*>"#, options: [.regularExpression, .caseInsensitive]) {
            result.insert(contentsOf: faceAdapter, at: head.upperBound)
        }
        return result
    }

    // Shape Detection compatibility via the existing permission-checked native
    // Vision API. A face box does not provide gaze, identity or face landmarks.
    static let faceAdapter = #"""
    <script data-htmlapp-vision-fixer>
    (() => {
      if (typeof globalThis.FaceDetector === 'function') return;
      class NativeFaceDetector {
        constructor() { this.pending = null; this.last = 0; this.cached = []; this.error = null; }
        async detect(image) {
          if (this.pending) return this.pending;
          if (Date.now() - this.last < 250) { if (this.error) throw this.error; return this.cached; }
          this.pending = this.scan(image);
          try { this.cached = await this.pending; this.error = null; this.last = Date.now(); return this.cached; }
          catch (error) { this.error = error; this.last = Date.now(); throw error; }
          finally { this.pending = null; }
        }
        async scan(image) {
          const api = globalThis.HTMLAppNative;
          if (!api?.vision?.detectFaces) throw new Error('Native Vision is unavailable in this host. Use the manual fallback.');
          const w = image.videoWidth || image.naturalWidth || image.width;
          const h = image.videoHeight || image.naturalHeight || image.height;
          if (!(w > 0 && h > 0)) return [];
          const scale = Math.min(1, 640 / Math.max(w, h));
          const canvas = document.createElement('canvas');
          canvas.width = Math.max(1, Math.round(w * scale));
          canvas.height = Math.max(1, Math.round(h * scale));
          canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
          const result = await api.vision.detectFaces(canvas.toDataURL('image/jpeg', .75));
          return (result.faces || []).map(f => ({boundingBox: {
            x: f.x * w, y: (1 - f.y - f.height) * h,
            width: f.width * w, height: f.height * h
          }, landmarks: []}));
        }
      }
      globalThis.FaceDetector = NativeFaceDetector;
    })();
    </script>
    """#

    static func blocking(_ issue: String) -> Bool {
        issue.hasPrefix("Bridge lint:") || issue.hasPrefix("Capability fixer:") ||
        issue.hasPrefix("Switch layout:") || issue.hasPrefix("3D viewer QA:")
    }

    static var deviceGuidance: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return """
        DEVICE TARGET: iOS/iPadOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), WKWebView host.
        Do not infer browser APIs from Apple Intelligence support. Use HTMLAppNative.vision.detectFaces(imageDataURL) for sampled camera images; result.faces has normalized bottom-left x,y,width,height. Camera capture requires user permission and an explicit start button. Stop tracks on exit; single-flight sampling at most 4 times/second, <=640px. Provide manual interaction when denied. Face boxes are not gaze or landmark tracking.
        Never invent bridges. Check (await HTMLAppNative.capabilities.describe('namespace.method')).available before optional hardware features and handle rejection/cancellation. Availability is not permission. Control Center requires iOS18+, native settings glass requires iOS26+, and older devices need useful inline controls. Web Bluetooth and browser SpeechRecognition are not reliable WKWebView capabilities; consult the native catalog instead. Do not gate native Vision on window.FaceDetector or Apple Intelligence.
        """
    }
}

/// Advisory static analysis of native APIs used by generated HTML.
/// Never executes untrusted app JavaScript.
enum HTMLAppBridgeLint {
    static func warnings(in html: String) -> [String] {
        // Bridge methods are registry-validated. SDK convenience wrappers
        // (which don't issue their own RPC) are validated separately so
        // they are not misreported as nonexistent native operations.
        let wrappers: Set<String> = [
            "ai.createSession", "db.searchFullText",
            "capabilities.has", "capabilities.describe",
            "events.on", "screens.configure", "screens.go", "motion.onData", "map.onSelect", "scene.onSelect"
        ]
        let known = HTMLAppBridgeRegistry.methodSet.union(wrappers)
        let pattern = #"\b(?:HTMLAppNative|HTMLApp)\.([A-Za-z][A-Za-z0-9]*)\.([A-Za-z][A-Za-z0-9]*)\s*\("#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = html as NSString
        var warnings: [String] = []
        var seen = Set<String>()
        for match in regex.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            guard match.numberOfRanges == 3 else { continue }
            let namespace = source.substring(with: match.range(at: 1))
            let method = source.substring(with: match.range(at: 2))
            let name = namespace + "." + method
            if !known.contains(name), seen.insert(name).inserted {
                let alternatives = known.filter { $0.hasPrefix(namespace + ".") }.sorted().prefix(8).joined(separator: ", ")
                warnings.append("Bridge lint: \(name) is not supported. Replace it using the typed API catalog; check argument and result shapes, feature-detect availability and provide a fallback. Same namespace: \(alternatives).")
            }
        }
        // Check common bridge calls whose positional arguments are required.
        // Regex lint is advisory: generated HTML can still call wrappers
        // indirectly, so this is not a substitute for runtime verification.
        let arities: [String: Int] = [
            "location.reverseGeocode": 2,
            "location.roadSpeedLimit": 2,
            "photos.read": 1,
            "photos.save": 1,
            "device.setBrightness": 1,
            "appStorage.get": 1,
            "appStorage.set": 2,
            "appStorage.remove": 1
        ]
        for match in regex.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            guard match.numberOfRanges == 3 else { continue }
            let name = source.substring(with: match.range(at: 1)) + "." +
                source.substring(with: match.range(at: 2))
            guard let required = arities[name] else { continue }
            let following = match.range.location + match.range.length
            guard following < source.length else { continue }
            // Only flag an immediately empty call. More complex expressions
            // require parsing and are intentionally not guessed at.
            let remaining = source.substring(from: following)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if remaining.hasPrefix(")") && required > 0,
               seen.insert("arity:" + name).inserted {
                warnings.append("Bridge lint: \(name) requires \(required) argument(s); the generated call is empty.")
            }
        }
        // Literal raw RPC names can be validated without executing the app.
        // This catches direct HTMLAppNative.call('wrong.method', ...) calls
        // that the wrapper-notation lint above cannot see.
        let directPattern = #"\bHTMLAppNative\s*\.\s*call\s*\(\s*['"]([A-Za-z][A-Za-z0-9]*\.[A-Za-z][A-Za-z0-9]*)['"]"#
        if let directRegex = try? NSRegularExpression(pattern: directPattern) {
            for match in directRegex.matches(
                in: html, range: NSRange(location: 0, length: source.length)
            ) where match.numberOfRanges == 2 {
                let name = source.substring(with: match.range(at: 1))
                if !HTMLAppBridgeRegistry.methodSet.contains(name),
                   seen.insert("direct:" + name).inserted {
                    warnings.append("Bridge lint: direct call to \(name) isn't registered. Use the generated native API contract.")
                }
            }
        }
        if html.contains("navigator.bluetooth.requestDevice(") {
            warnings.append("Bridge lint: Web Bluetooth requestDevice is not supported by this WKWebView runtime; use an available native capability.")
        }
        if html.contains("SpeechRecognition") || html.contains("webkitSpeechRecognition") {
            warnings.append("Capability fixer: Browser SpeechRecognition is unreliable in WKWebView. Use the catalog's native speech API with its exact arguments, explicit permission and a typed-input fallback.")
        }
        if html.contains("FaceDetector"), !html.contains("data-htmlapp-vision-fixer") {
            warnings.append("Capability fixer: Use HTMLAppNative.vision.detectFaces(imageDataURL); browser face detection is not a test for native Vision support.")
        }
        return warnings
    }
}

