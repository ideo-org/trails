//
//  TrailsDataStore.swift
//  Trails
//
//  Data store providing local persistence and rich spatial monograph data
//  aligned with PRD v0.2.0 (A Living Spatial Journal) and docs/stitch/v0.2.0.
//

import Foundation
import Combine
import simd

public enum CollectionMode: String, CaseIterable, Identifiable {
    case journal = "Journal"
    case map = "Map"

    public var id: String { rawValue }
}

// PRD v0.4.0 §14 My Trails Filters (All | Recorded by me | Downloaded)
public enum MyTrailsFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case recordedByMe = "Recorded by me"
    case downloaded = "Downloaded"

    public var id: String { rawValue }
}

@MainActor
public final class TrailsDataStore: ObservableObject {
    public static let shared = TrailsDataStore()

    @Published public var places: [Place] = []
    @Published public var activeTrail: TrailDetail?
    @Published public var selectedPlace: Place?
    @Published public var userDrafts: [TrailDetail] = []
    @Published public var savedTrails: [TrailDetail] = []
    @Published public var sampleTrails: [TrailDetail] = []
    @Published public var localProfile: LocalProfile = LocalProfile()

    // v0.2.0 Collection & Filter State (PRD §11 & §12)
    @Published public var collectionMode: CollectionMode = .journal
    @Published public var myTrailsFilter: MyTrailsFilter = .all
    @Published public var searchText: String = ""
    @Published public var selectedYearFilter: String? = nil
    @Published public var selectedPlaceFilter: String? = nil
    @Published public var targetPlaceForRecording: Place? = nil

    private let packageStore = TrailPackageStore.shared

    public init() {
        loadInitialData()
        reloadFromDisk()
    }

    public func reloadFromDisk() {
        self.localProfile = packageStore.loadLocalProfile()
        let diskTrails = packageStore.loadAllTrails().map { sanitizeTrail($0) }
        self.savedTrails = diskTrails.filter { !$0.isDraft }
        let diskDrafts = diskTrails.filter { $0.isDraft }
        if !diskDrafts.isEmpty {
            self.userDrafts = diskDrafts
        }

        let diskPlaces = packageStore.loadAllPlaces().filter {
            $0.id != "dhun-haveli" && $0.id != "craft-quarter" && !$0.name.lowercased().contains("dhun")
        }
        if !diskPlaces.isEmpty {
            self.places = diskPlaces
        } else {
            self.places = generatePlacesFromTrails(self.savedTrails)
        }

        if self.activeTrail == nil {
            self.activeTrail = self.savedTrails.first
        }
    }

    private func sanitizeTrail(_ trail: TrailDetail) -> TrailDetail {
        var t = trail
        if t.placeName.lowercased().contains("dhun") || t.placeId == "dhun-haveli" || t.placeId == "craft-quarter" {
            if t.placeName.contains("Craft") {
                t.placeName = "My Studio"
            } else {
                t.placeName = "My Trail"
            }
            if t.placeId == "dhun-haveli" || t.placeId == "craft-quarter" {
                t.placeId = "personal-trail"
            }
        }
        if t.locality.lowercased().contains("dhun") {
            t.locality = t.locality.replacingOccurrences(of: "Dhun, Jaipur", with: "Local Area")
                .replacingOccurrences(of: "Artisan Lane, Dhun", with: "Studio Lane")
                .replacingOccurrences(of: "Dhun", with: "Local")
        }
        if t.personalNotes == "Saved privately on this iPhone." || t.personalNotes.contains("Saved privately on this") {
            t.personalNotes = ""
        }
        if t.isPublished && t.visibility == .privateDraft {
            t.visibility = .publicPlace
        }

        // PRD v0.4.0: Automatically repair missing start frame or cover photos on disk
        if t.startFramePhotoName == nil {
            if let photo = packageStore.resolvedCoverOrFirstFrame(for: t.id)?.lastPathComponent ?? (t.sourceTrailId != nil ? packageStore.resolvedCoverOrFirstFrame(for: t.sourceTrailId!)?.lastPathComponent : nil) {
                t.startFramePhotoName = photo
            }
        }
        if t.coverImageName == nil {
            t.coverImageName = t.startFramePhotoName ?? packageStore.resolvedCoverOrFirstFrame(for: t.id)?.lastPathComponent
        }

        // Ensure Checkpoint 1 / Arrival inherits the starting reference frame photo if it has none
        if var firstMoment = t.moments.first, !firstMoment.hasPhoto && firstMoment.photoFileName == nil {
            if let startPhoto = t.startFramePhotoName ?? packageStore.resolvedCoverOrFirstFrame(for: t.id)?.lastPathComponent {
                firstMoment.photoFileName = startPhoto
                firstMoment.mediaType = "photo"
                t.moments[0] = firstMoment
            }
        }

        // If downloaded trail is missing footsteps, recover them from sourceTrailId if available
        if let srcId = t.sourceTrailId {
            packageStore.copyAssets(from: srcId, to: t.id)
            let existingSteps = packageStore.loadFootsteps(for: t.id)
            if existingSteps.isEmpty {
                let srcSteps = packageStore.loadFootsteps(for: srcId)
                if !srcSteps.isEmpty {
                    packageStore.saveTrailPackage(trail: t, footsteps: srcSteps)
                }
            }
        }

        return t
    }

