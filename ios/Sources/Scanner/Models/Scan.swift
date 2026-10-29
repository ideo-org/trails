//
//  Scan.swift
//  Trails
//
//  SwiftData model for spatial captures.
//

import Foundation
import SwiftData

@Model
final class Scan {
    @Attribute(.unique) var id: UUID
    var title: String
    var timestamp: Date
    var updatedAt: Date
    var pointCount: Int
    var fileSize: Int64
    var latitude: Double?
    var longitude: Double?
    var thumbnailData: Data?
    var plyFileName: String
    var subscanMetadataJSON: String?
    var snapFileNames: [String]
    var snapshotMetadataJSON: String?
    var syncStatusRaw: String
    var remoteDocumentID: String
    var remoteStoragePath: String
    var remoteSubscanStoragePaths: [String] = []
    var remoteSnapshotStoragePaths: [String]
    var lastSyncedAt: Date?
    var syncErrorMessage: String?
    var gaussianStatusRaw: String = GaussianAssetStatus.none.rawValue
    var gaussianCaptureManifestFileName: String?
    var gaussianAssetManifestFileName: String?
    var gaussianSplatFileName: String?
    var gaussianPLYFileName: String?
    var gaussianSPZFileName: String?
    var gaussianSOGFileName: String?
    var gaussianErrorMessage: String?

    init(
        id: UUID = UUID(),
        title: String,
        timestamp: Date = Date(),
        updatedAt: Date = Date(),
        pointCount: Int = 0,
        fileSize: Int64 = 0,
        latitude: Double? = nil,
        longitude: Double? = nil,
        thumbnailData: Data? = nil,
        plyFileName: String,
        subscanMetadataJSON: String? = nil,
        snapFileNames: [String] = [],
        snapshotMetadataJSON: String? = nil,
        syncStatusRaw: String = ScanSyncStatus.localOnly.rawValue,
        remoteDocumentID: String = "",
        remoteStoragePath: String = "",
        remoteSubscanStoragePaths: [String] = [],
        remoteSnapshotStoragePaths: [String] = [],
        lastSyncedAt: Date? = nil,
        syncErrorMessage: String? = nil,
        gaussianStatusRaw: String = GaussianAssetStatus.none.rawValue,
        gaussianCaptureManifestFileName: String? = nil,
        gaussianAssetManifestFileName: String? = nil,
        gaussianSplatFileName: String? = nil,
        gaussianPLYFileName: String? = nil,
        gaussianSPZFileName: String? = nil,
        gaussianSOGFileName: String? = nil,
        gaussianErrorMessage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.timestamp = timestamp
        self.updatedAt = updatedAt
        self.pointCount = pointCount
        self.fileSize = fileSize
        self.latitude = latitude
        self.longitude = longitude
        self.thumbnailData = thumbnailData
        self.plyFileName = plyFileName
        self.subscanMetadataJSON = subscanMetadataJSON
        self.snapFileNames = snapFileNames
        self.snapshotMetadataJSON = snapshotMetadataJSON
        self.syncStatusRaw = syncStatusRaw
        self.remoteDocumentID = remoteDocumentID
        self.remoteStoragePath = remoteStoragePath
        self.remoteSubscanStoragePaths = remoteSubscanStoragePaths
        self.remoteSnapshotStoragePaths = remoteSnapshotStoragePaths
        self.lastSyncedAt = lastSyncedAt
        self.syncErrorMessage = syncErrorMessage
        self.gaussianStatusRaw = gaussianStatusRaw
        self.gaussianCaptureManifestFileName = gaussianCaptureManifestFileName
        self.gaussianAssetManifestFileName = gaussianAssetManifestFileName
        self.gaussianSplatFileName = gaussianSplatFileName
        self.gaussianPLYFileName = gaussianPLYFileName
        self.gaussianSPZFileName = gaussianSPZFileName
        self.gaussianSOGFileName = gaussianSOGFileName
        self.gaussianErrorMessage = gaussianErrorMessage
    }
}

struct ScanPart: Codable, Hashable, Identifiable {
    let index: Int
    let fileName: String
    let pointCount: Int
    let fileSize: Int64
    let thumbnailFileName: String?

    var id: String { fileName }

    init(
        index: Int,
        fileName: String,
        pointCount: Int,
        fileSize: Int64,
        thumbnailFileName: String? = nil
    ) {
        self.index = index
        self.fileName = fileName
        self.pointCount = pointCount
        self.fileSize = fileSize
        self.thumbnailFileName = thumbnailFileName
    }

    static func encode(_ parts: [ScanPart]) -> String? {
        guard !parts.isEmpty,
              let data = try? JSONEncoder().encode(parts) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String?) -> [ScanPart] {
        guard let json,
              let data = json.data(using: .utf8),
              let parts = try? JSONDecoder().decode([ScanPart].self, from: data) else {
            return []
        }

        return parts.sorted { $0.index < $1.index }
    }
}

extension Scan {
    var syncStatus: ScanSyncStatus {
        get { ScanSyncStatus(rawValue: syncStatusRaw) ?? .localOnly }
        set { syncStatusRaw = newValue.rawValue }
    }

    var snapshots: [ScanSnapshot] {
        get { ScanSnapshot.decode(snapshotMetadataJSON) }
        set {
            snapshotMetadataJSON = ScanSnapshot.encode(newValue)
            snapFileNames = newValue.map(\.fileName)
        }
    }

    var scanParts: [ScanPart] {
        get {
            let decoded = ScanPart.decode(subscanMetadataJSON)
            guard decoded.isEmpty else { return decoded }

            return [
                ScanPart(
                    index: 1,
                    fileName: plyFileName,
                    pointCount: pointCount,
                    fileSize: fileSize
                )
            ]
        }
        set {
            let sortedParts = newValue.sorted { $0.index < $1.index }
            subscanMetadataJSON = ScanPart.encode(sortedParts)
            if let firstPart = sortedParts.first {
                plyFileName = firstPart.fileName
            }
        }
    }

    var plyFileNames: [String] {
        scanParts.map(\.fileName)
    }
}
