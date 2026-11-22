import CoreMotion
import Foundation
import Network

/// Keeps rotation updates separate from Multipeer discovery and transfer consent.
/// This channel sends only a quarter turn, without raw sensor readings or app data.
final class NearbyDeviceOrientation {
    private static let serviceType = "_htmlapp-tilt._tcp"
    private let motion = CMMotionManager()
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var clients: [ObjectIdentifier: NWConnection] = [:]
    private var subscribers: [String: NWConnection] = [:]
    private var timer: Timer?
    private var turn: UInt8 = 0
    private(set) var turns: [String: UInt8] = [:]
    var onChange: (() -> Void)?

    private static func parameters() -> NWParameters {
        let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        parameters.includePeerToPeer = true
        return parameters
    }

    func advertise(token: String) {
        guard listener == nil, let listener = try? NWListener(using: Self.parameters()) else { return }
        self.listener = listener
        listener.service = NWListener.Service(name: token, type: Self.serviceType)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.listener != nil, self.clients.count < 16 else { connection.cancel(); return }
            let id = ObjectIdentifier(connection)
            self.clients[id] = connection
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                switch state {
                case .ready:
                    if let self, let connection { self.sendTurn(to: connection) }
                case .failed(_), .cancelled:
                    self?.clients[id] = nil
                default: break
                }
            }
            connection.start(queue: .main)
        }
        listener.start(queue: .main)
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.25
            motion.startDeviceMotionUpdates()
        }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.sampleOrientation()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func sampleOrientation() {
        guard let gravity = motion.deviceMotion?.gravity, max(abs(gravity.x), abs(gravity.y)) > 0.30 else { return }
        let next: UInt8
        if abs(gravity.x) > abs(gravity.y) {
            next = gravity.x > 0 ? 3 : 1
        } else {
            next = gravity.y > 0 ? 2 : 0
        }
        guard turn != next else { return }
        turn = next
        for connection in clients.values { sendTurn(to: connection) }
    }

    private func sendTurn(to connection: NWConnection) {
        connection.send(content: Data([turn]), completion: .contentProcessed { error in
            if error != nil { connection.cancel() }
        })
    }

    func browse() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: Self.parameters())
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            guard let self, let browser, self.browser === browser else { return }
            var endpoints: [String: NWEndpoint] = [:]
            for result in results {
                if case let .service(name, _, _, _) = result.endpoint, UUID(uuidString: name) != nil {
                    endpoints[name] = result.endpoint
                }
            }
            for token in Array(self.subscribers.keys) where endpoints[token] == nil {
                self.subscribers.removeValue(forKey: token)?.cancel()
                self.turns[token] = nil
            }
            for (token, endpoint) in endpoints where self.subscribers[token] == nil && self.subscribers.count < 16 {
                let connection = NWConnection(to: endpoint, using: Self.parameters())
                self.subscribers[token] = connection
                connection.stateUpdateHandler = { [weak self, weak connection] state in
                    guard let self, let connection, self.subscribers[token] === connection else { return }
                    switch state {
                    case .ready: self.readTurn(from: connection, token: token)
                    case .failed(_), .cancelled:
                        self.subscribers[token] = nil
                        self.turns[token] = nil
                        self.onChange?()
                    default: break
                    }
                }
                connection.start(queue: .main)
            }
            self.onChange?()
        }
        browser.start(queue: .main)
    }

    private func readTurn(from connection: NWConnection, token: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self, weak connection] data, _, complete, error in
            guard let self, let connection, self.subscribers[token] === connection else { return }
            if let value = data?.first, value < 4, self.turns[token] != value {
                self.turns[token] = value
                self.onChange?()
            }
            if complete || error != nil { connection.cancel() }
            else { self.readTurn(from: connection, token: token) }
        }
    }

    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        for connection in clients.values { connection.cancel() }
        clients.removeAll()
        timer?.invalidate()
        timer = nil
        motion.stopDeviceMotionUpdates()
        turn = 0
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        for connection in subscribers.values { connection.cancel() }
        subscribers.removeAll()
        turns.removeAll()
    }
}
