//
//  TrailModels.swift
//  Trails
//
//  Domain data models matching the Stitch design system (docs/stitch/trails/DESIGN.md)
//  and screens (explore_dhun_map, place_overview_dhun_haveli, spatial_viewer_through_the_courtyard, review_publish_trail).
//

import Foundation
import CoreLocation

// MARK: - Place Models

public struct Place: Identifiable, Hashable, Codable {
    public let id: String
    public var name: String
    public var tagline: String
    public var surveyYear: String
    public var district: String
    public var locality: String
    public var description: String
    public var coverImageName: String?
    public var trailsCount: Int
    public var contributorsCount: Int
    public var latitude: Double
    public var longitude: Double
    public var category: PlaceCategory
    public var meshVersion: String
    public var floorLevels: [FloorLevel]
    public var authors: [PlaceAuthor]
    public var trails: [TrailSummary]

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public init(
        id: String,
        name: String,
        tagline: String,
        surveyYear: String,
        district: String,
        locality: String = "Dhun, Jaipur",
        description: String,
        coverImageName: String? = nil,
        trailsCount: Int,
        contributorsCount: Int,
        latitude: Double,
        longitude: Double,
        category: PlaceCategory,
        meshVersion: String = "LiDAR Mesh v2",
        floorLevels: [FloorLevel] = [],
        authors: [PlaceAuthor] = [],
        trails: [TrailSummary] = []
    ) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.surveyYear = surveyYear
        self.district = district
        self.locality = locality
        self.description = description
        self.coverImageName = coverImageName
        self.trailsCount = trailsCount
        self.contributorsCount = contributorsCount
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
        self.meshVersion = meshVersion
        self.floorLevels = floorLevels
        self.authors = authors
        self.trails = trails
    }
}

public enum PlaceCategory: String, CaseIterable, Identifiable, Codable {
    case all = "All Places"
    case dhunSurrounds = "Dhun & Surrounds"
    case courtyards = "Indoor Courtyards"
    case studios = "Artisan Studios"

    public var id: String { rawValue }
}

public struct FloorLevel: Identifiable, Hashable, Codable {
    public let id: String
    public let shortCode: String
    public let name: String
    public let elevationOffset: String

    public init(id: String, shortCode: String, name: String, elevationOffset: String = "+0.00m") {
        self.id = id
        self.shortCode = shortCode
        self.name = name
        self.elevationOffset = elevationOffset
    }
}

public struct PlaceAuthor: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let focusArea: String
    public let role: String

    public init(id: String, name: String, focusArea: String, role: String = "Architect & Spatial Explorer") {
        self.id = id
        self.name = name
        self.focusArea = focusArea
        self.role = role
    }
}

// MARK: - Trail Models

public struct TrailSummary: Identifiable, Hashable, Codable {
    public let id: String
    public var title: String
    public var subtitle: String
    public var placeName: String
    public var authorName: String
    public var authorRole: String
    public var distanceMeters: Int
    public var momentsCount: Int
    public var floorCode: String
    public var floorTitle: String
    public var meshDensity: String
    public var coverImageName: String?

    public init(
        id: String,
        title: String,
        subtitle: String,
        placeName: String,
        authorName: String,
        authorRole: String = "Architect & Spatial Explorer",
        distanceMeters: Int,
        momentsCount: Int,
        floorCode: String = "LVL 00",
        floorTitle: String = "Ground Floor",
        meshDensity: String = "98% density",
        coverImageName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.placeName = placeName
        self.authorName = authorName
        self.authorRole = authorRole
        self.distanceMeters = distanceMeters
        self.momentsCount = momentsCount
        self.floorCode = floorCode
        self.floorTitle = floorTitle
        self.meshDensity = meshDensity
        self.coverImageName = coverImageName
    }
}

