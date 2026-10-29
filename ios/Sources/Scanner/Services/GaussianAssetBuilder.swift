import Foundation
import simd
import spz

private struct GaussianAssetVoxelKey: Hashable {
    let x: Int32
    let y: Int32
    let z: Int32
}

enum GaussianAssetBuildError: Error {
    case noSourcePoints
    case writeFailed
}

final class GaussianAssetBuilder {
    private struct SourcePoint {
        let position: SIMD3<Float>
        let color: SIMD3<Float>
    }

    private struct GaussianPoint {
        let position: SIMD3<Float>
        let scale: SIMD3<Float>
        let color: SIMD3<Float>
        let opacity: Float
    }

    private nonisolated static let maxGaussianCount = 1_000_000
    private nonisolated static let previewGaussianCount = 180_000
    private nonisolated static let adaptiveDensityLimit = 420_000

    nonisolated init() {}

    nonisolated func build(
        scanID: UUID,
        sourcePLYFileNames: [String],
        captureManifestFileName: String?
    ) throws -> GaussianBuildResult {
        let keyframeCount = captureManifestFileName.map(Self.captureKeyframeCount(fileName:)) ?? 0
        let sourcePoints = try readSourcePoints(
            fileNames: sourcePLYFileNames,
            maxPointCount: Self.maxGaussianCount
        )
        guard !sourcePoints.isEmpty else { throw GaussianAssetBuildError.noSourcePoints }

        let bounds = Self.bounds(for: sourcePoints)
        let gaussians = Self.makeAdaptiveGaussians(from: sourcePoints, bounds: bounds)

        let stem = Self.assetStem(for: scanID)
        let splatFileName = "\(stem).splat"
        let gaussianPLYFileName = "\(stem)_3dgs.ply"
        let spzFileName = "\(stem).spz"
        let manifestFileName = "\(stem).json"
        let splatURL = ScanFileStore.fileURL(fileName: splatFileName)
        let plyURL = ScanFileStore.fileURL(fileName: gaussianPLYFileName)
        let spzURL = ScanFileStore.fileURL(fileName: spzFileName)
        let manifestURL = ScanFileStore.fileURL(fileName: manifestFileName)

        try writeSplat(gaussians, to: splatURL)
        try writeGaussianPLY(gaussians, to: plyURL)
        try writeSPZ(gaussians, to: spzURL)

        let manifestData = try Self.makeAssetManifestData(
            version: GaussianAssetManifest.currentVersion,
            createdAt: Date(),
            gaussianCount: gaussians.count,
            sourcePointCount: sourcePoints.count,
            keyframeCount: keyframeCount,
            splatFileName: splatFileName,
            gaussianPLYFileName: gaussianPLYFileName,
            spzFileName: spzFileName,
            sogFileName: nil,
            boundsMinimum: [bounds.minimum.x, bounds.minimum.y, bounds.minimum.z],
            boundsMaximum: [bounds.maximum.x, bounds.maximum.y, bounds.maximum.z]
        )
        try manifestData.write(to: manifestURL, options: .atomic)

        return GaussianBuildResult(
            manifestFileName: manifestFileName,
            splatFileName: splatFileName,
            gaussianPLYFileName: gaussianPLYFileName,
            spzFileName: spzFileName,
            sogFileName: nil
        )
    }

    nonisolated func buildPreview(
        scanID: UUID,
        sourcePLYFileNames: [String]
    ) throws -> GaussianPreviewBuildResult {
        let sourcePoints = try readSourcePoints(
            fileNames: sourcePLYFileNames,
            maxPointCount: Self.previewGaussianCount
        )
        guard !sourcePoints.isEmpty else { throw GaussianAssetBuildError.noSourcePoints }

        let bounds = Self.bounds(for: sourcePoints)
        let radius = min(0.0034, Self.recommendedScale(bounds: bounds, pointCount: sourcePoints.count) * 1.16)
        let gaussians = Self.makePreviewGaussians(from: sourcePoints, radius: radius)

        let gaussianPLYFileName = "\(Self.assetStem(for: scanID))_3dgs.ply"
        try writeGaussianPLY(gaussians, to: ScanFileStore.fileURL(fileName: gaussianPLYFileName))

        return GaussianPreviewBuildResult(gaussianPLYFileName: gaussianPLYFileName)
    }

