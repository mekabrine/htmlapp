import ImageIO
import MultipeerConnectivity
import SwiftUI
import UIKit

struct NearbyDevice: Identifiable {
    let id: MCPeerID
    let name: String
    let isTablet: Bool
    let token: String
    var turn: UInt8
}

struct NearbyOffer: Identifiable {
    let id = UUID()
    let sender: String
    let names: [String]
    let preview: UIImage?

    var title: String { names.count == 1 ? names[0] : "\(names.count) apps" }
}

final class NearbyAppTransfer: NSObject, ObservableObject, MCSessionDelegate,
                               MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    private static let service = "htmlapp-share"
    private static let offerHandshake = Data("HTMLAPP_OFFER_V2".utf8)
    private static let accepted = Data("HTMLAPP_ACCEPTED_V2".utf8)
    private static let declined = Data("HTMLAPP_DECLINED_V2".utf8)
    private static let importReceipt = Data("HTMLAPP_IMPORTED_V2".utf8)
    private static let archiveName = "HTMLApp.htmlapp.zip"
    private static let maxPreviewBytes = 150_000
    static let maximumArchiveBytes = 100_000_000

    private struct OfferPacket: Codable {
        let names: [String]
        let preview: Data?
    }

    @Published private(set) var devices: [NearbyDevice] = []
    @Published private(set) var offer: NearbyOffer?
    @Published private(set) var received: URL?
    @Published private(set) var acceptedByReceiver = false
    @Published private(set) var recipientConfirmed = false
    @Published private(set) var sendingBusy = false
    @Published private(set) var transferActive = false
    @Published var status = ""
    @Published var receiverScreenVisible = false
    @Published var isSaving = false

    private let motion = NearbyDeviceOrientation()
    private let token = UUID().uuidString.lowercased()
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var session: MCSession?
    private var peer: MCPeerID?
    private var outgoingOffer: Data?
    private var outbound: URL?
    private var authorizedInbound = false
    private var incomingResource = false
    private let inboundLock = NSLock()
    private var inboundTicket: (session: MCSession, peer: MCPeerID, started: Bool)?
    private var libraryVisible = false

    static var displayName: String {
        let alias = UserDefaults.standard.string(forKey: "htmlapp.nearbyDeviceName") ?? ""
        return clippedName(alias.isEmpty ? UIDevice.current.name : alias, maxBytes: 56, fallback: "Apple device")
    }

    static func setDisplayName(_ name: String) {
        let clean = clippedName(name, maxBytes: 56, fallback: "")
        UserDefaults.standard.set(clean, forKey: "htmlapp.nearbyDeviceName")
    }

    private static func clippedName(_ name: String, maxBytes: Int, fallback: String) -> String {
        var value = ""
        for char in name.trimmingCharacters(in: .whitespacesAndNewlines)
            where char.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            if value.utf8.count + String(char).utf8.count > maxBytes { break }
            value.append(char)
        }
        return value.isEmpty ? fallback : value
    }

    override init() {
        super.init()
        motion.onChange = { [weak self] in
            guard let self else { return }
            self.devices = self.devices.map { device in
                var updated = device
                updated.turn = self.motion.turns[device.token] ?? 0
                return updated
            }
        }
    }

    func setLibraryVisible(_ visible: Bool) {
        libraryVisible = visible
        if visible {
            startAdvertising()
        } else {
            stopAdvertising()
            if outgoingOffer == nil && received == nil { resetSession() }
        }
    }

    func restartDiscovery() {
        stopAdvertising()
        let wasBrowsing = browser != nil
        stopBrowsing()
        if wasBrowsing { startBrowsing() }
        else { startAdvertising() }
    }

    private func startAdvertising() {
        guard libraryVisible, browser == nil, advertiser == nil else { return }
        let local = MCPeerID(displayName: Self.displayName)
        let details = ["version": "2", "token": token, "type": UIDevice.current.userInterfaceIdiom == .pad ? "pad" : "phone"]
        let service = MCNearbyServiceAdvertiser(peer: local, discoveryInfo: details, serviceType: Self.service)
        advertiser = service
        service.delegate = self
        service.startAdvertisingPeer()
        motion.advertise(token: token)
    }

    private func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        motion.stopAdvertising()
    }

    func startBrowsing() {
        guard browser == nil else { return }
        resetSession()
        stopAdvertising()
        let service = MCNearbyServiceBrowser(peer: MCPeerID(displayName: Self.displayName), serviceType: Self.service)
        browser = service
        service.delegate = self
        service.startBrowsingForPeers()
        motion.browse()
        status = "Looking for nearby devices…"
    }

    private func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        motion.stopBrowsing()
        devices = []
    }

    func endSending() {
        stopBrowsing()
        resetSession()
        startAdvertising()
    }

    func invite(_ device: NearbyDevice, names: [String], preview: Data?) {
        guard let browser, session == nil, devices.contains(where: { $0.id == device.id }) else {
            status = "That device is no longer nearby. Choose a device again."
            return
        }
        let packet = OfferPacket(names: names.prefix(30).map { Self.clippedName($0, maxBytes: 180, fallback: "HTML app") },
                                 preview: preview.flatMap { $0.count <= Self.maxPreviewBytes ? $0 : nil })
        guard !packet.names.isEmpty, let bytes = try? JSONEncoder().encode(packet) else { return }
        let session = connect(local: browser.myPeerID, remote: device.id)
        outgoingOffer = bytes
        status = "Waiting for \(device.name) to respond…"
        browser.invitePeer(device.id, to: session, withContext: Self.offerHandshake, timeout: 20)
        expire(session, after: 60, message: "No response. You can choose the device again.") {
            !$0.acceptedByReceiver
        }
    }

    private func connect(local: MCPeerID, remote: MCPeerID) -> MCSession {
        let session = MCSession(peer: local, securityIdentity: nil, encryptionPreference: .required)
        self.session = session
        peer = remote
        session.delegate = self
        transferActive = true
        return session
    }

    private func expire(_ connection: MCSession, after seconds: Double, message: String, when shouldExpire: @escaping (NearbyAppTransfer) -> Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self, weak connection] in
            guard let self, let connection, self.session === connection, shouldExpire(self) else { return }
            self.resetSession()
            self.status = message
        }
    }

    private func resetSession(preserveReceipt: Bool = false) {
        let old = session
        session = nil
        setInboundTicket(nil)
        old?.disconnect()
        peer = nil
        offer = nil
        outgoingOffer = nil
        authorizedInbound = false
        incomingResource = false
        acceptedByReceiver = false
        if !preserveReceipt { recipientConfirmed = false }
        transferActive = false
        sendingBusy = false
        if let outbound { try? FileManager.default.removeItem(at: outbound) }
        outbound = nil
    }

    func answer(_ accept: Bool) {
        guard offer != nil, let session, let peer else { return }
        offer = nil
        authorizedInbound = accept
        if accept { setInboundTicket((session, peer, false)) }
        do {
            try session.send(accept ? Self.accepted : Self.declined, toPeers: [peer], with: .reliable)
            status = accept ? "Receiving app…" : "Transfer declined."
            // Give the reliable response time to leave before disconnecting.
            if !accept {
                expire(session, after: 1, message: "Transfer declined.") { _ in true }
            } else {
                expire(session, after: 90, message: "The sender didn’t finish the transfer.") { !$0.incomingResource }
            }
        } catch {
            resetSession()
            status = "The sender disconnected."
        }
    }

    func send(_ url: URL) {
        guard let session, let peer, acceptedByReceiver, !sendingBusy else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        outbound = url
        sendingBusy = true
        status = "Sending app without saved data…"
        expire(session, after: 120, message: "The transfer timed out.") { $0.sendingBusy }
        session.sendResource(at: url, withName: Self.archiveName, toPeer: peer) { [weak self, weak session] error in
            DispatchQueue.main.async {
                guard let self, let session, self.session === session else { return }
                try? FileManager.default.removeItem(at: url)
                self.outbound = nil
                self.sendingBusy = false
                if self.recipientConfirmed { return }
                if let error {
                    self.resetSession()
                    self.status = "Transfer failed: \(error.localizedDescription)"
                } else {
                    self.status = "Sent. Waiting for the receiving device to save it…"
                    self.expire(session, after: 90, message: "The receiving device didn’t confirm saving.") { !$0.recipientConfirmed }
                }
            }
        }
    }

    func failSending(_ message: String) {
        resetSession()
        status = message
    }

    func finishImport(success: Bool, message: String) {
        if success, let session, let peer {
            try? session.send(Self.importReceipt, toPeers: [peer], with: .reliable)
        }
        if let received { try? FileManager.default.removeItem(at: received) }
        received = nil
        isSaving = false
        status = message
        if let session {
            expire(session, after: 1, message: message) { _ in true }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            guard self.browser === browser, info?["version"] == "2",
                  let token = info?["token"], token != self.token,
                  UUID(uuidString: token) != nil else { return }
            let isTablet = info?["type"] == "pad"
            let device = NearbyDevice(id: peerID, name: peerID.displayName, isTablet: isTablet,
                                      token: token, turn: self.motion.turns[token] ?? 0)
            self.devices.removeAll { $0.id == peerID }
            self.devices.append(device)
            self.devices.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            guard self.browser === browser else { return }
            self.devices.removeAll { $0.id == peerID }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            guard self.browser === browser else { return }
            self.status = "Can’t find nearby devices. Check Local Network access in Settings."
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            guard self.advertiser === advertiser, self.libraryVisible, self.session == nil,
                  context == Self.offerHandshake else { invitationHandler(false, nil); return }
            // Open only the encrypted control channel. App bytes are sent after Receive.
            let session = self.connect(local: advertiser.myPeerID, remote: peerID)
            invitationHandler(true, session)
            self.expire(session, after: 22, message: "The sender didn’t deliver a preview.") {
                $0.offer == nil && !$0.authorizedInbound
            }
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            guard self.advertiser === advertiser else { return }
            self.status = "Nearby receiving is unavailable. Check Local Network access in Settings."
        }
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            guard self.session === session, self.peer == peerID else { return }
            if state == .connected, let offer = self.outgoingOffer {
                do { try session.send(offer, toPeers: [peerID], with: .reliable) }
                catch { self.failSending("Couldn’t send the preview. Choose the device again.") }
            } else if state == .notConnected {
                if self.received != nil { return }
                self.resetSession(preserveReceipt: true)
                if !self.recipientConfirmed { self.status = "The device disconnected. You can try again." }
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            guard self.session === session, self.peer == peerID else { return }
            if self.outgoingOffer != nil {
                switch data {
                case Self.accepted: self.acceptedByReceiver = true
                case Self.declined: self.failSending("\(peerID.displayName) declined the transfer.")
                case Self.importReceipt where self.acceptedByReceiver:
                    self.recipientConfirmed = true
                    self.status = "The other device saved your app!"
                default: break
                }
                return
            }

            guard self.libraryVisible, self.offer == nil, !self.authorizedInbound,
                  data.count <= 210_000,
                  let packet = try? JSONDecoder().decode(OfferPacket.self, from: data),
                  (1...30).contains(packet.names.count) else { return }
            let names = packet.names.map { Self.clippedName($0, maxBytes: 180, fallback: "HTML app") }
            self.offer = NearbyOffer(sender: peerID.displayName, names: names, preview: Self.decodePreview(packet.preview))
            self.expire(session, after: 50, message: "The nearby offer expired.") { $0.offer != nil }
        }
    }

    private static func decodePreview(_ data: Data?) -> UIImage? {
        guard let data, data.count <= maxPreviewBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let attributes = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = attributes[kCGImagePropertyPixelWidth] as? Int,
              let height = attributes[kCGImagePropertyPixelHeight] as? Int,
              (1...1_024).contains(width), (1...1_024).contains(height), abs(width - height) <= 2 else { return nil }
        return UIImage(data: data)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        stream.close()
    }

    private func setInboundTicket(_ ticket: (session: MCSession, peer: MCPeerID, started: Bool)?) {
        inboundLock.lock()
        inboundTicket = ticket
        inboundLock.unlock()
    }

    private func claimInboundResource(session: MCSession, peer: MCPeerID, starting: Bool) -> Bool {
        inboundLock.lock()
        defer { inboundLock.unlock() }
        guard let ticket = inboundTicket, ticket.session === session,
              ticket.peer == peer, ticket.started != starting else { return false }
        inboundTicket = starting ? (session, peer, true) : nil
        return true
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        guard resourceName == Self.archiveName, progress.totalUnitCount <= Int64(Self.maximumArchiveBytes),
              claimInboundResource(session: session, peer: peerID, starting: true) else {
            progress.cancel()
            return
        }
        DispatchQueue.main.async {
            guard self.session === session, self.peer == peerID, self.authorizedInbound else { return }
            self.incomingResource = true
            self.expire(session, after: 120, message: "The transfer timed out.") {
                $0.received == nil && $0.authorizedInbound
            }
        }
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        guard resourceName == Self.archiveName,
              claimInboundResource(session: session, peer: peerID, starting: false) else { return }
        do {
            if let error { throw error }
            guard let localURL, let size = try localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  (1...Self.maximumArchiveBytes).contains(size) else { throw HTMLAppPackageError.invalidArchive }
            // Multipeer removes the supplied URL when this callback returns.
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Nearby-\(UUID().uuidString).zip")
            try FileManager.default.copyItem(at: localURL, to: destination)
            DispatchQueue.main.async {
                guard self.session === session, self.peer == peerID, self.authorizedInbound, self.received == nil else {
                    try? FileManager.default.removeItem(at: destination)
                    return
                }
                self.authorizedInbound = false
                self.received = destination
            }
        } catch {
            DispatchQueue.main.async {
                guard self.session === session else { return }
                self.resetSession()
                self.status = "Receive failed: \(error.localizedDescription)"
            }
        }
    }

}