public struct TrailDetail: Identifiable, Hashable, Codable {
    public let id: String
    public var title: String
    public var subtitle: String
    public var placeId: String
    public var placeName: String
    public var locality: String
    public var wing: String
    public var authorName: String
    public var authorRole: String
    public var distanceMeters: Int
    public var floorCode: String
    public var floorTitle: String
    public var meshDensity: String
    public var samplingFrequency: String
    public var nodeCount: Int
    public var personalNotes: String
    public var moments: [SpatialMoment]
    public var visibility: TrailVisibility
    public var isDraft: Bool
    public var coverImageName: String?
    public var latitude: Double?
    public var longitude: Double?
    public var inspiredByTrailId: String?
    public var inspiredByNote: String?
    public var isRetrace: Bool
    public var retraceSimilarityIndex: Double?
    public var retraceReferenceTrailTitle: String?
    public var retraceDate: Date?
    public var createdAt: Date
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, placeId, placeName, locality, wing
        case authorName, authorRole, distanceMeters, floorCode, floorTitle
        case meshDensity, samplingFrequency, nodeCount, personalNotes
        case moments, visibility, isDraft, coverImageName, latitude, longitude
        case inspiredByTrailId, inspiredByNote
        case isRetrace, retraceSimilarityIndex, retraceReferenceTrailTitle, retraceDate
        case createdAt, updatedAt
    }

    public var photoCount: Int {
        moments.filter { $0.hasPhoto || $0.mediaType == "photo" }.count
    }

    public var videoCount: Int {
        moments.filter { $0.hasVideo || $0.mediaType == "video" }.count
    }

    public var audioCount: Int {
        moments.filter { $0.hasAudio || $0.mediaType == "voice" }.count
    }

    public var mediaSummary: String {
        var parts: [String] = []
        if photoCount > 0 { parts.append("\(photoCount)P") }
        if videoCount > 0 { parts.append("\(videoCount)V") }
        if audioCount > 0 { parts.append("\(audioCount)A") }
        return parts.isEmpty ? "\(moments.count)M" : parts.joined(separator: " · ")
    }

    public var hasIndoorScan: Bool {
        meshDensity.contains("wall") || meshDensity.contains("LiDAR") || moments.contains { $0.placementStatus == "placed" && $0.positionZ != nil }
    }

    public var hasGeographicTrack: Bool {
        latitude != nil && longitude != nil
    }

    public init(
        id: String,
        title: String,
        subtitle: String,
        placeId: String,
        placeName: String,
        locality: String = "Dhun, Jaipur",
        wing: String,
        authorName: String,
        authorRole: String,
        distanceMeters: Int,
        floorCode: String = "LVL 00",
        floorTitle: String = "Ground Floor",
        meshDensity: String = "98% density",
        samplingFrequency: String = "24.6 kHz",
        nodeCount: Int = 4,
        personalNotes: String = "",
        moments: [SpatialMoment] = [],
        visibility: TrailVisibility = .privateDraft,
        isDraft: Bool = false,
        coverImageName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        inspiredByTrailId: String? = nil,
        inspiredByNote: String? = nil,
        isRetrace: Bool = false,
        retraceSimilarityIndex: Double? = nil,
        retraceReferenceTrailTitle: String? = nil,
        retraceDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.placeId = placeId
        self.placeName = placeName
        self.locality = locality
        self.wing = wing
        self.authorName = authorName
        self.authorRole = authorRole
        self.distanceMeters = distanceMeters
        self.floorCode = floorCode
        self.floorTitle = floorTitle
        self.meshDensity = meshDensity
        self.samplingFrequency = samplingFrequency
        self.nodeCount = nodeCount
        self.personalNotes = personalNotes
        self.moments = moments
        self.visibility = visibility
        self.isDraft = isDraft
        self.coverImageName = coverImageName
        self.latitude = latitude
        self.longitude = longitude
        self.inspiredByTrailId = inspiredByTrailId
        self.inspiredByNote = inspiredByNote
        self.isRetrace = isRetrace
        self.retraceSimilarityIndex = retraceSimilarityIndex
        self.retraceReferenceTrailTitle = retraceReferenceTrailTitle
        self.retraceDate = retraceDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.subtitle = try container.decode(String.self, forKey: .subtitle)
        self.placeId = try container.decode(String.self, forKey: .placeId)
        self.placeName = try container.decode(String.self, forKey: .placeName)
        self.locality = try container.decodeIfPresent(String.self, forKey: .locality) ?? "Dhun, Jaipur"
        self.wing = try container.decodeIfPresent(String.self, forKey: .wing) ?? "Main"
        self.authorName = try container.decodeIfPresent(String.self, forKey: .authorName) ?? "A trail by you"
        self.authorRole = try container.decodeIfPresent(String.self, forKey: .authorRole) ?? "Explorer"
        self.distanceMeters = try container.decodeIfPresent(Int.self, forKey: .distanceMeters) ?? 0
        self.floorCode = try container.decodeIfPresent(String.self, forKey: .floorCode) ?? "LVL 00"
        self.floorTitle = try container.decodeIfPresent(String.self, forKey: .floorTitle) ?? "Ground Floor"
        self.meshDensity = try container.decodeIfPresent(String.self, forKey: .meshDensity) ?? "LiDAR Route"
        self.samplingFrequency = try container.decodeIfPresent(String.self, forKey: .samplingFrequency) ?? "24.6 kHz"
        self.nodeCount = try container.decodeIfPresent(Int.self, forKey: .nodeCount) ?? 0
        self.personalNotes = try container.decodeIfPresent(String.self, forKey: .personalNotes) ?? ""
        self.moments = try container.decodeIfPresent([SpatialMoment].self, forKey: .moments) ?? []
        self.visibility = try container.decodeIfPresent(TrailVisibility.self, forKey: .visibility) ?? .privateDraft
        self.isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
        self.coverImageName = try container.decodeIfPresent(String.self, forKey: .coverImageName)
        self.latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        self.longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        self.inspiredByTrailId = try container.decodeIfPresent(String.self, forKey: .inspiredByTrailId)
        self.inspiredByNote = try container.decodeIfPresent(String.self, forKey: .inspiredByNote)
        self.isRetrace = try container.decodeIfPresent(Bool.self, forKey: .isRetrace) ?? false
        self.retraceSimilarityIndex = try container.decodeIfPresent(Double.self, forKey: .retraceSimilarityIndex)
        self.retraceReferenceTrailTitle = try container.decodeIfPresent(String.self, forKey: .retraceReferenceTrailTitle)
        self.retraceDate = try container.decodeIfPresent(Date.self, forKey: .retraceDate)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

public struct SpatialMoment: Identifiable, Hashable, Codable {
    public let id: String
    public var index: Int
    public var title: String
    public var subtitle: String
    public var narrative: String
    public var architecturalNote: String
    public var distanceAlongPathMeters: Int
    public var relativeElevation: String
    public var audioDuration: String?
    public var videoDuration: String?
    public var hasAudio: Bool
    public var hasPhoto: Bool
    public var hasVideo: Bool
    public var mediaType: String // "note" | "photo" | "voice" | "video"
    public var photoAssetName: String?
    public var photoFileName: String?
    public var audioFileName: String?
    public var videoFileName: String?
    public var videoThumbnailAssetName: String?
    public var positionX: Double // Local survey coordinate X
    public var positionY: Double // Local survey coordinate Y (or Z in 3D frame)
    public var positionZ: Double?
    public var headingDegrees: Double? // Orientation / Compass heading when captured
    public var placementStatus: String // "placed" | "unplaced" per PRD §12.4
    public var createdAt: Date

    public init(
        id: String,
        index: Int,
        title: String,
        subtitle: String,
        narrative: String,
        architecturalNote: String,
        distanceAlongPathMeters: Int,
        relativeElevation: String = "+0.00m",
        audioDuration: String? = nil,
        videoDuration: String? = nil,
        hasAudio: Bool = false,
        hasPhoto: Bool = false,
        hasVideo: Bool = false,
        mediaType: String = "note",
        photoAssetName: String? = nil,
        photoFileName: String? = nil,
        audioFileName: String? = nil,
        videoFileName: String? = nil,
        videoThumbnailAssetName: String? = nil,
        positionX: Double = 0.5,
        positionY: Double = 0.5,
        positionZ: Double? = 0.0,
        headingDegrees: Double? = nil,
        placementStatus: String = "placed",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.subtitle = subtitle
        self.narrative = narrative
        self.architecturalNote = architecturalNote
        self.distanceAlongPathMeters = distanceAlongPathMeters
        self.relativeElevation = relativeElevation
        self.audioDuration = audioDuration
        self.videoDuration = videoDuration
        self.hasAudio = hasAudio
        self.hasPhoto = hasPhoto
        self.hasVideo = hasVideo
        self.mediaType = mediaType
        self.photoAssetName = photoAssetName
        self.photoFileName = photoFileName
        self.audioFileName = audioFileName
        self.videoFileName = videoFileName
        self.videoThumbnailAssetName = videoThumbnailAssetName
        self.positionX = positionX
        self.positionY = positionY
        self.positionZ = positionZ
        self.headingDegrees = headingDegrees
        self.placementStatus = placementStatus
        self.createdAt = createdAt
    }

    public func resolvedPhotoURL(trailId: String, fallbackTrailId: String? = nil) -> URL? {
        if let fileName = photoFileName {
            let fileURL = TrailPackageStore.shared.mediaDirectory(for: trailId).appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
            if let fallback = fallbackTrailId {
                let fallbackURL = TrailPackageStore.shared.mediaDirectory(for: fallback).appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: fallbackURL.path) {
                    return fallbackURL
                }
            }
        }
        return nil
    }

    public func resolvedVideoURL(trailId: String, fallbackTrailId: String? = nil) -> URL? {
        if let fileName = videoFileName {
            let fileURL = TrailPackageStore.shared.mediaDirectory(for: trailId).appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
            if let fallback = fallbackTrailId {
                let fallbackURL = TrailPackageStore.shared.mediaDirectory(for: fallback).appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: fallbackURL.path) {
                    return fallbackURL
                }
            }
        }
        return nil
    }

    public func resolvedVideoThumbnailURL(trailId: String, fallbackTrailId: String? = nil) -> URL? {
        if let fileName = videoThumbnailAssetName ?? photoFileName {
            let fileURL = TrailPackageStore.shared.mediaDirectory(for: trailId).appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
            if let fallback = fallbackTrailId {
                let fallbackURL = TrailPackageStore.shared.mediaDirectory(for: fallback).appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: fallbackURL.path) {
                    return fallbackURL
                }
            }
        }
        return nil
    }

    public func resolvedAudioURL(trailId: String, fallbackTrailId: String? = nil) -> URL? {
        if let fileName = audioFileName {
            let fileURL = TrailPackageStore.shared.mediaDirectory(for: trailId).appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
            if let fallback = fallbackTrailId {
                let fallbackURL = TrailPackageStore.shared.mediaDirectory(for: fallback).appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: fallbackURL.path) {
                    return fallbackURL
                }
            }
        }
        return nil
    }
}

