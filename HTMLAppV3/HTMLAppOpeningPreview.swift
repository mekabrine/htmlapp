import CryptoKit
import SwiftUI
import UIKit
import WebKit

enum HTMLAppOpeningPreviewCache {
    private struct Entry: Codable {
        let revision: Date
        let image: Data
    }

    private static let maxImageBytes = 1_000_000

    static func isEnabled(for appID: String) -> Bool {
        UserDefaults.standard.bool(forKey: permissionKey(for: appID))
    }

    static func setEnabled(_ enabled: Bool, for appID: String) {
        if enabled {
            UserDefaults.standard.set(true, forKey: permissionKey(for: appID))
        } else {
            UserDefaults.standard.removeObject(forKey: permissionKey(for: appID))
            try? FileManager.default.removeItem(at: fileURL(for: appID))
        }
    }

    static func image(for app: SavedHTMLApp) -> UIImage? {
        guard isEnabled(for: app.id) else { return nil }
        let url = fileURL(for: app.id)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 2 * maxImageBytes,
              let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.revision == app.updatedAt else { return nil }
        return UIImage(data: entry.image)
    }

    static func save(_ image: UIImage, for app: SavedHTMLApp) {
        guard isEnabled(for: app.id),
              let bytes = image.jpegData(compressionQuality: 0.75),
              bytes.count <= maxImageBytes,
              let data = try? JSONEncoder().encode(Entry(revision: app.updatedAt, image: bytes)) else { return }
        let url = fileURL(for: app.id)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private static func permissionKey(for appID: String) -> String {
        "htmlapp.openingPreview." + appID
    }

    private static func fileURL(for appID: String) -> URL {
        let key = SHA256.hash(data: Data(appID.utf8)).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLAppOpeningPreviews", isDirectory: true)
            .appendingPathComponent(key + ".json")
    }
}

@MainActor
final class HTMLAppOpeningPreview: ObservableObject {
    @Published private(set) var isShowing = true
    @Published private(set) var failed = false
    private let initialImage: UIImage?
    private let initialRevision: Date
    private var captureRevision: Date?

    init(app: SavedHTMLApp) {
        initialImage = HTMLAppOpeningPreviewCache.image(for: app)
        initialRevision = app.updatedAt
    }

    func image(for app: SavedHTMLApp) -> UIImage? {
        initialRevision == app.updatedAt ? initialImage : nil
    }

    func loaded(_ webView: WKWebView, app: SavedHTMLApp, succeeded: Bool) {
        guard isShowing else { return }
        if !succeeded {
            failed = true
            return
        }
        guard HTMLAppOpeningPreviewCache.isEnabled(for: app.id),
              captureRevision != app.updatedAt,
              HTMLAppOpeningPreviewCache.image(for: app) == nil,
              !webView.bounds.isEmpty,
              UIApplication.shared.applicationState == .active else {
            isShowing = false
            return
        }

        captureRevision = app.updatedAt
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.snapshotWidth = NSNumber(value: min(Double(webView.bounds.width), 600))
        configuration.afterScreenUpdates = true
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            guard let self, self.isShowing, self.captureRevision == app.updatedAt else { return }
            if let image, image.size.width > 1, image.size.height > 1,
               UIApplication.shared.applicationState == .active {
                HTMLAppOpeningPreviewCache.save(image, for: app)
            }
            self.isShowing = false
        }
    }

    func endWait() {
        if !failed { isShowing = false }
    }
}

struct HTMLAppOpeningPreviewView: View {
    let app: SavedHTMLApp
    let image: UIImage?
    let failed: Bool
    let close: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color("HTMLAppLaunchBackground").ignoresSafeArea()
                if let image, !failed {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .accessibilityHidden(true)
                    ProgressView()
                        .tint(.white)
                        .padding(10)
                        .background(.black.opacity(0.7), in: Circle())
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 24)
                        .accessibilityLabel("Opening \(app.name)")
                } else {
                    VStack(spacing: 16) {
                        AppIconView(app: app, size: 76)
                            .accessibilityHidden(true)
                        Text(app.name).font(.title2.bold()).multilineTextAlignment(.center)
                        if failed {
                            Text("The app couldn’t load.")
                            Button("Back to Library", action: close).buttonStyle(.bordered)
                        } else {
                            ProgressView().tint(.white).accessibilityLabel("Opening \(app.name)")
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(24)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
        }
    }
}