    public func generatePlacesFromTrails(_ trails: [TrailDetail]) -> [Place] {
        var placesDict: [String: (name: String, locality: String, trails: [TrailDetail], lat: Double, lon: Double)] = [:]
        for trail in trails {
            let key = (trail.placeId.isEmpty || trail.placeId == "personal-trail")
                ? (trail.placeName.isEmpty ? "local-place" : trail.placeName.lowercased().replacingOccurrences(of: " ", with: "-"))
                : trail.placeId
            let name = trail.placeName.isEmpty ? "My Trails" : trail.placeName
            let locality = trail.locality.isEmpty ? "Local Area" : trail.locality
            let lat = trail.latitude ?? 0
            let lon = trail.longitude ?? 0

            if var existing = placesDict[key] {
                existing.trails.append(trail)
                if existing.lat == 0 && lat != 0 {
                    existing.lat = lat
                    existing.lon = lon
                }
                placesDict[key] = existing
            } else {
                placesDict[key] = (name: name, locality: locality, trails: [trail], lat: lat, lon: lon)
            }
        }

        return placesDict.values.map { val in
            Place(
                id: val.name.lowercased().replacingOccurrences(of: " ", with: "-"),
                name: val.name,
                tagline: "\(val.trails.count) recorded spatial \(val.trails.count == 1 ? "trail" : "trails")",
                surveyYear: "",
                district: val.locality,
                locality: val.locality,
                description: "Recorded journeys at \(val.name).",
                coverImageName: val.trails.first?.coverImageName,
                trailsCount: val.trails.count,
                contributorsCount: 1,
                latitude: val.lat,
                longitude: val.lon,
                category: .all,
                meshVersion: "LiDAR Route",
                floorLevels: [],
                authors: [],
                trails: val.trails.map { t in
                    TrailSummary(
                        id: t.id,
                        title: t.title,
                        subtitle: t.subtitle,
                        placeName: t.placeName,
                        authorName: t.authorName,
                        distanceMeters: t.distanceMeters,
                        momentsCount: t.moments.count,
                        floorCode: t.floorCode,
                        floorTitle: t.floorTitle,
                        coverImageName: t.coverImageName
                    )
                }
            )
        }
    }

    // MARK: - Filtered Queries (PRD §11.3 & v0.2.1 §7, §21, §26)

    public var allDisplayTrails: [TrailDetail] {
        return savedTrails
    }

    public var sampleMonograph: TrailDetail? {
        return sampleTrails.first
    }

    public var filteredTrails: [TrailDetail] {
        var results = allDisplayTrails

        // PRD v0.4.0 §14 Provenance Filter (All | Recorded by me | Downloaded)
        switch myTrailsFilter {
        case .all:
            break
        case .recordedByMe:
            results = results.filter { !$0.isDownloaded }
        case .downloaded:
            results = results.filter { $0.isDownloaded }
        }

        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let query = searchText.lowercased()
            results = results.filter {
                $0.title.lowercased().contains(query) ||
                $0.placeName.lowercased().contains(query) ||
                $0.locality.lowercased().contains(query)
            }
        }