// MARK: - Retrace Session Model (PRD v0.3.0)

public struct RetraceSession: Identifiable, Codable {
    public let id: String
    public let sourceTrailId: String
    public var startedAt: Date
    public var endedAt: Date?
    public var distanceWalkedMeters: Int
    public var visitedMomentIds: [String]
    public var similarityIndex: Double // 0.0 to 1.0 (PRD v0.3.0 similarity metric)
    public var pathCoveragePercentage: Double // 0.0 to 1.0
    public var checkpointsOrder: [String] // IDs in order visited (supports out-of-order retrace)
    public var positioningMode: String // PRD v0.3.1 §5: "localSpatialAligned", "localSpatialUnaligned", "manualFollowAlong", "geographic"
    public var alignmentState: String // PRD v0.3.1 §8: "unavailable", "loading", "searching", "verifying", "aligned", "degraded", "lost"
    public var alignmentMethod: String? // "arWorldMap", "twoPointReference", "manualProgression"
    public var referenceFrameId: String?
    public var segmentIds: [String]
    public var newMoments: [SpatialMoment]

    public init(
        id: String = UUID().uuidString,
        sourceTrailId: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        distanceWalkedMeters: Int = 0,
        visitedMomentIds: [String] = [],
        similarityIndex: Double = 0.0,
        pathCoveragePercentage: Double = 0.0,
        checkpointsOrder: [String] = [],
        positioningMode: String = "localSpatialUnaligned",
        alignmentState: String = "searching",
        alignmentMethod: String? = nil,
        referenceFrameId: String? = nil,
        segmentIds: [String] = [],
        newMoments: [SpatialMoment] = []
    ) {
        self.id = id
        self.sourceTrailId = sourceTrailId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceWalkedMeters = distanceWalkedMeters
        self.visitedMomentIds = visitedMomentIds
        self.similarityIndex = similarityIndex
        self.pathCoveragePercentage = pathCoveragePercentage
        self.checkpointsOrder = checkpointsOrder
        self.positioningMode = positioningMode
        self.alignmentState = alignmentState
        self.alignmentMethod = alignmentMethod
        self.referenceFrameId = referenceFrameId
        self.segmentIds = segmentIds
        self.newMoments = newMoments
    }
}

