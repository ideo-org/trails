import SwiftUI
import SceneKit
import UIKit
import simd

struct TrailsPointCloudView: UIViewRepresentable {
    let filePath: String

    func makeUIView(context: Context) -> TrailsPointCloudContainerView {
        let view = TrailsPointCloudContainerView()
        context.coordinator.load(filePath: filePath, into: view)
        return view
    }

    func updateUIView(_ uiView: TrailsPointCloudContainerView, context: Context) {
        context.coordinator.load(filePath: filePath, into: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var loadedPath: String?

        func load(filePath: String, into view: TrailsPointCloudContainerView) {
            guard loadedPath != filePath else { return }
            loadedPath = filePath
            view.load(filePath: filePath)
        }
    }
}

final class TrailsPointCloudContainerView: UIView {
    private let sceneView = SCNView(frame: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func load(filePath: String) {
        do {
            let parsed = try RawPLYParser.pointCloud(from: URL(fileURLWithPath: filePath))
            sceneView.scene = makeScene(geometry: parsed.geometry, bounds: parsed.bounds)
            resetCamera(bounds: parsed.bounds)
        } catch {
            sceneView.scene = makeErrorScene()
        }
    }

    private func configure() {
        backgroundColor = UIColor(red: 0.082, green: 0.087, blue: 0.095, alpha: 1)
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.backgroundColor = backgroundColor
        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = false
        sceneView.antialiasingMode = .multisampling2X
        sceneView.preferredFramesPerSecond = 60
        addSubview(sceneView)

        NSLayoutConstraint.activate([
            sceneView.leadingAnchor.constraint(equalTo: leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: trailingAnchor),
            sceneView.topAnchor.constraint(equalTo: topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func makeScene(geometry: SCNGeometry, bounds: RawPointCloudBounds) -> SCNScene {
        let scene = SCNScene()
        let cloudNode = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(cloudNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 140
        scene.rootNode.addChildNode(ambient)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.name = "Camera"
        scene.rootNode.addChildNode(cameraNode)

        let focusNode = SCNNode()
        focusNode.name = "Focus"
        focusNode.simdPosition = bounds.center
        scene.rootNode.addChildNode(focusNode)

        let lookAt = SCNLookAtConstraint(target: focusNode)
        lookAt.isGimbalLockEnabled = true
        cameraNode.constraints = [lookAt]
        return scene
    }

    private func resetCamera(bounds: RawPointCloudBounds) {
        guard let scene = sceneView.scene,
              let cameraNode = scene.rootNode.childNode(withName: "Camera", recursively: false) else {
            return
        }

        let extent = bounds.extent
        let radius = max(max(extent.x, max(extent.y, extent.z)), 0.4)
        cameraNode.simdPosition = bounds.center + SIMD3<Float>(radius * 0.9, radius * 0.55, radius * 1.6)
        cameraNode.camera?.zFar = Double(max(radius * 8, 20))
        sceneView.pointOfView = cameraNode
        sceneView.defaultCameraController.target = SCNVector3(bounds.center)
    }

    private func makeErrorScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.082, green: 0.087, blue: 0.095, alpha: 1)
        return scene
    }
}

private struct RawPointCloudBounds {
    let minimum: SIMD3<Float>
    let maximum: SIMD3<Float>

    var center: SIMD3<Float> {
        (minimum + maximum) * 0.5
    }

    var extent: SIMD3<Float> {
        maximum - minimum
    }
}

private enum RawPLYParser {
    private static let pointBudget = 520_000

    struct ParsedPointCloud {
        let geometry: SCNGeometry
        let bounds: RawPointCloudBounds
    }

    static func pointCloud(from url: URL) throws -> ParsedPointCloud {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let header = header(in: data) else {
            throw NSError(domain: "RawPLYParser", code: 1)
        }

        let hasRGB = header.string.contains("property uchar red")
        let plyStride = hasRGB ? 15 : 24
        let availableVertices = min(
            header.vertexCount,
            max(0, (data.count - header.bodyOffset) / plyStride)
        )
        guard availableVertices > 0 else {
            throw NSError(domain: "RawPLYParser", code: 2)
        }

        let displayStride = max(1, (availableVertices + pointBudget - 1) / pointBudget)
        let displayCount = (availableVertices + displayStride - 1) / displayStride
        var vertexBytes = Data(count: displayCount * 12)
        var colorBytes = Data(count: displayCount * 12)
        var minimum = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw NSError(domain: "RawPLYParser", code: 3)
            }
            let bodyBase = baseAddress.advanced(by: header.bodyOffset)

            vertexBytes.withUnsafeMutableBytes { vertexRaw in
                colorBytes.withUnsafeMutableBytes { colorRaw in
                    let vertexPtr = vertexRaw.bindMemory(to: Float32.self)
                    let colorPtr = colorRaw.bindMemory(to: Float32.self)

                    for displayIndex in 0..<displayCount {
                        let sourceIndex = displayIndex * displayStride
                        let pointBase = bodyBase.advanced(by: sourceIndex * plyStride)
                        let position = SIMD3<Float>(
                            readFloat(from: pointBase, at: 0),
                            readFloat(from: pointBase, at: 4),
                            readFloat(from: pointBase, at: 8)
                        )

                        minimum = simd_min(minimum, position)
                        maximum = simd_max(maximum, position)
                        vertexPtr[displayIndex * 3 + 0] = position.x
                        vertexPtr[displayIndex * 3 + 1] = position.y
                        vertexPtr[displayIndex * 3 + 2] = position.z

                        let color = displayColor(from: pointBase, hasRGB: hasRGB)
                        colorPtr[displayIndex * 3 + 0] = color.x
                        colorPtr[displayIndex * 3 + 1] = color.y
                        colorPtr[displayIndex * 3 + 2] = color.z
                    }
                }
            }
        }

        let bounds = expandedBounds(minimum: minimum, maximum: maximum)
        return ParsedPointCloud(
            geometry: makeGeometry(vertexBytes: vertexBytes, colorBytes: colorBytes, pointCount: displayCount, bounds: bounds),
            bounds: bounds
        )
    }

    private static func header(in data: Data) -> (string: String, bodyOffset: Int, vertexCount: Int)? {
        let tokens = ["end_header\n", "end_header\r\n"]
        guard let token = tokens.first(where: { data.range(of: Data($0.utf8)) != nil }),
              let range = data.range(of: Data(token.utf8)),
              let string = String(data: data[..<range.upperBound], encoding: .ascii) else {
            return nil
        }

        let vertexCount = string
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
            .first(where: { $0.hasPrefix("element vertex ") })
            .flatMap { Int($0.replacingOccurrences(of: "element vertex ", with: "")) } ?? 0
        return (string, range.upperBound, vertexCount)
    }

    private static func displayColor(from pointer: UnsafeRawPointer, hasRGB: Bool) -> SIMD3<Float> {
        if hasRGB {
            return SIMD3<Float>(
                Float(pointer.advanced(by: 12).load(as: UInt8.self)) / 255,
                Float(pointer.advanced(by: 13).load(as: UInt8.self)) / 255,
                Float(pointer.advanced(by: 14).load(as: UInt8.self)) / 255
            )
        }

        let nx = abs(readFloat(from: pointer, at: 12))
        let ny = abs(readFloat(from: pointer, at: 16))
        let nz = abs(readFloat(from: pointer, at: 20))
        let brightness = min(1, 0.32 + (nx * 0.18) + (ny * 0.38) + (nz * 0.24))
        return SIMD3<Float>(
            min(1, brightness * 1.08),
            min(1, brightness),
            min(1, brightness * 0.88)
        )
    }

    private static func makeGeometry(
        vertexBytes: Data,
        colorBytes: Data,
        pointCount: Int,
        bounds: RawPointCloudBounds
    ) -> SCNGeometry {
        let vertexSource = SCNGeometrySource(
            data: vertexBytes,
            semantic: .vertex,
            vectorCount: pointCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 12
        )
        let colorSource = SCNGeometrySource(
            data: colorBytes,
            semantic: .color,
            vectorCount: pointCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 12
        )
        let element = SCNGeometryElement(
            data: nil,
            primitiveType: .point,
            primitiveCount: pointCount,
            bytesPerIndex: 0
        )
        let pointSize = pointSize(bounds: bounds, pointCount: pointCount)
        element.pointSize = pointSize
        element.minimumPointScreenSpaceRadius = 0
        element.maximumPointScreenSpaceRadius = max(1.0, pointSize)

        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.writesToDepthBuffer = true
        material.readsFromDepthBuffer = true
        geometry.materials = [material]
        return geometry
    }

    private static func expandedBounds(minimum: SIMD3<Float>, maximum: SIMD3<Float>) -> RawPointCloudBounds {
        let extent = simd_max(maximum - minimum, SIMD3<Float>(repeating: 0.08))
        let padding = simd_max(extent * 0.08, SIMD3<Float>(repeating: 0.05))
        return RawPointCloudBounds(minimum: minimum - padding, maximum: maximum + padding)
    }

    private static func pointSize(bounds: RawPointCloudBounds, pointCount: Int) -> CGFloat {
        let safeExtent = max(max(bounds.extent.x, max(bounds.extent.y, bounds.extent.z)), 0.5)
        let estimatedSpacing = safeExtent / sqrt(Float(max(pointCount, 1)))
        return CGFloat(min(1.4, max(0.75, estimatedSpacing * 110)))
    }

    private static func readFloat(from pointer: UnsafeRawPointer, at offset: Int) -> Float {
        let value = pointer.advanced(by: offset).loadUnaligned(as: UInt32.self)
        return Float(bitPattern: UInt32(littleEndian: value))
    }
}