    private nonisolated func readSourcePoints(
        fileNames: [String],
        maxPointCount: Int
    ) throws -> [SourcePoint] {
        let vertexCounts = fileNames.map { Self.vertexCount(fileName: $0) }
        let totalVertices = vertexCounts.reduce(0, +)
        let safeMaxPointCount = max(1, maxPointCount)
        let stride = max(1, (totalVertices + safeMaxPointCount - 1) / safeMaxPointCount)

        var points: [SourcePoint] = []
        points.reserveCapacity(min(totalVertices, safeMaxPointCount))

        for fileName in fileNames {
            try appendSourcePoints(
                from: ScanFileStore.fileURL(fileName: fileName),
                stride: stride,
                maxPointCount: safeMaxPointCount,
                to: &points
            )
            if points.count >= safeMaxPointCount { break }
        }

        return points
    }

    private nonisolated func appendSourcePoints(
        from url: URL,
        stride displayStride: Int,
        maxPointCount: Int,
        to points: inout [SourcePoint]
    ) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let header = Self.header(in: data) else { return }

        let hasRGB = header.string.contains("property uchar red")
        let plyStride = hasRGB ? 15 : 24
        let availableVertices = min(
            header.vertexCount,
            max(0, (data.count - header.bodyOffset) / plyStride)
        )
        guard availableVertices > 0 else { return }

        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            let bodyBase = baseAddress.advanced(by: header.bodyOffset)