// MARK: - PRD v0.3.1 Reference Frame & Alignment Tracking Models

public struct ReferenceFrame: Codable, Hashable {
    public let id: String
    public let sourceSessionId: String
    public let units: String // "meters"
    public let axisConvention: String // "rightHanded_YUp_ZBack" (ARKit)
    public let worldAlignmentConfiguration: String // "gravityAndHeading" or "gravity"
    public let createdAt: Date
    public let positioningMethod: String // "arWorldMap", "manualAnchor", "gps"
    public let alignmentAssetReferences: [String]

    public init(
        id: String = UUID().uuidString,
        sourceSessionId: String,
        units: String = "meters",
        axisConvention: String = "rightHanded_YUp_ZBack",
        worldAlignmentConfiguration: String = "gravityAndHeading",
        createdAt: Date = Date(),
        positioningMethod: String = "arWorldMap",
        alignmentAssetReferences: [String] = []
    ) {
        self.id = id
        self.sourceSessionId = sourceSessionId
        self.units = units
        self.axisConvention = axisConvention
        self.worldAlignmentConfiguration = worldAlignmentConfiguration
        self.createdAt = createdAt
        self.positioningMethod = positioningMethod
        self.alignmentAssetReferences = alignmentAssetReferences
    }
}

public struct TrackingSegment: Identifiable, Codable {
    public let id: String
    public let sessionId: String
    public let coordinateFrameId: String
    public let startedAt: Date
    public var endedAt: Date?
    public var rawPathReference: String?
    public var transformToReference: [Float]?
    public var transformStatus: String // "identity", "aligned", "unaligned"
    public var interruptionReason: String?

