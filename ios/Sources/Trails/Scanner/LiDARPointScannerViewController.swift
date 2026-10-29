import UIKit
import ARKit
import SceneKit

final class LiDARPointScannerViewController: UIViewController, ARSessionDelegate {
    var onScanFinished: ((_ filePath: String, _ vertexCount: Int, _ duration: Double, _ fileSize: Int64) -> Void)?
    var onScanCancelled: (() -> Void)?
    var onProgress: ((_ pointCount: Int, _ maxPoints: Int) -> Void)?

    /// The last rendered frame of the 3D point cloud scene, captured just before PLY export.
    /// Available on the main thread immediately after `onScanFinished` fires.
    private(set) var pendingSceneThumbnail: UIImage?

    var maxPoints: Int = 10_000_000
    var voxelSize: Float = 0.01 {
        didSet { accumulator.setVoxelSize(voxelSize) }
    }
    var minimumConfidence: UInt8 = 1 {
        didSet { accumulator.setMinimumConfidence(minimumConfidence) }
    }
    var maxRange: Float = 5.0 {
        didSet { accumulator.setMaxRange(maxRange) }
    }
    var previewPointSize: CGFloat = 5.0

    private var scnView: ARSCNView!
    private let accumulator = PointCloudAccumulator()
    private var isCapturing = false
    private var isAccumulating = false
    private var isPaused = false
    private var scanStartTime: Date?
    private var pauseStartTime: Date?
    private var totalPausedDuration: TimeInterval = 0

