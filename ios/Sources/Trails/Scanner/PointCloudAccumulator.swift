import Foundation
import ARKit

final class PointCloudAccumulator {
    private enum CapturedImageMatrix {
        case itur601
        case itur709
    }

    private struct CapturedImageEncoding {
        let matrix: CapturedImageMatrix
        let isVideoRange: Bool

        init(buffer: CVPixelBuffer) {
            let attachment = CVBufferCopyAttachment(buffer, kCVImageBufferYCbCrMatrixKey, nil)
            if let matrixValue = attachment as? String, matrixValue == (kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String) {
                matrix = .itur709
            } else {
                // ARKit documents capturedImage as full-range ITU-R 601 by default.
                // Keep that as the fallback while still respecting runtime attachments.
                matrix = .itur601
            }
            isVideoRange = CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        }
    }

    private struct Surfel {
        var position: SIMD3<Float>
        var color: SIMD3<Float>
        var confidence: Float
        var observations: Int
        var lastSeenFrame: Int
        var nearestDepth: Float
    }

    private let queue = DispatchQueue(label: "com.trails.lidar.pointcloud", qos: .userInitiated)
    private var surfels: [Surfel] = []
    private var voxelIndexMap: [SIMD3<Int32>: Int] = [:]
    private var voxelSize: Float = 0.01
    private var minimumConfidence: UInt8 = 2
    private var maxRange: Float = 5.0
    private var frameIndex = 0

    var pointCount: Int {
        queue.sync { surfels.count }
    }

    func setVoxelSize(_ size: Float) {
        queue.async {
            self.voxelSize = size
        }
    }

    func setMinimumConfidence(_ confidence: UInt8) {
        queue.async {
            self.minimumConfidence = confidence
        }
    }

    func setMaxRange(_ range: Float) {
        queue.async {
            self.maxRange = range
        }
    }

    func addFrame(_ frame: ARFrame) {
        guard let depthData = frame.sceneDepth ?? frame.smoothedSceneDepth else { return }
        let confMap = depthData.confidenceMap

        let depthMap = depthData.depthMap
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)

        let intrinsics = frame.camera.intrinsics
        let imageResolution = frame.camera.imageResolution
        let transform = frame.camera.transform
        let capturedImage = frame.capturedImage

