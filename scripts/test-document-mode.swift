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
        print("Package runtime marker fixtures passed.")
    }
}
