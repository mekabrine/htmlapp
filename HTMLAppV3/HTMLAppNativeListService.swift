import Foundation
import UIKit

/// A small host-owned native sheet/list with VoiceOver labels and optional
/// pull-to-refresh events. Generated HTML cannot push arbitrary UIKit
/// controllers or execute JS in the background.
@MainActor
enum HTMLAppNativeListService {
    private static var sessions: [String: ListController] = [:]

    struct Item {
        let id: String
        let title: String
        let detail: String?
        let symbol: String?

        init?(_ object: [String: Any]) {
            guard let id = object["id"] as? String, !id.isEmpty, id.count <= 100,
                  let title = object["title"] as? String, !title.isEmpty,
                  title.count <= 120 else { return nil }
            self.id = id
            self.title = title
            detail = (object["detail"] as? String).map { String($0.prefix(240)) }
            symbol = (object["symbol"] as? String).map { String($0.prefix(80)) }
        }
    }

    private static func items(_ args: [String: Any]) -> [Item]? {
        guard let raw = args["items"] as? [[String: Any]],
              raw.count <= 200 else { return nil }
        let result = raw.compactMap(Item.init)
        guard result.count == raw.count,
              Set(result.map(\.id)).count == result.count else { return nil }
        return result
    }

    static func present(args: [String: Any], appID: String,
                        completion: @escaping @MainActor ([String: Any]) -> Void,
                        onRefresh: @escaping @MainActor (String) -> Void) -> Bool {
        guard sessions[appID] == nil,
              let parsed = items(args),
              let presenter = HTMLAppNativeUIService.presenter(for: appID)
        else { return false }
        let title = String((args["title"] as? String ?? "Choose an item").prefix(120))
        let sessionID = UUID().uuidString
        let controller = ListController(
            title: title, sessionID: sessionID, items: parsed,
            allowsRefresh: args["allowsRefresh"] as? Bool == true,
            refresh: onRefresh
        ) { result in
            sessions.removeValue(forKey: appID)
            completion(result)
        }
        sessions[appID] = controller
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        navigation.sheetPresentationController?.detents = [.medium(), .large()]
        presenter.present(navigation, animated: true)
        return true
    }

    static func update(args: [String: Any], appID: String) -> [String: Any]? {
        guard let controller = sessions[appID],
              let parsed = items(args) else { return nil }
        if let sessionID = args["sessionID"] as? String,
           sessionID != controller.sessionID { return nil }
        controller.update(items: parsed)
        return [
            "updated": true,
            "count": parsed.count,
            "sessionID": controller.sessionID
        ]
    }

    @discardableResult
    static func dismiss(appID: String) -> Bool {
        guard let controller = sessions[appID] else { return false }
        controller.finish(["cancelled": true])
        return true
    }

    private final class ListController: UITableViewController {
        let sessionID: String
        private var rows: [Item]
        private let refresh: @MainActor (String) -> Void
        private var callback: (@MainActor ([String: Any]) -> Void)?

        init(title: String, sessionID: String, items: [Item],
             allowsRefresh: Bool,
             refresh: @escaping @MainActor (String) -> Void,
             completion: @escaping @MainActor ([String: Any]) -> Void) {
            self.sessionID = sessionID
            self.rows = items
            self.refresh = refresh
            self.callback = completion
            super.init(style: .insetGrouped)
            self.title = title
            if allowsRefresh {
                refreshControl = UIRefreshControl()
                refreshControl?.addTarget(
                    self, action: #selector(pulledToRefresh), for: .valueChanged
                )
            }
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidLoad() {
            super.viewDidLoad()
            tableView.rowHeight = UITableView.automaticDimension
            tableView.estimatedRowHeight = 64
            tableView.accessibilityIdentifier = "HTMLAppNativeList"
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .done, target: self,
                action: #selector(done)
            )
        }

        func update(items: [Item]) {
            rows = items
            tableView.reloadData()
            refreshControl?.endRefreshing()
        }

        override func tableView(_ tableView: UITableView,
                                numberOfRowsInSection section: Int) -> Int {
            rows.count
        }

        override func tableView(_ tableView: UITableView,
                                cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            let item = rows[indexPath.row]
            cell.textLabel?.text = item.title
            cell.textLabel?.font = .preferredFont(forTextStyle: .body)
            cell.textLabel?.adjustsFontForContentSizeCategory = true
            cell.detailTextLabel?.text = item.detail
            cell.detailTextLabel?.font = .preferredFont(forTextStyle: .footnote)
            cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
            if let symbol = item.symbol {
                cell.imageView?.image = UIImage(systemName: symbol)
            }
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityLabel = [item.title, item.detail]
                .compactMap { $0 }.joined(separator: ", ")
            return cell
        }

        override func tableView(_ tableView: UITableView,
                                didSelectRowAt indexPath: IndexPath) {
            let item = rows[indexPath.row]
            finish(["cancelled": false, "id": item.id,
                    "index": indexPath.row, "sessionID": sessionID])
        }

        @objc private func pulledToRefresh() {
            refresh(sessionID)
        }

        @objc private func done() {
            finish(["cancelled": true, "sessionID": sessionID])
        }

        func finish(_ value: [String: Any]) {
            guard let callback else { return }
            self.callback = nil
            navigationController?.dismiss(animated: true) {
                callback(value)
            }
        }
    }
}