    public init(
        id: String = UUID().uuidString,
        sessionId: String,
        coordinateFrameId: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        rawPathReference: String? = nil,
        transformToReference: [Float]? = nil,
        transformStatus: String = "identity",
        interruptionReason: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.coordinateFrameId = coordinateFrameId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.rawPathReference = rawPathReference
        self.transformToReference = transformToReference
        self.transformStatus = transformStatus
        self.interruptionReason = interruptionReason
    }
}

public struct AlignmentAttempt: Identifiable, Codable {
    public let id: String
    public let retraceSessionId: String
    public var referenceAssetIds: [String]
    public var method: String // "arWorldMap", "twoPointReference", "manualFallback"
    public var startedAt: Date
    public var endedAt: Date?
    public var outcome: String // "success", "failed", "timeout", "manualFallback"
    public var verificationResults: String?
    public var failureReason: String?

    public init(
        id: String = UUID().uuidString,
        retraceSessionId: String,
        referenceAssetIds: [String] = [],
        method: String = "arWorldMap",
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        outcome: String = "pending",
        verificationResults: String? = nil,
        failureReason: String? = nil
    ) {
        self.id = id
        self.retraceSessionId = retraceSessionId
        self.referenceAssetIds = referenceAssetIds
        self.method = method
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.outcome = outcome
        self.verificationResults = verificationResults
        self.failureReason = failureReason
    }
}

public enum TrailVisibility: String, CaseIterable, Identifiable, Codable {
    case privateDraft = "Private (Only me)"
    case sharedLink = "Shared (Link)"
    case publicPlace = "Public"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .privateDraft:
            return "Stays exclusively on this iPhone. Only you can view or replay."
        case .sharedLink:
            return "Anyone with your unique link can open this trail. Not listed in public directory."
        case .publicPlace:
            return "Saved to local collection. Ready for future peer exchange."
        }
    }
}

