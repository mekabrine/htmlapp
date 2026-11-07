import AVFoundation
import UIKit
import CoreImage

/// Foreground camera pipeline. Pixel buffers stay native; requested snapshots
/// use a bounded four-file ring instead of base64 messages on every frame.
final class HTMLAppCameraFrames: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "htmlapp.camera.frames")
    private var latest: CVPixelBuffer?
    private var sequence = 0
    private var lastCapture = Date.distantPast
    private var stopped = false
    private let root: URL
    private let context = CIContext()
    private var preview: UIView?
    private var observer: NSObjectProtocol?
    init(root: URL) { self.root = root; super.init() }
    @MainActor func mount(in webView: UIView, frame: [String: Any]) throws {
        guard let host = webView.superview, let x = frame["x"] as? Double, let y = frame["y"] as? Double,
              let width = frame["width"] as? Double, let height = frame["height"] as? Double,
              [x,y,width,height].allSatisfy({ $0.isFinite }), x >= 0, y >= 0, width >= 44, height >= 44,
              x+width <= Double(webView.bounds.width)+1, y+height <= Double(webView.bounds.height)+1 else { throw Failure.invalid }
        let view = PreviewView(session: session)
        view.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(view)
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: webView.leadingAnchor, constant: x),
            view.topAnchor.constraint(equalTo: webView.topAnchor, constant: y),
            view.widthAnchor.constraint(equalToConstant: width), view.heightAnchor.constraint(equalToConstant: height)])
        preview = view
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }
    func start(front: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            do {
                guard !self.stopped, let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back) else { throw Failure.unavailable }
                let input = try AVCaptureDeviceInput(device: device)
                self.session.beginConfiguration(); self.session.sessionPreset = .vga640x480
                let output = AVCaptureVideoDataOutput(); output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                guard self.session.canAddInput(input), self.session.canAddOutput(output) else {
                    self.session.commitConfiguration(); throw Failure.unavailable
                }
                self.session.addInput(input); self.session.addOutput(output)
                output.setSampleBufferDelegate(self, queue: self.queue)
                if let connection = output.connection(with: .video), connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
                self.session.commitConfiguration(); self.session.startRunning()
                guard self.session.isRunning else { throw Failure.unavailable }
                DispatchQueue.main.async { completion(.success(())) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if !stopped { latest = CMSampleBufferGetImageBuffer(sampleBuffer) }
    }
    func frame(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        queue.async {
            do {
                guard !self.stopped, Date().timeIntervalSince(self.lastCapture) >= 0.25, let buffer = self.latest else { throw Failure.noFrame }
                let image = CIImage(cvPixelBuffer: buffer)
                guard let bytes = self.context.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]), bytes.count < 2_000_000 else { throw Failure.noFrame }
                self.lastCapture = Date()
                self.sequence += 1
                let relative = "camera-frames/frame-\(self.sequence % 4).jpg"
                let file = self.root.appendingPathComponent(relative)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: file, options: .atomic)
                let result: [String: Any] = ["url": relative, "sequence": self.sequence, "width": CVPixelBufferGetWidth(buffer), "height": CVPixelBufferGetHeight(buffer), "mimeType": "image/jpeg", "reusedAfterCaptures": 4]
                DispatchQueue.main.async { completion(.success(result)) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
    @MainActor func stop() {
        preview?.removeFromSuperview(); preview = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil
        queue.async { self.stopped = true; self.latest = nil; self.session.stopRunning() }
    }
    private final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        init(session: AVCaptureSession) {
            super.init(frame: .zero)
            let preview = layer as! AVCaptureVideoPreviewLayer; preview.session = session; preview.videoGravity = .resizeAspectFill
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    }
    enum Failure: LocalizedError { case invalid, unavailable, noFrame
        var errorDescription: String? { "Camera frame unavailable: check visible preview bounds, camera permission/hardware, and wait for capture startup." }
    }
}
