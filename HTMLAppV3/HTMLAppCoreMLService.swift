import Foundation
import CoreML
import Vision

actor HTMLAppCoreMLService {
    private let root: URL
    private var models: [String: VNCoreMLModel] = [:]
    init(root: URL) { self.root = root.resolvingSymlinksInPath() }
    private func local(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard !path.hasPrefix("/"), !path.contains(".."), url.path.hasPrefix(root.path + "/"),
              FileManager.default.fileExists(atPath: url.path) else { throw Failure.invalid }
        return url
    }
    func load(path: String) async throws -> [String: Any] {
        await HTMLAppGPUCache.maintenance.value
        return try loadAfterMaintenance(path: path)
    }

    // Keep compilation and model registration in one actor turn so parallel
    // loads cannot both claim the last available model slot.
    private func loadAfterMaintenance(path: String) throws -> [String: Any] {
        try Task.checkCancellation()
        guard models.count < 2 else { throw Failure.limit }
        let source = try local(path)
        guard ["mlmodel", "mlmodelc"].contains(source.pathExtension) else { throw Failure.invalid }
        let compiled: URL
        let temporary = source.pathExtension == "mlmodel"
        if temporary {
            guard let size = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 100_000_000 else { throw Failure.limit }
            compiled = try MLModel.compileModel(at: source)
        } else { compiled = source }
        defer { if temporary { try? FileManager.default.removeItem(at: compiled) } }
        let config = MLModelConfiguration(); config.computeUnits = .all
        let model = try MLModel(contentsOf: compiled, configuration: config)
        let vision = try VNCoreMLModel(for: model)
        try Task.checkCancellation()
        let id = UUID().uuidString; models[id] = vision
        return ["id": id, "inputs": Array(model.modelDescription.inputDescriptionsByName.keys), "outputs": Array(model.modelDescription.outputDescriptionsByName.keys)]
    }
    func infer(id: String, imagePath: String) throws -> [String: Any] {
        try Task.checkCancellation()
        guard let model = models[id] else { throw Failure.invalid }
        let image = try local(imagePath)
        guard let size = try? image.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8_000_000 else { throw Failure.limit }
        let request = VNCoreMLRequest(model: model); request.imageCropAndScaleOption = .centerCrop
        try VNImageRequestHandler(url: image, options: [:]).perform([request])
        try Task.checkCancellation()
        if let results = request.results as? [VNClassificationObservation] {
            return ["kind": "classification", "results": results.prefix(20).map { ["label": $0.identifier, "confidence": $0.confidence] as [String: Any] }]
        }
        if let results = request.results as? [VNRecognizedObjectObservation] {
            return ["kind": "objects", "results": results.prefix(50).map { observation -> [String: Any] in
                let box = observation.boundingBox
                return ["label": observation.labels.first?.identifier ?? "", "confidence": observation.confidence,
                        "box": ["x": box.origin.x, "y": box.origin.y, "width": box.width, "height": box.height]]
            }]
        }
        throw Failure.unsupported
    }
    func unload(id: String) { models.removeValue(forKey: id) }
    enum Failure: LocalizedError { case invalid, limit, unsupported
        var errorDescription: String? { "Core ML requires an app-owned image model (.mlmodel or .mlmodelc), at most two loaded models, and classification/detection outputs. Check local paths and size limits." }
    }
}
