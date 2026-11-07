import UIKit
import RealityKit
import ARKit
import WebKit

/// Foreground, bounded primitive scene. No downloaded executable scene code.
@MainActor
final class HTMLAppNativeScene: NSObject {
    private weak var webView: WKWebView?
    private var view: ARView?
    private var backgroundObserver: NSObjectProtocol?
    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }
    func shutdown() {
        hide()
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        backgroundObserver = nil
    }
    func hide() { view?.session.pause(); view?.removeFromSuperview(); view = nil }
    func show(_ args: [String: Any]) throws {
        guard let webView, let host = webView.superview,
              let frame = args["frame"] as? [String: Any],
              let x = frame["x"] as? Double, let y = frame["y"] as? Double,
              let w = frame["width"] as? Double, let h = frame["height"] as? Double,
              [x,y,w,h].allSatisfy({ $0.isFinite }), x >= 0, y >= 0, w >= 44, h >= 44,
              x+w <= Double(webView.bounds.width)+1, y+h <= Double(webView.bounds.height)+1,
              let objects = args["objects"] as? [[String: Any]], objects.count <= 100 else { throw Failure.invalid }
        let ar = args["ar"] as? Bool ?? false
        if ar && !ARWorldTrackingConfiguration.isSupported { throw Failure.unavailable }
        let anchor = AnchorEntity(world: .zero)
        for item in objects {
            guard let id = item["id"] as? String, !id.isEmpty, id.count <= 80,
                  let position = item["position"] as? [Double], position.count == 3,
                  position.allSatisfy({ $0.isFinite && abs($0) <= 100 }),
                  let size = item["size"] as? Double, size.isFinite, size >= 0.01, size <= 10 else { throw Failure.invalid }
            let mesh: MeshResource
            switch item["shape"] as? String {
            case "sphere": mesh = .generateSphere(radius: Float(size / 2))
            case "box": mesh = .generateBox(size: Float(size))
            default: throw Failure.invalid
            }
            let color = (item["color"] as? String ?? "3576d3").replacingOccurrences(of: "#", with: "")
            guard color.count == 6, let rgb = UInt32(color, radix: 16) else { throw Failure.invalid }
            let material = SimpleMaterial(color: UIColor(red: CGFloat((rgb >> 16)&255)/255,
                green: CGFloat((rgb >> 8)&255)/255, blue: CGFloat(rgb&255)/255, alpha: 1), isMetallic: false)
            let entity = ModelEntity(mesh: mesh, materials: [material]); entity.name = id
            entity.position = SIMD3<Float>(Float(position[0]), Float(position[1]), Float(position[2]))
            entity.generateCollisionShapes(recursive: false)
            anchor.addChild(entity)
        }
        hide()
        let scene = ARView(frame: .zero, cameraMode: ar ? .ar : .nonAR, automaticallyConfigureSession: false)
        scene.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(scene)
        NSLayoutConstraint.activate([
            scene.leadingAnchor.constraint(equalTo: webView.leadingAnchor, constant: x),
            scene.topAnchor.constraint(equalTo: webView.topAnchor, constant: y),
            scene.widthAnchor.constraint(equalToConstant: w), scene.heightAnchor.constraint(equalToConstant: h)
        ])
        scene.scene.addAnchor(anchor)
        if ar { scene.session.run(ARWorldTrackingConfiguration()) }
        else {
            let camera = PerspectiveCamera(); camera.position = [0,0,3]; anchor.addChild(camera)
        }
        scene.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        view = scene
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let view, let entity = view.entity(at: gesture.location(in: view)),
              let bytes = try? JSONSerialization.data(withJSONObject: ["id": entity.name]),
              let json = String(data: bytes, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('htmlapp:scene-select',{detail:\(json)}));")
    }
    enum Failure: LocalizedError {
        case invalid, unavailable
        var errorDescription: String? { self == .invalid ? "Invalid scene frame or primitive objects." : "AR world tracking is unavailable on this device." }
    }
}
