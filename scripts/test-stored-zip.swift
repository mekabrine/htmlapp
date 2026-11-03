import Foundation

enum HTMLAppPackageError: Error {
    case invalidArchive, unsafePath, archiveTooLarge, damagedArchive, unsupportedCompression
}

@main
struct StoredZipTests {
    static func main() throws {
        guard CommandLine.arguments.count > 1 else { fatalError("fixture folder required") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let payload = Data("<html><body><h1>Offline HTMLApp backup</h1></body></html>".utf8)
        for path in ["stored.zip", "deflated.zip", "descriptor.zip"] {
            let result = try StoredZip.read(from: root.appendingPathComponent(path))
            precondition(result.count == 1 && result["app.html"] == payload,
                         "Unexpected contents from \(path)")
        }
        let failures: [(String, HTMLAppPackageError)] = [
            ("bad-crc.zip", .damagedArchive),
            ("duplicate.zip", .damagedArchive),
            ("traversal.zip", .unsafePath),
            ("many.zip", .archiveTooLarge)
        ]
        for (path, expected) in failures {
            do {
                _ = try StoredZip.read(from: root.appendingPathComponent(path))
                fatalError("Unsafe ZIP fixture \(path) was accepted")
            } catch let error as HTMLAppPackageError {
                precondition(String(describing: error) == String(describing: expected),
                             "Wrong error for \(path): \(error)")
            }
        }
        let export = root.appendingPathComponent("exported.zip")
        try StoredZip.write(entries: [
            .init(path: "folder/app.html", data: payload)
        ], to: export)
        let roundtrip = try StoredZip.read(from: export)
        precondition(roundtrip["folder/app.html"] == payload, "Store export roundtrip failed")
        print("ZIP Store/Deflate/descriptors/CRC/limits and export fixtures passed.")
    }
}
