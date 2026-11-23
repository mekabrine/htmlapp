import Foundation

@main struct HTMLAppDocumentModeTests {
    static func main() {
        let variants = [
            #"<head><meta name="htmlapp-runtime" content="package"></head>"#,
            #"<HEAD><META CONTENT='PACKAGE' NAME='HTMLAPP-RUNTIME'></HEAD>"#,
            #"<head><meta data-extra=x name=htmlapp-runtime content=package /></head>"#,
            #"<meta content="package" name="htmlapp-runtime">"#
        ]
        for html in variants {
            precondition(HTMLAppDocumentMode.usesPackageRuntime(html), "Package marker was missed: \(html)")
        }
        precondition(!HTMLAppDocumentMode.usesPackageRuntime(#"<head><!-- <meta name="htmlapp-runtime" content="package"> --></head>"#))
        precondition(!HTMLAppDocumentMode.usesPackageRuntime(#"<head><meta name="htmlapp-runtime" content="off"></head>"#))
        precondition(!HTMLAppDocumentMode.usesPackageRuntime(#"<head><meta content="package" name="unrelated"></head>"#))
        precondition(!HTMLAppDocumentMode.usesPackageRuntime(#"<html><head></head><body><meta name="htmlapp-runtime" content="package"></body></html>"#))
        let chart = #"<script defer src="/libraries/chart.js/dist/chart.umd.min.js"></script>"#
        let origin = "htmlapp-resource://app-test"
        let example = "<!-- " + chart + " -->"
        let cdn = "https://example.com/library.js"
        let html = example + chart + "<SCRIPT SRC = '" + cdn + "'></SCRIPT>"
        let expected = example + chart.replacingOccurrences(of: "/libraries/", with: origin + "/libraries/")
            + "<SCRIPT SRC = '" + cdn + "'></SCRIPT>"
        precondition(HTMLAppDocumentMode.resolvingBundledLibraries(in: html, origin: origin) == expected)
        precondition(HTMLAppDocumentMode.remoteLibraries(in: html) == [cdn])
        let cached = HTMLAppDocumentMode.replacingLibraryReferences(in: html) {
            $0 == cdn ? "offline-cache/library.js" : nil
        }
        precondition(cached == example + chart + "<SCRIPT SRC = 'offline-cache/library.js'></SCRIPT>")
        print("Package runtime marker fixtures passed.")
    }
}