        let scaleX = Float(depthWidth) / Float(imageResolution.width)
        let scaleY = Float(depthHeight) / Float(imageResolution.height)
        let fx = intrinsics[0][0] * scaleX
        let fy = intrinsics[1][1] * scaleY
        let cx = intrinsics[2][0] * scaleX
        let cy = intrinsics[2][1] * scaleY

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        if let confMap {
            CVPixelBufferLockBaseAddress(confMap, .readOnly)
        }
        CVPixelBufferLockBaseAddress(capturedImage, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            if let confMap {
                CVPixelBufferUnlockBaseAddress(confMap, .readOnly)
            }
            CVPixelBufferUnlockBaseAddress(capturedImage, .readOnly)
        }

        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap) else { return }

        let imageBase = CVPixelBufferGetBaseAddress(capturedImage)
        let depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let confBase = confMap.flatMap { CVPixelBufferGetBaseAddress($0) }
        let confBytesPerRow = confMap.map { CVPixelBufferGetBytesPerRow($0) }
        let imageBytesPerRow = CVPixelBufferGetBytesPerRow(capturedImage)
        let imageEncoding = CapturedImageEncoding(buffer: capturedImage)
        let (voxelSize, minimumConfidence, maxRange) = queue.sync {
            (self.voxelSize, self.minimumConfidence, self.maxRange)
        }

        var newPoints: [SIMD3<Float>] = []
        var newColors: [SIMD3<Float>] = []
        var newVoxels: [SIMD3<Int32>] = []
        var newDepths: [Float] = []
        var newConfidences: [Float] = []

        let step = voxelSize <= 0.01 ? 1 : 2
        for v in stride(from: 0, to: depthHeight, by: step) {
            for u in stride(from: 0, to: depthWidth, by: step) {
                let confidence: UInt8
                if let confBase, let confBytesPerRow {
                    let confPtr = confBase.advanced(by: v * confBytesPerRow + u)
                    confidence = confPtr.load(as: UInt8.self)
                    guard confidence >= minimumConfidence else { continue }
                } else {
                    confidence = max(minimumConfidence, 1)
                }

                let depthPtr = depthBase.advanced(by: v * depthBytesPerRow + u * MemoryLayout<Float>.size)
                let depth = depthPtr.load(as: Float.self)
                guard depth > 0.2 && depth < maxRange && depth.isFinite else { continue }

                let xCamera = (Float(u) - cx) * depth / fx
                let yCamera = -(Float(v) - cy) * depth / fy
                let zCamera = -depth
                let cameraPoint = SIMD4<Float>(xCamera, yCamera, zCamera, 1.0)
                let worldPoint = transform * cameraPoint
                let worldXYZ = SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)

                let voxelKey = SIMD3<Int32>(
                    Int32(floor(worldXYZ.x / voxelSize)),
                    Int32(floor(worldXYZ.y / voxelSize)),
                    Int32(floor(worldXYZ.z / voxelSize))
                )

                let imageU = Int(Float(u) / scaleX)
                let imageV = Int(Float(v) / scaleY)
                let rgb = sampleColor(
                    baseAddress: imageBase,
                    x: imageU,
                    y: imageV,
                    bytesPerRow: imageBytesPerRow,
                    buffer: capturedImage,
                    encoding: imageEncoding
                )

                newPoints.append(worldXYZ)
                newColors.append(rgb)
                newVoxels.append(voxelKey)
                newDepths.append(depth)
                newConfidences.append(confidenceWeight(for: confidence))
            }
        }

        queue.async { [weak self] in
            guard let self else { return }
            self.frameIndex += 1
            let currentFrameIndex = self.frameIndex

            // Hard cap: probabilistic reservoir insertion once we reach 10M surfels.
            // This prevents unbounded memory growth during very long room scans.
            let hardCap = 10_000_000

            for index in 0..<newPoints.count {
                if let existingIndex = self.voxelIndexMap[newVoxels[index]] {
                    self.fuseSurfel(
                        at: existingIndex,
                        point: newPoints[index],
                        color: newColors[index],
                        depth: newDepths[index],
                        confidence: newConfidences[index],
                        frameIndex: currentFrameIndex
                    )
                } else {
                    // Over budget: random-replace an existing surfel (reservoir sampling)
                    if self.surfels.count >= hardCap {
                        let replaceIdx = Int.random(in: 0..<hardCap)
                        // Remove old voxel mapping for replaced surfel
                        let oldVoxel = SIMD3<Int32>(
                            Int32(floor(self.surfels[replaceIdx].position.x / self.voxelSize)),
                            Int32(floor(self.surfels[replaceIdx].position.y / self.voxelSize)),
                            Int32(floor(self.surfels[replaceIdx].position.z / self.voxelSize))
                        )
                        self.voxelIndexMap.removeValue(forKey: oldVoxel)
                        self.surfels[replaceIdx] = Surfel(
                            position: newPoints[index],
                            color: newColors[index],
                            confidence: newConfidences[index],
                            observations: 1,
                            lastSeenFrame: currentFrameIndex,
                            nearestDepth: newDepths[index]
                        )
                        self.voxelIndexMap[newVoxels[index]] = replaceIdx
                    } else {
                        let insertIndex = self.surfels.count
                        self.voxelIndexMap[newVoxels[index]] = insertIndex
                        self.surfels.append(
                            Surfel(
                                position: newPoints[index],
                                color: newColors[index],
                                confidence: newConfidences[index],
                                observations: 1,
                                lastSeenFrame: currentFrameIndex,
                                nearestDepth: newDepths[index]
                            )
                        )
                    }
                }
            }
        }
    }

    func previewSnapshot(maxPoints: Int) -> ([SIMD3<Float>], [SIMD3<UInt8>]) {
        queue.sync {
            guard !surfels.isEmpty, maxPoints > 0 else { return ([], []) }

            let stride = max(1, (surfels.count + maxPoints - 1) / maxPoints)
            let previewCount = min(maxPoints, (surfels.count + stride - 1) / stride)
            var positions: [SIMD3<Float>] = []
            var colors: [SIMD3<UInt8>] = []
            positions.reserveCapacity(previewCount)
            colors.reserveCapacity(previewCount)

            for index in Swift.stride(from: 0, to: surfels.count, by: stride) {
                guard positions.count < maxPoints else { break }
                let surfel = surfels[index]
                positions.append(surfel.position)
                colors.append(floatColorToUInt8(surfel.color))
            }

            return (positions, colors)
        }
    }

    func exportPLY() -> URL? {
        let exportCount = queue.sync {
            surfels.reduce(0) { count, surfel in
                count + (surfel.observations >= 2 || surfel.confidence >= 1.5 ? 1 : 0)
            }
        }

        guard exportCount > 0 else { return nil }

        let fileName = "scan_\(Int(Date().timeIntervalSince1970)).ply"
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let outputPath = documentsDirectory.appendingPathComponent(fileName)

        let header = """
        ply
        format binary_little_endian 1.0
        element vertex \(exportCount)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header

        """.data(using: .ascii)!

        do {
            if FileManager.default.fileExists(atPath: outputPath.path) {
                try FileManager.default.removeItem(at: outputPath)
            }

            guard FileManager.default.createFile(atPath: outputPath.path, contents: nil) else { return nil }
            let fileHandle = try FileHandle(forWritingTo: outputPath)
            defer { try? fileHandle.close() }

            try fileHandle.write(contentsOf: header)

            var writeError: Error?
            queue.sync {
                var chunk = Data()
                chunk.reserveCapacity(16_384 * 15)

                do {
                    for surfel in surfels where surfel.observations >= 2 || surfel.confidence >= 1.5 {
                        let point = surfel.position
                        let color = floatColorToUInt8(surfel.color)

                        var x = point.x.bitPattern.littleEndian
                        var y = point.y.bitPattern.littleEndian
                        var z = point.z.bitPattern.littleEndian

                        withUnsafeBytes(of: &x) { chunk.append(contentsOf: $0) }
                        withUnsafeBytes(of: &y) { chunk.append(contentsOf: $0) }
                        withUnsafeBytes(of: &z) { chunk.append(contentsOf: $0) }

                        chunk.append(color.x)
                        chunk.append(color.y)
                        chunk.append(color.z)

                        if chunk.count >= 16_384 * 15 {
                            try fileHandle.write(contentsOf: chunk)
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }

                    if !chunk.isEmpty {
                        try fileHandle.write(contentsOf: chunk)
                    }
                } catch {
                    writeError = error
                }
            }

            if let writeError {
                throw writeError
            }

            return outputPath
        } catch {
            try? FileManager.default.removeItem(at: outputPath)
            return nil
        }
    }

    func reset() {
        queue.sync {
            surfels.removeAll()
            voxelIndexMap.removeAll()
            frameIndex = 0
        }
    }

    private func fuseSurfel(
        at index: Int,
        point: SIMD3<Float>,
        color: SIMD3<Float>,
        depth: Float,
        confidence: Float,
        frameIndex: Int
    ) {
        var surfel = surfels[index]
        let replacementThreshold = max(voxelSize * 0.75, 0.005)
        let pointDistance = simd_distance(surfel.position, point)
        let shouldReplace = depth + replacementThreshold < surfel.nearestDepth || pointDistance > voxelSize * 1.5

        if shouldReplace {
            surfel.position = point
            surfel.color = color
            surfel.nearestDepth = depth
        } else {
            let existingWeight = max(surfel.confidence, 1.0)
            let newWeight = max(confidence * (1.2 / max(depth, 0.25)), 0.25)
            let alpha = min(0.8, newWeight / (existingWeight + newWeight))
            surfel.position = surfel.position * (1.0 - alpha) + point * alpha
            surfel.color = surfel.color * (1.0 - alpha) + color * alpha
            surfel.nearestDepth = min(surfel.nearestDepth, depth)
        }

        surfel.confidence = min(24.0, surfel.confidence + confidence)
        surfel.observations += 1
        surfel.lastSeenFrame = frameIndex
        surfels[index] = surfel
    }

    private func confidenceWeight(for confidence: UInt8) -> Float {
        switch confidence {
        case 3...: return 1.0
        case 2: return 0.75
        case 1: return 0.35
        default: return 0.15
        }
    }

    private func floatColorToUInt8(_ color: SIMD3<Float>) -> SIMD3<UInt8> {
        SIMD3<UInt8>(
            clampColor(color.x),
            clampColor(color.y),
            clampColor(color.z)
        )
    }

    private func clampColor(_ value: Float) -> UInt8 {
        UInt8(max(0, min(255, Int(value.rounded()))))
    }

    private func sampleColor(
        baseAddress: UnsafeMutableRawPointer?,
        x: Int,
        y: Int,
        bytesPerRow: Int,
        buffer: CVPixelBuffer,
        encoding: CapturedImageEncoding
    ) -> SIMD3<Float> {
        let pixelFormat = CVPixelBufferGetPixelFormatType(buffer)
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let safeX = max(0, min(width - 1, x))
        let safeY = max(0, min(height - 1, y))

        if pixelFormat == kCVPixelFormatType_32BGRA {
            guard let baseAddress else { return SIMD3<Float>(128, 128, 128) }
            let offset = safeY * bytesPerRow + safeX * 4
            let blue = baseAddress.advanced(by: offset).load(as: UInt8.self)
            let green = baseAddress.advanced(by: offset + 1).load(as: UInt8.self)
            let red = baseAddress.advanced(by: offset + 2).load(as: UInt8.self)
            return SIMD3<Float>(Float(red), Float(green), Float(blue))
        }

        if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
            guard let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
                  let uvBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else {
                return SIMD3<Float>(128, 128, 128)
            }

            let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            let uvBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
            let yValue = Float(yBase.advanced(by: safeY * yBytesPerRow + safeX).load(as: UInt8.self))
            let uvX = (safeX / 2) * 2
            let uvY = safeY / 2
            let cbValue = Float(uvBase.advanced(by: uvY * uvBytesPerRow + uvX).load(as: UInt8.self))
            let crValue = Float(uvBase.advanced(by: uvY * uvBytesPerRow + uvX + 1).load(as: UInt8.self))
            return yCbCrToRGB(y: yValue, cb: cbValue, cr: crValue, encoding: encoding)
        }

        return SIMD3<Float>(128, 128, 128)
    }

    private func yCbCrToRGB(
        y: Float,
        cb: Float,
        cr: Float,
        encoding: CapturedImageEncoding
    ) -> SIMD3<Float> {
        let chromaBlue = cb - 128.0
        let chromaRed = cr - 128.0

        let red: Float
        let green: Float
        let blue: Float

        if encoding.isVideoRange {
            let luma = max(0, y - 16.0) * (255.0 / 219.0)
            switch encoding.matrix {
            case .itur709:
                red = luma + 1.792741 * chromaRed
                green = luma - 0.213249 * chromaBlue - 0.532909 * chromaRed
                blue = luma + 2.112402 * chromaBlue
            case .itur601:
                red = luma + 1.596027 * chromaRed
                green = luma - 0.391762 * chromaBlue - 0.812968 * chromaRed
                blue = luma + 2.017232 * chromaBlue
            }
        } else {
            switch encoding.matrix {
            case .itur709:
                red = y + 1.5748 * chromaRed
                green = y - 0.187324 * chromaBlue - 0.468124 * chromaRed
                blue = y + 1.8556 * chromaBlue
            case .itur601:
                red = y + 1.402 * chromaRed
                green = y - 0.344136 * chromaBlue - 0.714136 * chromaRed
                blue = y + 1.772 * chromaBlue
            }
        }

        return SIMD3<Float>(Float(clampColor(red)), Float(clampColor(green)), Float(clampColor(blue)))
    }
}