            for index in stride(from: 0, to: availableVertices, by: displayStride) {
                let pointBase = bodyBase.advanced(by: index * plyStride)
                let position = SIMD3<Float>(
                    Self.readFloat(from: pointBase, at: 0),
                    Self.readFloat(from: pointBase, at: 4),
                    Self.readFloat(from: pointBase, at: 8)
                )
                guard position.x.isFinite, position.y.isFinite, position.z.isFinite else { continue }

                let color: SIMD3<Float>
                if hasRGB {
                    color = SIMD3<Float>(
                        Float(pointBase.advanced(by: 12).load(as: UInt8.self)) / 255,
                        Float(pointBase.advanced(by: 13).load(as: UInt8.self)) / 255,
                        Float(pointBase.advanced(by: 14).load(as: UInt8.self)) / 255
                    )
                } else {
                    color = SIMD3<Float>(repeating: 0.72)
                }

                points.append(SourcePoint(position: position, color: color))
                if points.count >= maxPointCount {
                    return
                }
            }
        }
    }

    private nonisolated func writeSplat(_ gaussians: [GaussianPoint], to url: URL) throws {
        var data = Data()
        data.reserveCapacity(gaussians.count * 32)

        for gaussian in gaussians {
            appendFloat(gaussian.position.x, to: &data)
            appendFloat(gaussian.position.y, to: &data)
            appendFloat(gaussian.position.z, to: &data)
            appendFloat(gaussian.scale.x, to: &data)
            appendFloat(gaussian.scale.y, to: &data)
            appendFloat(gaussian.scale.z, to: &data)
            data.append(UInt8(max(0, min(255, gaussian.color.x * 255))))
            data.append(UInt8(max(0, min(255, gaussian.color.y * 255))))
            data.append(UInt8(max(0, min(255, gaussian.color.z * 255))))
            data.append(UInt8(max(0, min(255, gaussian.opacity * 255))))
            data.append(255)
            data.append(128)
            data.append(128)
            data.append(128)
        }

        try data.write(to: url, options: .atomic)
    }

    private nonisolated func writeGaussianPLY(_ gaussians: [GaussianPoint], to url: URL) throws {
        var data = Data()
        var header = "ply\n"
        header += "format binary_little_endian 1.0\n"
        header += "element vertex \(gaussians.count)\n"
        header += "property float x\n"
        header += "property float y\n"
        header += "property float z\n"
        header += "property float f_dc_0\n"
        header += "property float f_dc_1\n"
        header += "property float f_dc_2\n"
        header += "property float opacity\n"
        header += "property float scale_0\n"
        header += "property float scale_1\n"
        header += "property float scale_2\n"
        header += "property float rot_0\n"
        header += "property float rot_1\n"
        header += "property float rot_2\n"
        header += "property float rot_3\n"
        header += "end_header\n"
        data.append(Data(header.utf8))

        for gaussian in gaussians {
            appendFloat(gaussian.position.x, to: &data)
            appendFloat(gaussian.position.y, to: &data)
            appendFloat(gaussian.position.z, to: &data)
            appendFloat(Self.shCoefficient(from: gaussian.color.x), to: &data)
            appendFloat(Self.shCoefficient(from: gaussian.color.y), to: &data)
            appendFloat(Self.shCoefficient(from: gaussian.color.z), to: &data)
            appendFloat(Self.logit(gaussian.opacity), to: &data)
            appendFloat(log(max(gaussian.scale.x, 0.0001)), to: &data)
            appendFloat(log(max(gaussian.scale.y, 0.0001)), to: &data)
            appendFloat(log(max(gaussian.scale.z, 0.0001)), to: &data)
            appendFloat(1, to: &data)
            appendFloat(0, to: &data)
            appendFloat(0, to: &data)
            appendFloat(0, to: &data)
        }

        try data.write(to: url, options: .atomic)
    }

    private nonisolated func writeSPZ(_ gaussians: [GaussianPoint], to url: URL) throws {
        let pointCount = gaussians.count
        var positions: [Float] = []
        var scales: [Float] = []
        var rotations: [Float] = []
        var alphas: [Float] = []
        var colors: [Float] = []

        positions.reserveCapacity(pointCount * 3)
        scales.reserveCapacity(pointCount * 3)
        rotations.reserveCapacity(pointCount * 4)
        alphas.reserveCapacity(pointCount)
        colors.reserveCapacity(pointCount * 3)

        for gaussian in gaussians {
            positions.append(contentsOf: [
                gaussian.position.x,
                gaussian.position.y,
                gaussian.position.z
            ])
            scales.append(contentsOf: [
                log(max(gaussian.scale.x, 0.0001)),
                log(max(gaussian.scale.y, 0.0001)),
                log(max(gaussian.scale.z, 0.0001))
            ])
            rotations.append(contentsOf: [0, 0, 0, 1])
            alphas.append(Self.logit(gaussian.opacity))
            colors.append(contentsOf: [
                Self.shCoefficient(from: gaussian.color.x),
                Self.shCoefficient(from: gaussian.color.y),
                Self.shCoefficient(from: gaussian.color.z)
            ])
        }

        let cloud = GaussianCloud(
            numPoints: Int32(pointCount),
            shDegree: 0,
            antialiased: false,
            positions: positions,
            scales: scales,
            rotations: rotations,
            alphas: alphas,
            colors: colors,
            sh: []
        )
        try saveSpz(cloud, to: url, options: PackOptions(from: .rdf))
    }

    private nonisolated func appendFloat(_ value: Float, to data: inout Data) {
        var littleEndian = value.bitPattern.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private nonisolated static func captureKeyframeCount(fileName: String) -> Int {
        guard let data = try? Data(contentsOf: ScanFileStore.fileURL(fileName: fileName)) else {
            return 0
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let keyframes = object["keyframes"] as? [Any] else {
            return 0
        }
        return keyframes.count
    }

    private nonisolated static func makeAssetManifestData(
        version: Int,
        createdAt: Date,
        gaussianCount: Int,
        sourcePointCount: Int,
        keyframeCount: Int,
        splatFileName: String,
        gaussianPLYFileName: String,
        spzFileName: String?,
        sogFileName: String?,
        boundsMinimum: [Float],
        boundsMaximum: [Float]
    ) throws -> Data {
        let manifest = GaussianAssetManifest(
            version: version,
            createdAt: createdAt,
            gaussianCount: gaussianCount,
            sourcePointCount: sourcePointCount,
            keyframeCount: keyframeCount,
            splatFileName: splatFileName,
            gaussianPLYFileName: gaussianPLYFileName,
            spzFileName: spzFileName,
            sogFileName: sogFileName,
            boundsMinimum: boundsMinimum,
            boundsMaximum: boundsMaximum
        )
        return try JSONEncoder().encode(manifest)
    }

    private nonisolated static func vertexCount(fileName: String) -> Int {
        guard let data = try? Data(contentsOf: ScanFileStore.fileURL(fileName: fileName), options: .mappedIfSafe),
              let header = header(in: data) else {
            return 0
        }
        return header.vertexCount
    }

    private nonisolated static func header(in data: Data) -> (string: String, bodyOffset: Int, vertexCount: Int)? {
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

    private nonisolated static func bounds(for points: [SourcePoint]) -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        var minimum = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        for point in points {
            minimum = simd_min(minimum, point.position)
            maximum = simd_max(maximum, point.position)
        }
        return (minimum, maximum)
    }

    private nonisolated static func makeAdaptiveGaussians(
        from points: [SourcePoint],
        bounds: (minimum: SIMD3<Float>, maximum: SIMD3<Float>)
    ) -> [GaussianPoint] {
        let baseRadius = recommendedScale(bounds: bounds, pointCount: points.count)
        guard points.count <= adaptiveDensityLimit else {
            return makeUniformGaussians(from: points, radius: baseRadius)
        }

        let cellSize = max(baseRadius * 4.5, 0.0045)

        var voxelCounts: [GaussianAssetVoxelKey: Int] = [:]
        voxelCounts.reserveCapacity(min(points.count, 900_000))
        for point in points {
            voxelCounts[voxelKey(for: point.position, minimum: bounds.minimum, cellSize: cellSize), default: 0] += 1
        }

        var gaussians: [GaussianPoint] = []
        gaussians.reserveCapacity(points.count)

        for point in points {
            let displayColor = viewerDisplayColor(from: point.color)
            let key = voxelKey(for: point.position, minimum: bounds.minimum, cellSize: cellSize)
            let neighborCount = localNeighborCount(around: key, voxelCounts: voxelCounts)

            let density = min(1, max(0, (Float(neighborCount) - 1) / 30))
            let densityCurve = sqrt(density)
            let radiusScale = 0.72 + densityCurve * 0.36
            let radius = min(0.0032, max(0.00055, baseRadius * radiusScale))
            let opacity = min(0.50, max(0.18, 0.20 + densityCurve * 0.28))

            gaussians.append(
                GaussianPoint(
                    position: point.position,
                    scale: SIMD3<Float>(repeating: radius),
                    color: displayColor,
                    opacity: opacity
                )
            )
        }

        guard !gaussians.isEmpty else {
            return makeUniformGaussians(from: points, radius: baseRadius)
        }

        return gaussians
    }

    private nonisolated static func makeUniformGaussians(
        from points: [SourcePoint],
        radius: Float
    ) -> [GaussianPoint] {
        points.map { point in
            GaussianPoint(
                position: point.position,
                scale: SIMD3<Float>(repeating: radius),
                color: viewerDisplayColor(from: point.color),
                opacity: 0.36
            )
        }
    }

    private nonisolated static func makePreviewGaussians(
        from points: [SourcePoint],
        radius: Float
    ) -> [GaussianPoint] {
        points.map { point in
            GaussianPoint(
                position: point.position,
                scale: SIMD3<Float>(repeating: radius),
                color: viewerDisplayColor(from: point.color),
                opacity: 0.40
            )
        }
    }

    private nonisolated static func assetStem(for scanID: UUID) -> String {
        "gaussian_\(scanID.uuidString)"
    }

    private nonisolated static func viewerDisplayColor(from color: SIMD3<Float>) -> SIMD3<Float> {
        let clamped = SIMD3<Float>(
            min(1, max(0, color.x)),
            min(1, max(0, color.y)),
            min(1, max(0, color.z))
        )
        let luminance = min(1, max(0, simd_dot(clamped, SIMD3<Float>(0.2126, 0.7152, 0.0722))))
        let shadowWeight = 1 - smoothstep(edge0: 0.24, edge1: 0.78, value: luminance)
        let visibleShadowWeight = shadowWeight * smoothstep(edge0: 0.018, edge1: 0.09, value: luminance)
        let desaturation = shadowWeight * 0.34
        let grayscale = SIMD3<Float>(repeating: luminance)
        let balancedColor = clamped * (1 - desaturation) + grayscale * desaturation

        let gamma: Float = 0.70
        let lifted = SIMD3<Float>(
            pow(balancedColor.x, gamma),
            pow(balancedColor.y, gamma),
            pow(balancedColor.z, gamma)
        )
        let exposure = 1.08 + visibleShadowWeight * 0.18
        let floorLift = visibleShadowWeight * 0.024
        let adjusted = lifted * exposure + SIMD3<Float>(repeating: floorLift)

        return SIMD3<Float>(
            min(1, max(0, adjusted.x)),
            min(1, max(0, adjusted.y)),
            min(1, max(0, adjusted.z))
        )
    }

    private nonisolated static func smoothstep(edge0: Float, edge1: Float, value: Float) -> Float {
        guard edge0 != edge1 else {
            return value < edge0 ? 0 : 1
        }
        let t = min(1, max(0, (value - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    private nonisolated static func voxelKey(
        for position: SIMD3<Float>,
        minimum: SIMD3<Float>,
        cellSize: Float
    ) -> GaussianAssetVoxelKey {
        let offset = (position - minimum) / cellSize
        return GaussianAssetVoxelKey(
            x: Int32(floor(offset.x)),
            y: Int32(floor(offset.y)),
            z: Int32(floor(offset.z))
        )
    }

    private nonisolated static func localNeighborCount(
        around key: GaussianAssetVoxelKey,
        voxelCounts: [GaussianAssetVoxelKey: Int]
    ) -> Int {
        var count = 0
        for dx in -1...1 {
            for dy in -1...1 {
                for dz in -1...1 {
                    count += voxelCounts[
                        GaussianAssetVoxelKey(
                            x: key.x + Int32(dx),
                            y: key.y + Int32(dy),
                            z: key.z + Int32(dz)
                        ),
                        default: 0
                    ]
                }
            }
        }
        return count
    }

    private nonisolated static func recommendedScale(
        bounds: (minimum: SIMD3<Float>, maximum: SIMD3<Float>),
        pointCount: Int
    ) -> Float {
        let extent = bounds.maximum - bounds.minimum
        let safeExtent = max(max(extent.x, max(extent.y, extent.z)), 0.5)
        let spacing = safeExtent / sqrt(Float(max(pointCount, 1)))
        return min(0.0032, max(0.00055, spacing * 0.28))
    }

    private nonisolated static func shCoefficient(from srgb: Float) -> Float {
        let clamped = min(1, max(0, srgb))
        let linear: Float
        if clamped <= 0.04045 {
            linear = clamped / 12.92
        } else {
            linear = pow((clamped + 0.055) / 1.055, 2.4)
        }
        return (linear - 0.5) / 0.28209479177387814
    }

    private nonisolated static func logit(_ value: Float) -> Float {
        let clamped = min(0.999, max(0.001, value))
        return log(clamped / (1 - clamped))
    }

    private nonisolated static func readFloat(from pointer: UnsafeRawPointer, at offset: Int) -> Float {
        let value = pointer.advanced(by: offset).loadUnaligned(as: UInt32.self)
        return Float(bitPattern: UInt32(littleEndian: value))
    }
}
