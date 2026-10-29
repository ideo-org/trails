import Foundation
import SwiftData

enum GaussianAssetStatus: String, Codable {
    case none
    case queued
    case building
    case ready
    case failed
}

struct GaussianAssetManifest: Codable {
    static let currentVersion = 4

    let version: Int
    let createdAt: Date
    let gaussianCount: Int
    let sourcePointCount: Int
    let keyframeCount: Int
    let splatFileName: String
    let gaussianPLYFileName: String
    let spzFileName: String?
    let sogFileName: String?
    let boundsMinimum: [Float]
    let boundsMaximum: [Float]
}

struct GaussianCaptureBundleManifest: Codable {
    let version: Int
    let createdAt: Date
    let directoryName: String
    let keyframes: [GaussianKeyframeMetadata]
}

struct GaussianKeyframeMetadata: Codable {
    let colorFileName: String
    let depthFileName: String
    let timestamp: TimeInterval
    let imageWidth: Int
    let imageHeight: Int
    let depthWidth: Int
    let depthHeight: Int
    let intrinsics: [Float]
    let transform: [Float]
}

struct GaussianBuildResult {
    let manifestFileName: String
    let splatFileName: String
    let gaussianPLYFileName: String
    let spzFileName: String?
    let sogFileName: String?
}

struct GaussianPreviewBuildResult {
    let gaussianPLYFileName: String
}

extension Scan {
    var gaussianStatus: GaussianAssetStatus {
        get { GaussianAssetStatus(rawValue: gaussianStatusRaw) ?? .none }
        set { gaussianStatusRaw = newValue.rawValue }
    }

    var hasReadyGaussianAsset: Bool {
        gaussianStatus == .ready
            && gaussianSplatFileName != nil
            && gaussianPLYFileName != nil
    }

    var needsGaussianAssetRebuild: Bool {
        guard gaussianStatus == .ready else { return false }
        guard !plyFileNames.isEmpty else { return false }
        guard let manifestFileName = gaussianAssetManifestFileName else { return true }
        let manifestURL = ScanFileStore.fileURL(fileName: manifestFileName)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(GaussianAssetManifest.self, from: data) else {
            return true
        }
        return manifest.version < GaussianAssetManifest.currentVersion
    }

    var hasInterruptedGaussianBuild: Bool {
        gaussianStatus == .building
    }
}