        if let place = selectedPlaceFilter {
            results = results.filter { $0.placeName == place || $0.placeId == place }
        }

        if let year = selectedYearFilter {
            let calendar = Calendar.current
            results = results.filter {
                String(calendar.component(.year, from: $0.createdAt)) == year
            }
        }

        return results
    }

    public var availableYears: [String] {
        let calendar = Calendar.current
        let years = allDisplayTrails.map { String(calendar.component(.year, from: $0.createdAt)) }
        return Array(Set(years)).sorted(by: >)
    }

    public func clearFilters() {
        searchText = ""
        selectedYearFilter = nil
        selectedPlaceFilter = nil
    }

    public func startTrailAtPlace(_ place: Place) {
        self.targetPlaceForRecording = place
    }

    // MARK: - Persistence Actions

    public func saveDraft(trail: TrailDetail, footsteps: [SIMD3<Float>] = []) {
        var mutableTrail = trail
        mutableTrail.isDraft = true
        mutableTrail.updatedAt = Date()
        packageStore.saveTrailPackage(trail: mutableTrail, footsteps: footsteps)

        if let idx = userDrafts.firstIndex(where: { $0.id == trail.id }) {
            userDrafts[idx] = mutableTrail
        } else {
            userDrafts.insert(mutableTrail, at: 0)
        }
        self.activeTrail = mutableTrail
    }

    public func saveFinalTrail(trail: TrailDetail, footsteps: [SIMD3<Float>] = []) {
        var mutableTrail = trail
        mutableTrail.isDraft = false
        mutableTrail.updatedAt = Date()
        packageStore.saveTrailPackage(trail: mutableTrail, footsteps: footsteps)

        userDrafts.removeAll { $0.id == trail.id }

        if let idx = savedTrails.firstIndex(where: { $0.id == trail.id }) {
            savedTrails[idx] = mutableTrail
        } else {
            savedTrails.insert(mutableTrail, at: 0)
        }
        self.activeTrail = mutableTrail
        if packageStore.loadAllPlaces().filter({ $0.id != "dhun-haveli" && $0.id != "craft-quarter" && !$0.name.lowercased().contains("dhun") }).isEmpty {
            self.places = generatePlacesFromTrails(self.savedTrails)
        }
    }

    public func updateTrail(trail: TrailDetail) {
        var mutableTrail = trail
        mutableTrail.updatedAt = Date()
        packageStore.updateTrailMetadata(trail: mutableTrail)

        if mutableTrail.isDraft {
            if let idx = userDrafts.firstIndex(where: { $0.id == trail.id }) {
                userDrafts[idx] = mutableTrail
            }
        } else {
            if let idx = savedTrails.firstIndex(where: { $0.id == trail.id }) {
                savedTrails[idx] = mutableTrail
            }
        }
        if activeTrail?.id == trail.id {
            activeTrail = mutableTrail
        }
    }

    public func deleteTrail(id: String) {
        packageStore.deleteTrailPackage(id: id)
        userDrafts.removeAll { $0.id == id }
        savedTrails.removeAll { $0.id == id }
        if activeTrail?.id == id {
            activeTrail = savedTrails.first
        }
        if packageStore.loadAllPlaces().filter({ $0.id != "dhun-haveli" && $0.id != "craft-quarter" && !$0.name.lowercased().contains("dhun") }).isEmpty {
            self.places = generatePlacesFromTrails(self.savedTrails)
        }
    }

    public func updateProfile(displayName: String, introduction: String, username: String? = nil, avatarURL: String? = nil) {
        localProfile.displayName = displayName
        localProfile.introduction = introduction
        if let username {
            localProfile.username = username
        }
        if let avatarURL {
            localProfile.avatarURL = avatarURL
        }
        packageStore.saveLocalProfile(localProfile)
    }

    // MARK: - Initial Dataset

    private func loadInitialData() {
        self.sampleTrails = []
        self.places = []
        self.activeTrail = nil
    }
}
