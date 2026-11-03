import UIKit
import UniformTypeIdentifiers

/// iOS Share-sheet extension for HTML documents.
///
/// A Share extension cannot reliably launch its containing app on every
/// iOS version. It saves the document in the App Group inbox, then attempts
/// the HTMLApp URL handoff. The app drains the inbox on foreground launch.
final class HTMLAppShareViewController: UIViewController {
    private let groupID = "group.com.mekabrine.htmlapp"
    private let maximumSize = 12_000_000
    private let status = UILabel()
    private let openButton = UIButton(type: .system)
    private var receivedDocument = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let title = UILabel()
        title.text = "Import into HTMLApp"
        title.font = .preferredFont(forTextStyle: .title2)
        title.adjustsFontForContentSizeCategory = true

        status.text = "Preparing your HTML document…"
        status.font = .preferredFont(forTextStyle: .body)
        status.numberOfLines = 0
        status.adjustsFontForContentSizeCategory = true

        openButton.setTitle("Open HTMLApp", for: .normal)
        openButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        openButton.addTarget(self, action: #selector(openHTMLApp), for: .touchUpInside)
        openButton.isEnabled = false

        let done = UIButton(type: .system)
        done.setTitle("Done", for: .normal)
        done.addTarget(self, action: #selector(finish), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, status, openButton, done])
        stack.axis = .vertical
        stack.spacing = 18
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        receiveSharedDocument()
    }

    private func receiveSharedDocument() {
        let attachments = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []
        let supported = attachments.compactMap { provider -> (NSItemProvider, String)? in
            let type = provider.registeredTypeIdentifiers.first { identifier in
                guard let kind = UTType(identifier) else { return false }
                return kind.conforms(to: .html) || kind.conforms(to: .data)
            }
            return type.map { (provider, $0) }
        }
        guard let (provider, kind) = supported.first else {
            report("Share a local HTML document to import it.")
            return
        }
        provider.loadFileRepresentation(forTypeIdentifier: kind) { [weak self] url, error in
            guard let self else { return }
            guard let url else {
                self.report(error?.localizedDescription ?? "Couldn't read the shared HTML file.")
                return
            }
            do {
                try self.saveToSharedInbox(source: url, suggestedName: provider.suggestedName)
                DispatchQueue.main.async {
                    self.receivedDocument = true
                    self.status.text = "Ready to import. Open HTMLApp to choose New App or Update Existing."
                    self.openButton.isEnabled = true
                    self.openHTMLApp()
                }
            } catch {
                self.report(error.localizedDescription)
            }
        }
    }

    private func saveToSharedInbox(source: URL, suggestedName: String?) throws {
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else {
            throw NSError(domain: "HTMLAppShare", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:
                            "The shared HTML inbox isn't available with this signing profile."])
        }
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        guard !data.isEmpty, data.count <= maximumSize else {
            throw NSError(domain: "HTMLAppShare", code: 2,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Choose a nonempty HTML file smaller than 12 MB."])
        }
        let fm = FileManager.default
        let incoming = group.appendingPathComponent("IncomingHTML", isDirectory: true)
        let staging = group.appendingPathComponent("IncomingHTMLStaging", isDirectory: true)
        try fm.createDirectory(at: incoming, withIntermediateDirectories: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let temporary = staging.appendingPathComponent(id, isDirectory: true)
        let completed = incoming.appendingPathComponent(id, isDirectory: true)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        let original = (suggestedName ?? source.lastPathComponent) as NSString
        let base = String(original.deletingPathExtension.prefix(75))
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let cleanName = (base.isEmpty ? "Shared-HTML" : base) + ".html"
        do {
            try data.write(to: temporary.appendingPathComponent(cleanName), options: .atomic)
            try fm.moveItem(at: temporary, to: completed)
        } catch {
            try? fm.removeItem(at: temporary)
            throw error
        }
    }

    private func report(_ message: String) {
        DispatchQueue.main.async {
            self.status.text = message
            self.openButton.isEnabled = self.receivedDocument
        }
    }

    @objc private func openHTMLApp() {
        guard receivedDocument, let url = URL(string: "htmlapp://import-inbox") else { return }
        // Host activation is opportunistic. A Share extension isn't allowed
        // to assume iOS will open its containing app.
        extensionContext?.open(url) { [weak self] launched in
            DispatchQueue.main.async {
                if launched {
                    self?.finish()
                } else {
                    self?.status.text = "HTML saved. Open HTMLApp from your Home Screen to import it."
                }
            }
        }
    }

    @objc private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