// MARK: - PRD §11 & §12 File Package Models

public struct PathSampleRecord: Codable, Hashable {
    public let timestamp: Double
    public let positionX: Float
    public let positionY: Float
    public let positionZ: Float
    public let trackingState: String

    public init(timestamp: Double, positionX: Float, positionY: Float, positionZ: Float, trackingState: String = "normal") {
        self.timestamp = timestamp
        self.positionX = positionX
        self.positionY = positionY
        self.positionZ = positionZ
        self.trackingState = trackingState
    }
}

public struct LocalProfile: Codable, Hashable {
    public var id: String
    public var displayName: String
    public var introduction: String
    public var interests: [String]

    public init(
        id: String = UUID().uuidString,
        displayName: String = "A trail by you",
        introduction: String = "Spatial explorer documenting living spaces.",
        interests: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.introduction = introduction
        self.interests = interests
    }
}

// MARK: - TrailPackageStore (PRD §11 & §12 File Persistence Coordinator)

import simd

public final class TrailPackageStore {
    public static let shared = TrailPackageStore()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        ensureBaseDirectoriesExist()
    }

    // MARK: - Directory Resolution (PRD §11.1)

    public var baseDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Trails", isDirectory: true)
    }

    public var trailsDirectory: URL {
        baseDirectory.appendingPathComponent("trails", isDirectory: true)
    }

    public var placesDirectory: URL {
        baseDirectory.appendingPathComponent("places", isDirectory: true)
    }

    public var profilesDirectory: URL {
        baseDirectory.appendingPathComponent("profiles", isDirectory: true)
    }

    public var libraryIndexURL: URL {
        baseDirectory.appendingPathComponent("library-index.json")
    }

    public var localProfileURL: URL {
        profilesDirectory.appendingPathComponent("local-profile.json")
    }

    private func ensureBaseDirectoriesExist() {
        try? fileManager.createDirectory(at: trailsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: placesDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Local Identity (PRD §9.1 & §12.5)

    public func loadLocalProfile() -> LocalProfile {
        if let data = try? Data(contentsOf: localProfileURL),
           let profile = try? decoder.decode(LocalProfile.self, from: data) {
            return profile
        }
        let defaultProfile = LocalProfile(
            id: UUID().uuidString,
            displayName: "A trail by you",
            introduction: "Spatial explorer documenting living spaces.",
            interests: []
        )
        saveLocalProfile(defaultProfile)
        return defaultProfile
    }

    public func saveLocalProfile(_ profile: LocalProfile) {
        ensureBaseDirectoriesExist()
        if let data = try? encoder.encode(profile) {
            try? data.write(to: localProfileURL, options: .atomic)
        }
    }

    // MARK: - Trail Packages (PRD §11.1 & §12.1)

    public func trailDirectory(for id: String) -> URL {
        trailsDirectory.appendingPathComponent(id, isDirectory: true)
    }

    public func saveTrailPackage(trail: TrailDetail, footsteps: [SIMD3<Float>]) {
        let dir = trailDirectory(for: trail.id)
        let trackingDir = dir.appendingPathComponent("tracking", isDirectory: true)
        try? fileManager.createDirectory(at: trackingDir, withIntermediateDirectories: true)

        // 1. Save manifest.json
        let manifestURL = dir.appendingPathComponent("manifest.json")
        if let data = try? encoder.encode(trail) {
            try? data.write(to: manifestURL, options: .atomic)
        }

        // 2. Save moments.json
        let momentsURL = dir.appendingPathComponent("moments.json")
        if let data = try? encoder.encode(trail.moments) {
            try? data.write(to: momentsURL, options: .atomic)
        }

        // 3. Save tracking/samples.json
        let samplesURL = trackingDir.appendingPathComponent("samples.json")
        let now = Date().timeIntervalSince1970
        let sampleRecords = footsteps.enumerated().map { index, step in
            PathSampleRecord(
                timestamp: now + Double(index) * 0.1,
                positionX: step.x,
                positionY: step.y,
                positionZ: step.z,
                trackingState: "normal"
            )
        }
        if let data = try? encoder.encode(sampleRecords) {
            try? data.write(to: samplesURL, options: .atomic)
        }

        updateLibraryIndex()
    }

    public func updateTrailMetadata(trail: TrailDetail) {
        let dir = trailDirectory(for: trail.id)
        guard fileManager.fileExists(atPath: dir.path) else {
            saveTrailPackage(trail: trail, footsteps: [])
            return
        }

        let manifestURL = dir.appendingPathComponent("manifest.json")
        if let data = try? encoder.encode(trail) {
            try? data.write(to: manifestURL, options: .atomic)
        }

        let momentsURL = dir.appendingPathComponent("moments.json")
        if let data = try? encoder.encode(trail.moments) {
            try? data.write(to: momentsURL, options: .atomic)
        }

        updateLibraryIndex()
    }

    public func loadAllTrails() -> [TrailDetail] {
        ensureBaseDirectoriesExist()
        guard let trailDirs = try? fileManager.contentsOfDirectory(at: trailsDirectory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }

        var trails: [TrailDetail] = []
        for dir in trailDirs {
            let manifestURL = dir.appendingPathComponent("manifest.json")
            let momentsURL = dir.appendingPathComponent("moments.json")

            guard let manifestData = try? Data(contentsOf: manifestURL),
                  var trail = try? decoder.decode(TrailDetail.self, from: manifestData) else {
                continue
            }

            if let momentsData = try? Data(contentsOf: momentsURL),
               let moments = try? decoder.decode([SpatialMoment].self, from: momentsData) {
                trail.moments = moments
            }

            trails.append(trail)
        }

        return trails.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func loadFootsteps(for trailId: String) -> [SIMD3<Float>] {
        let samplesURL = trailDirectory(for: trailId)
            .appendingPathComponent("tracking", isDirectory: true)
            .appendingPathComponent("samples.json")

        guard let data = try? Data(contentsOf: samplesURL),
              let records = try? decoder.decode([PathSampleRecord].self, from: data) else {
            return []
        }

        return records.map { SIMD3<Float>($0.positionX, $0.positionY, $0.positionZ) }
    }

    // MARK: - Retrace Sessions (PRD v0.3.0 §2 & §7)

    public func saveRetraceSession(session: RetraceSession, footsteps: [SIMD3<Float>]) {
        let dir = trailDirectory(for: session.sourceTrailId).appendingPathComponent("retraces", isDirectory: true)
        let sessionDir = dir.appendingPathComponent(session.id, isDirectory: true)
        try? fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let sessionFile = sessionDir.appendingPathComponent("session.json")
        if let data = try? encoder.encode(session) {
            try? data.write(to: sessionFile, options: .atomic)
        }

        let samplesFile = sessionDir.appendingPathComponent("samples.json")
        let now = Date().timeIntervalSince1970
        let sampleRecords = footsteps.enumerated().map { index, step in
            PathSampleRecord(
                timestamp: now + Double(index) * 0.1,
                positionX: step.x,
                positionY: step.y,
                positionZ: step.z,
                trackingState: "retrace"
            )
        }
        if let data = try? encoder.encode(sampleRecords) {
            try? data.write(to: samplesFile, options: .atomic)
        }
    }

    public func loadRetraceSessions(for sourceTrailId: String) -> [RetraceSession] {
        let dir = trailDirectory(for: sourceTrailId).appendingPathComponent("retraces", isDirectory: true)
        guard let subdirs = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        var sessions: [RetraceSession] = []
        for subdir in subdirs {
            let file = subdir.appendingPathComponent("session.json")
            if let data = try? Data(contentsOf: file),
               let s = try? decoder.decode(RetraceSession.self, from: data) {
                sessions.append(s)
            }
        }
        return sessions.sorted(by: { $0.startedAt > $1.startedAt })
    }

    public func mediaDirectory(for trailId: String) -> URL {
        let dir = trailDirectory(for: trailId).appendingPathComponent("media", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func copyAssets(from sourceTrailId: String, to destinationTrailId: String) {
        let srcMediaDir = mediaDirectory(for: sourceTrailId)
        let dstMediaDir = mediaDirectory(for: destinationTrailId)
        if let files = try? fileManager.contentsOfDirectory(atPath: srcMediaDir.path) {
            for file in files {
                let srcFile = srcMediaDir.appendingPathComponent(file)
                let dstFile = dstMediaDir.appendingPathComponent(file)
                if !fileManager.fileExists(atPath: dstFile.path) {
                    try? fileManager.copyItem(at: srcFile, to: dstFile)
                }
            }
        }

        let srcSpatialDir = spatialDirectory(for: sourceTrailId)
        let dstSpatialDir = spatialDirectory(for: destinationTrailId)
        if let files = try? fileManager.contentsOfDirectory(atPath: srcSpatialDir.path) {
            for file in files {
                let srcFile = srcSpatialDir.appendingPathComponent(file)
                let dstFile = dstSpatialDir.appendingPathComponent(file)
                if !fileManager.fileExists(atPath: dstFile.path) {
                    try? fileManager.copyItem(at: srcFile, to: dstFile)
                }
            }
        }
    }

    // MARK: - Spatial & Reference Frame Storage (PRD v0.3.1 §6 & §7)

    public func spatialDirectory(for trailId: String) -> URL {
        let dir = trailDirectory(for: trailId).appendingPathComponent("spatial", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func worldMapURL(for trailId: String) -> URL {
        spatialDirectory(for: trailId).appendingPathComponent("worldmap.arworldmap")
    }

    public func referenceFrameURL(for trailId: String) -> URL {
        spatialDirectory(for: trailId).appendingPathComponent("reference-frame.json")
    }

    public func hasWorldMap(for trailId: String) -> Bool {
        fileManager.fileExists(atPath: worldMapURL(for: trailId).path)
    }

    public func saveWorldMapData(_ data: Data, for trailId: String) {
        let url = worldMapURL(for: trailId)
        try? data.write(to: url, options: .atomic)
    }

    public func loadWorldMapData(for trailId: String) -> Data? {
        let url = worldMapURL(for: trailId)
        return try? Data(contentsOf: url)
    }

    public func saveReferenceFrame(_ frame: ReferenceFrame, for trailId: String) {
        let url = referenceFrameURL(for: trailId)
        if let data = try? encoder.encode(frame) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public func loadReferenceFrame(for trailId: String) -> ReferenceFrame? {
        let url = referenceFrameURL(for: trailId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ReferenceFrame.self, from: data)
    }

    // MARK: - Places Persistence (PRD §12 & §14)

    public func savePlace(_ place: Place) {
        ensureBaseDirectoriesExist()
        let dir = placesDirectory.appendingPathComponent(place.id, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let placeURL = dir.appendingPathComponent("place.json")
        if let data = try? encoder.encode(place) {
            try? data.write(to: placeURL, options: .atomic)
        }
    }

    public func loadAllPlaces() -> [Place] {
        ensureBaseDirectoriesExist()
        guard let placeDirs = try? fileManager.contentsOfDirectory(at: placesDirectory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        var places: [Place] = []
        for dir in placeDirs {
            let placeURL = dir.appendingPathComponent("place.json")
            if let data = try? Data(contentsOf: placeURL),
               let place = try? decoder.decode(Place.self, from: data) {
                places.append(place)
            }
        }
        return places
    }

    public func deleteTrailPackage(id: String) {
        let dir = trailDirectory(for: id)
        try? fileManager.removeItem(at: dir)
        updateLibraryIndex()
    }

    private func updateLibraryIndex() {
        let allTrails = loadAllTrails()
        let summaries = allTrails.map { trail in
            TrailSummary(
                id: trail.id,
                title: trail.title,
                subtitle: trail.subtitle,
                placeName: trail.placeName,
                authorName: trail.authorName,
                authorRole: trail.authorRole,
                distanceMeters: trail.distanceMeters,
                momentsCount: trail.moments.count,
                floorCode: trail.floorCode,
                floorTitle: trail.floorTitle,
                meshDensity: trail.meshDensity
            )
        }
        if let data = try? encoder.encode(summaries) {
            try? data.write(to: libraryIndexURL, options: .atomic)
        }
    }
}