    private var pointCloudNode = SCNNode()
    private var previewNode = SCNNode()
    private var lastRenderTime: TimeInterval = 0
    private let renderInterval: TimeInterval = 0.1
    private let previewPointBudget = 180_000

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        applyCurrentScanSettings()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isCapturing = false
        scnView.session.pause()
    }

    private func setupUI() {
        view.backgroundColor = .clear
        scnView = ARSCNView(frame: view.bounds)
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scnView.delegate = self
        scnView.session.delegate = self
        scnView.preferredFramesPerSecond = 60
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = .clear
        scnView.autoenablesDefaultLighting = false
        view.addSubview(scnView)

        pointCloudNode.addChildNode(previewNode)
        scnView.scene.rootNode.addChildNode(pointCloudNode)
    }

    private func startSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = Self.supportedFrameSemantics
        configuration.planeDetection = [.horizontal]
        if let videoFormat = Self.preferredFastCaptureVideoFormat() {
            configuration.videoFormat = videoFormat
        }
        scnView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isCapturing = true
        scanStartTime = Date()
    }

    func applyCurrentScanSettings() {
        let settings = SettingsViewModel.shared
        applyScanSettings(
            pointDensity: settings.pointDensity,
            pointSize: settings.pointSize,
            scanRange: settings.scanRange
        )
    }

    func applyScanSettings(pointDensity: PointDensity, pointSize: PointSize, scanRange: ScanRange) {
        voxelSize = pointDensity.liveVoxelSize
        minimumConfidence = pointDensity.minimumConfidenceRaw
        maxRange = scanRange.meters
        previewPointSize = CGFloat(pointSize.livePreviewPointSize)
        maxPoints = 12_000_000
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isCapturing else { return }

        if isAccumulating && !isPaused {
            accumulator.addFrame(frame)
        }

        let now = CACurrentMediaTime()
        if now - lastRenderTime > renderInterval {
            lastRenderTime = now
            updateVisualization()
        }
    }

    private func updateVisualization() {
        let totalCount = accumulator.pointCount
        let (points, colors) = accumulator.previewSnapshot(maxPoints: previewPointBudget)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isAccumulating && !self.isPaused {
                self.onProgress?(totalCount, self.maxPoints)
            }
            self.renderPreview(points: points, colors: colors)
            if self.isAccumulating && totalCount >= self.maxPoints {
                self.stopScan()
            }
        }
    }

    private var lastPreviewCount = 0

    private func renderPreview(points: [SIMD3<Float>], colors: [SIMD3<UInt8>]) {
        guard points.count == colors.count else { return }
        guard !points.isEmpty else {
            previewNode.geometry = nil
            lastPreviewCount = 0
            return
        }
        // Skip rebuild if count hasn't changed (avoids wasted work between frames)
        guard points.count != lastPreviewCount else { return }
        lastPreviewCount = points.count

        let vertices = points.map { SCNVector3($0.x, $0.y, $0.z) }
        let vertexSource = SCNGeometrySource(vertices: vertices)

        var floatColors = [Float](repeating: 1.0, count: colors.count * 4)
        for index in 0..<colors.count {
            let displayColor = sceneDisplayColor(
                fromSRGB: SIMD3<Float>(
                    Float(colors[index].x) / 255.0,
                    Float(colors[index].y) / 255.0,
                    Float(colors[index].z) / 255.0
                )
            )
            floatColors[index * 4]     = displayColor.x
            floatColors[index * 4 + 1] = displayColor.y
            floatColors[index * 4 + 2] = displayColor.z
        }

        let colorData = floatColors.withUnsafeBufferPointer { buffer in
            Data(bytes: buffer.baseAddress!, count: buffer.count * MemoryLayout<Float>.size)
        }
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4)

        // Sequential element — no index array (saves ~48 MB per rebuild at maxPoints)
        let element = SCNGeometryElement(
            data: nil,
            primitiveType: .point,
            primitiveCount: points.count,
            bytesPerIndex: 0)

        element.pointSize = previewPointSize
        element.minimumPointScreenSpaceRadius = max(1.5, previewPointSize * 0.45)
        element.maximumPointScreenSpaceRadius = 12.0

        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        geometry.shaderModifiers = [.fragment: fragmentModifier]
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.readsFromDepthBuffer = false
        material.writesToDepthBuffer = false
        material.blendMode = .alpha
        geometry.materials = [material]
        previewNode.geometry = geometry
    }

    private func sceneDisplayColor(fromSRGB color: SIMD3<Float>) -> SIMD3<Float> {
        let linear = SIMD3<Float>(
            srgbToLinear(color.x),
            srgbToLinear(color.y),
            srgbToLinear(color.z)
        )
        let luma = simd_dot(linear, SIMD3<Float>(0.2126, 0.7152, 0.0722))
        let saturated = SIMD3<Float>(repeating: luma) + (linear - SIMD3<Float>(repeating: luma)) * 1.12
        return SIMD3<Float>(
            clamp01(saturated.x * 0.68),
            clamp01(saturated.y * 0.68),
            clamp01(saturated.z * 0.68)
        )
    }

    private func srgbToLinear(_ value: Float) -> Float {
        let clamped = clamp01(value)
        if clamped <= 0.04045 {
            return clamped / 12.92
        }
        return pow((clamped + 0.055) / 1.055, 2.4)
    }

    private func clamp01(_ value: Float) -> Float {
        min(1, max(0, value))
    }

    @objc func startAccumulatingPoints() {
        accumulator.reset()
        previewNode.geometry = nil
        lastPreviewCount = 0
        isAccumulating = true
        isPaused = false
        totalPausedDuration = 0
        scanStartTime = Date()
    }

    @objc func pauseScan() {
        guard isAccumulating, !isPaused else { return }
        isPaused = true
        pauseStartTime = Date()
    }

    @objc func resumeScan() {
        guard isAccumulating, isPaused else { return }
        if let pauseStartTime {
            totalPausedDuration += Date().timeIntervalSince(pauseStartTime)
        }
        isPaused = false
        self.pauseStartTime = nil
    }

    @objc func takePhoto(completion: @escaping (String?) -> Void) {
        guard let frame = scnView.session.currentFrame else {
            completion(nil)
            return
        }

        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            completion(nil)
            return
        }

        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = image.jpegData(compressionQuality: 0.85) else {
                completion(nil)
                return
            }

            let filename = "snapshot_\(Int(Date().timeIntervalSince1970)).jpg"
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsDirectory.appendingPathComponent(filename)

            do {
                try data.write(to: fileURL)
                completion(fileURL.path)
            } catch {
                completion(nil)
            }
        }
    }

    @objc func stopScan() {
        guard isAccumulating else { return }
        isAccumulating = false

        // Capture the rendered 3D scene on the main thread before going off-thread for PLY export
        pendingSceneThumbnail = captureSceneSnapshot()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let url = self.accumulator.exportPLY() else {
                DispatchQueue.main.async {
                    self.onScanCancelled?()
                }
                return
            }

            let count = self.accumulator.pointCount
            let actualDuration = Date().timeIntervalSince(self.scanStartTime ?? .now) - self.totalPausedDuration
            let duration = max(0.1, actualDuration)
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            DispatchQueue.main.async {
                self.onScanFinished?(url.path, count, duration, fileSize)
            }
        }
    }

    /// Returns a UIImage snapshot of the live Metal-rendered 3D point cloud scene.
    /// Must be called on the main thread.
    func captureSceneSnapshot() -> UIImage? {
        guard scnView != nil else { return nil }
        let image = scnView.snapshot()
        return image
    }

    @objc func cancelScan() {
        isAccumulating = false
        accumulator.reset()
        previewNode.geometry = nil
        lastPreviewCount = 0
        onScanCancelled?()
    }

    private var fragmentModifier: String {
        """
        float2 coord = _surface.pointCoord - float2(0.5);
        if (length(coord) > 0.5) {
            discard;
        }

        _output.color.a = 1.0;
        """
    }

    private static let supportedFrameSemantics: ARConfiguration.FrameSemantics = {
        var semantics: ARConfiguration.FrameSemantics = []
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            semantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            semantics.insert(.smoothedSceneDepth)
        }
        return semantics
    }()

    private static func preferredFastCaptureVideoFormat() -> ARConfiguration.VideoFormat? {
        ARWorldTrackingConfiguration.supportedVideoFormats
            .filter { $0.imageResolution.width >= 1920 }
            .sorted { lhs, rhs in
                if lhs.framesPerSecond != rhs.framesPerSecond {
                    return lhs.framesPerSecond > rhs.framesPerSecond
                }

                let lhsPixels = lhs.imageResolution.width * lhs.imageResolution.height
                let rhsPixels = rhs.imageResolution.width * rhs.imageResolution.height
                return lhsPixels < rhsPixels
            }
            .first
    }
}

extension LiDARPointScannerViewController: ARSCNViewDelegate {}
