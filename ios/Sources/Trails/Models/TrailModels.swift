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
        coverImageName: String? = "DhunHaveliEvening",
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
    case pavilions = "Historic Pavilions"
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
    public var createdAt: Date
    public var updatedAt: Date

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
        coverImageName: String? = "DhunHaveliEvening",
        latitude: Double? = 26.9124,
        longitude: Double? = 75.7873,
        inspiredByTrailId: String? = nil,
        inspiredByNote: String? = nil,
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
    public var audioFileName: String?
    public var videoFileName: String?
    public var videoThumbnailAssetName: String?
    public var positionX: Double // Local survey coordinate X
    public var positionY: Double // Local survey coordinate Y (or Z in 3D frame)
    public var positionZ: Double?
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
        audioFileName: String? = nil,
        videoFileName: String? = nil,
        videoThumbnailAssetName: String? = nil,
        positionX: Double = 0.5,
        positionY: Double = 0.5,
        positionZ: Double? = 0.0,
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
        self.audioFileName = audioFileName
        self.videoFileName = videoFileName
        self.videoThumbnailAssetName = videoThumbnailAssetName
        self.positionX = positionX
        self.positionY = positionY
        self.positionZ = positionZ
        self.placementStatus = placementStatus
        self.createdAt = createdAt
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

    public func mediaDirectory(for trailId: String) -> URL {
        let dir = trailDirectory(for: trailId).appendingPathComponent("media", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
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