private struct NearbyOfferPopup: View {
    let offer: NearbyOffer
    let answer: (Bool) -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.5)).ignoresSafeArea()
            ViewThatFits(in: .vertical) {
                card
                ScrollView { card }
            }
            .frame(maxWidth: 420)
            .padding(20)
        }
        .accessibilityElement(children: .contain)
    }

    private var card: some View {
        VStack(spacing: 16) {
            Text("\(offer.sender) would like to send you \(offer.title).")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            if let image = offer.preview {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Preview of \(offer.names[0])")
                if offer.names.count > 1 {
                    Text("Preview of \(offer.names[0])")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("Preview unavailable", systemImage: "photo")
                    .foregroundStyle(.secondary)
            }
            if offer.names.count > 1 {
                Text(offer.names.joined(separator: ", "))
                    .font(.footnote)
                    .lineLimit(3)
            }
            Text("The sender supplied this preview. Receive apps only from devices you recognize.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Decline", role: .cancel) { answer(false) }
                    .buttonStyle(.bordered)
                Button("Receive") { answer(true) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct NearbyLibraryReceiver: ViewModifier {
    @ObservedObject var transfer: NearbyAppTransfer
    let enabled: Bool
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(transfer.offer != nil && !transfer.receiverScreenVisible)
            .task(id: enabled && scenePhase != .background) {
                transfer.setLibraryVisible(enabled && scenePhase != .background)
            }
            .overlay {
                if let offer = transfer.offer, !transfer.receiverScreenVisible {
                    NearbyOfferPopup(offer: offer, answer: transfer.answer)
                }
            }
            .onChange(of: transfer.received) { url in
                guard let url, !transfer.isSaving else { return }
                transfer.isSaving = true
                Task { @MainActor in
                    do {
                        try store.importPortablePackage(from: url, replaceExisting: false, includePersonalData: false)
                        transfer.finishImport(success: true, message: "App saved to Library!")
                        store.notice = "Nearby transfer saved to your Library."
                    } catch {
                        let message = "Couldn’t save the received app: \(error.localizedDescription)"
                        transfer.finishImport(success: false, message: message)
                        if !transfer.receiverScreenVisible { store.errorMessage = message }
                    }
                }
            }
    }
}

struct NearbyAppTransferView: View {
    let appIDs: Set<String>
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var transfer: NearbyAppTransfer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chosenDevice: NearbyDevice?
    @State private var editingName = false
    @State private var deviceName = ""
    @State private var previewApps: [SavedHTMLApp] = []
    @State private var sentAppIDs = Set<String>()

    private var sending: Bool { !appIDs.isEmpty }

    var body: some View {
        List {
            if sending {
                senderContent
            } else {
                Section("Receive nearby") {
                    Label("Ready to receive in the Library", systemImage: "dot.radiowaves.left.and.right")
                    Text("Keep HTMLApp open in the Library. Incoming offers appear here and in the Library.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if transfer.isSaving { ProgressView("Saving to your Library…") }
                }
            }
            if !transfer.status.isEmpty {
                Section { Text(transfer.status).foregroundStyle(.secondary) }
            }
            Section {
                Button {
                    deviceName = NearbyAppTransfer.displayName
                    editingName = true
                } label: {
                    LabeledContent("Your device name", value: NearbyAppTransfer.displayName)
                }
                .disabled(transfer.transferActive || chosenDevice != nil)
            } footer: {
                Text("If iOS supplies a generic name like iPhone, you can enter the name from Settings → General → About → Name. It’s used only for Nearby Transfer.")
            }
        }
        .navigationTitle(sending ? "Choose Nearby Device" : "Nearby Transfer")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Nearby device name", isPresented: $editingName) {
            TextField("Device name", text: $deviceName)
            Button("Save") {
                NearbyAppTransfer.setDisplayName(deviceName)
                transfer.restartDiscovery()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Leave it blank to use the name provided by iOS.")
        }
        .accessibilityHidden(!sending && transfer.offer != nil)
        .overlay {
            if !sending, let offer = transfer.offer {
                NearbyOfferPopup(offer: offer, answer: transfer.answer)
            }
        }
        .onAppear {
            transfer.receiverScreenVisible = !sending
            if sending { transfer.startBrowsing() }
        }
        .onChange(of: scenePhase) { phase in
            guard sending else { return }
            if phase == .background {
                chosenDevice = nil
                transfer.endSending()
            } else if phase == .active {
                transfer.startBrowsing()
            }
        }
        .onDisappear {
            transfer.receiverScreenVisible = false
            if sending { transfer.endSending() }
        }
        .onChange(of: transfer.acceptedByReceiver) { accepted in
            if accepted && sending { sendSelectedApps() }
        }
        .onChange(of: transfer.recipientConfirmed) { confirmed in
            guard confirmed, sending else { return }
            for appID in sentAppIDs {
                ForgeConversationLog.append(appID, kind: "share", text: "Nearby recipient confirmed importing this app.")
            }
            dismiss()
        }
    }

    @ViewBuilder
    private var senderContent: some View {
        Section {
            if transfer.devices.isEmpty && transfer.status == "Looking for nearby devices…" {
                ProgressView("Looking for nearby devices…")
            }
            ForEach(transfer.devices) { device in
                Button {
                    prepareOffer(for: device)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: device.isTablet ? "ipad" : "iphone")
                            .font(.system(size: 24))
                            .rotationEffect(.degrees(Double(device.turn) * 90))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: device.turn)
                            .frame(width: 40, height: 42)
                            .accessibilityLabel(device.isTablet ? "iPad" : "iPhone")
                        Text(device.name)
                        Spacer()
                        if chosenDevice?.id == device.id { ProgressView() }
                    }
                }
                .disabled(chosenDevice != nil || transfer.transferActive)
            }
        } header: {
            Text("Devices with HTMLApp open")
        } footer: {
            Text("The other device can stay in its Library. It will see the app preview and choose whether to receive it.")
        }

        if let device = chosenDevice, let app = previewApps.first {
            Section("Preparing preview") {
                NearbyAppPreview(html: HTMLAppRuntimeBackend.sharedHTML(app.html, localID: app.id)) { data in
                    guard chosenDevice?.id == device.id else { return }
                    chosenDevice = nil
                    transfer.invite(device, names: previewApps.map(\.name), preview: data)
                }
                .id(device.id)
                .frame(width: 220, height: 220)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                ProgressView("Preparing offer for \(device.name)…")
            }
        } else if transfer.transferActive {
            Section { ProgressView(transfer.sendingBusy ? "Sending app…" : "Waiting for the receiving device…") }
        }
    }

    private func prepareOffer(for device: NearbyDevice) {
        guard chosenDevice == nil, !transfer.transferActive else { return }
        let apps = store.orderedApps.filter { appIDs.contains($0.id) }
        guard !apps.isEmpty, apps.count <= 30 else {
            transfer.status = apps.isEmpty ? "These apps are no longer in your Library." : "Select 30 apps or fewer to send together."
            return
        }
        previewApps = apps
        chosenDevice = device
    }

    private func sendSelectedApps() {
        let reviewed = previewApps
        let reviewedIDs = Set(reviewed.map(\.id))
        guard !reviewedIDs.isEmpty,
              reviewed.allSatisfy({ reviewedApp in
                store.apps.contains { $0.id == reviewedApp.id && $0.updatedAt == reviewedApp.updatedAt &&
                        $0.name == reviewedApp.name && $0.html == reviewedApp.html }
              }) else {
            transfer.failSending("An app changed after its preview was made. Choose the device to create a new offer.")
            return
        }
        do {
            let url = try store.createNearbyPackage(appIDs: reviewedIDs)
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard let size, (1...NearbyAppTransfer.maximumArchiveBytes).contains(size) else {
                try? FileManager.default.removeItem(at: url)
                transfer.failSending("The package is unavailable or exceeds the 100 MB transfer limit.")
                return
            }
            sentAppIDs = reviewedIDs
            transfer.send(url)
        } catch {
            transfer.failSending("Couldn’t prepare the apps: \(error.localizedDescription)")
        }
    }
}
