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
        let diskTrails = packageStore.loadAllTrails()
        self.savedTrails = diskTrails.filter { !$0.isDraft }
        let diskDrafts = diskTrails.filter { $0.isDraft }
        if !diskDrafts.isEmpty {
            self.userDrafts = diskDrafts
        }

        let diskPlaces = packageStore.loadAllPlaces()
        if !diskPlaces.isEmpty {
            self.places = diskPlaces
        }
    }

    // MARK: - Filtered Queries (PRD §11.3)

    public var allDisplayTrails: [TrailDetail] {
        return savedTrails + sampleTrails
    }

    public var filteredTrails: [TrailDetail] {
        var results = allDisplayTrails

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
            activeTrail = savedTrails.first ?? sampleTrails.first
        }
    }

    public func updateProfile(displayName: String, introduction: String) {
        localProfile.displayName = displayName
        localProfile.introduction = introduction
        packageStore.saveLocalProfile(localProfile)
    }

    // MARK: - Initial Monograph Dataset (PRD §1 & docs/stitch/v0.2.0)

    private func loadInitialData() {
        let moment1 = SpatialMoment(
            id: "m1",
            index: 1,
            title: "Entrance Threshold",
            subtitle: "Look for the iron pivot hinge",
            narrative: "Cross the massive threshold beam. Look down at the carved threshold stone worn concave by generations of footsteps.",
            architecturalNote: "Iron strap-hinge anchors from the late 19th century.",
            distanceAlongPathMeters: 4,
            relativeElevation: "+0.00m",
            hasAudio: false,
            hasPhoto: true,
            mediaType: "photo",
            photoAssetName: "SandstoneArchway",
            positionX: 0.18,
            positionY: 0.65
        )

        let moment2 = SpatialMoment(
            id: "m2",
            index: 2,
            title: "The Light Well Lintels",
            subtitle: "Echo of footsteps here is softer",
            narrative: "Stand directly under the east archway. Notice how the hand-chiseled lintels taper upward to draw smoke and hot air toward the open court.",
            architecturalNote: "Late 18th-century craft detail, undamaged corner joinery.",
            distanceAlongPathMeters: 18,
            relativeElevation: "+0.00m",
            audioDuration: "0:42",
            hasAudio: true,
            hasPhoto: false,
            mediaType: "voice",
            positionX: 0.42,
            positionY: 0.48
        )

        let moment3 = SpatialMoment(
            id: "m3",
            index: 3,
            title: "Worn Sandstone Steps",
            subtitle: "Take your shoes off if you like",
            narrative: "The step risers narrow as you approach the mezzanine transition. Notice the temperature drop as air rises from the basement channels.",
            architecturalNote: "Red sandstone blocks dry-stacked with lime-mortar skim.",
            distanceAlongPathMeters: 55,
            relativeElevation: "+1.20m",
            hasAudio: false,
            hasPhoto: false,
            mediaType: "note",
            positionX: 0.62,
            positionY: 0.35
        )

        let moment4 = SpatialMoment(
            id: "m4",
            index: 4,
            title: "Courtyard Cistern Breeze",
            subtitle: "Cold draft from the sub-floor ducts",
            narrative: "A subtle cooling cross-current washes across this recessed alcove, drawn up from the subterranean rainwater cistern below.",
            architecturalNote: "Sub-floor thermal convection flue connected to north light shaft.",
            distanceAlongPathMeters: 92,
            relativeElevation: "+1.80m",
            audioDuration: "1:15",
            hasAudio: true,
            hasPhoto: true,
            mediaType: "photo",
            photoAssetName: "DhunHaveliEvening",
            positionX: 0.78,
            positionY: 0.22
        )

        let heroTrail = TrailDetail(
            id: "evening-through-haveli",
            title: "An evening through the Haveli",
            subtitle: "Worn sandstone lintels & passive evening drafts",
            placeId: "dhun-haveli",
            placeName: "Dhun Haveli",
            locality: "Dhun, Jaipur",
            wing: "Ground Floor, Courtyard wing",
            authorName: "Hiro",
            authorRole: "Architect & Spatial Explorer",
            distanceMeters: 140,
            floorCode: "LVL 00",
            floorTitle: "Ground Floor",
            meshDensity: "LiDAR Mesh v2",
            samplingFrequency: "24.6 kHz",
            nodeCount: 4,
            personalNotes: "Recorded at twilight while stone floors retained warmth. Follow the path along the water drainage channels towards the eastern light shaft.",
            moments: [moment1, moment2, moment3, moment4],
            visibility: .privateDraft,
            isDraft: false,
            coverImageName: "DhunHaveliEvening",
            latitude: 26.9124,
            longitude: 75.7873
        )

        let stepwellTrail = TrailDetail(
            id: "stepwell-descent",
            title: "The Stepwell Descent",
            subtitle: "Water basin cisterns & subterranean acoustic dampening",
            placeId: "dhun-haveli",
            placeName: "Dhun South",
            locality: "Dhun, Jaipur",
            wing: "Basement Incline",
            authorName: "Hiro",
            authorRole: "Architect",
            distanceMeters: 85,
            floorCode: "LVL -01",
            floorTitle: "Basement Cistern",
            meshDensity: "LiDAR Mesh v2",
            samplingFrequency: "24.6 kHz",
            nodeCount: 3,
            personalNotes: "Descending past the cold intake ducts. Notice the abrupt 4-degree temperature shift.",
            moments: [moment1, moment3, moment4],
            visibility: .privateDraft,
            isDraft: false,
            coverImageName: "SandstoneArchway",
            latitude: 26.9118,
            longitude: 75.7865
        )

        let terraceTrail = TrailDetail(
            id: "upper-terrace-dawn",
            title: "Upper Terrace at Dawn",
            subtitle: "Solar geometer alignments across roof overlook",
            placeId: "dhun-haveli",
            placeName: "Haveli Level 2",
            locality: "Dhun, Jaipur",
            wing: "Roof Terrace",
            authorName: "Hiro",
            authorRole: "Solar Geometer",
            distanceMeters: 110,
            floorCode: "LVL 02",
            floorTitle: "Roof Overlook",
            meshDensity: "LiDAR Mesh v1",
            samplingFrequency: "24.6 kHz",
            nodeCount: 5,
            personalNotes: "First morning sunlight hitting the eastern sandstone battlements.",
            moments: [moment2, moment3, moment4],
            visibility: .privateDraft,
            isDraft: false,
            coverImageName: "DhunHaveliEvening",
            latitude: 26.9126,
            longitude: 75.7876,
            inspiredByTrailId: "evening-through-haveli",
            inspiredByNote: "Vertical solar counterpart to Hiro's evening haveli walk."
        )

        let workshopTrail = TrailDetail(
            id: "carpenters-lane",
            title: "Carpenters' Lane Workshop",
            subtitle: "Teak joinery & cedar scent cross-ventilation",
            placeId: "craft-quarter",
            placeName: "Dhun Craft Quarter",
            locality: "Artisan Lane, Dhun",
            wing: "Workshop 02",
            authorName: "Hiro",
            authorRole: "Craft Researcher",
            distanceMeters: 62,
            floorCode: "LVL 00",
            floorTitle: "Timber Yard",
            meshDensity: "LiDAR Mesh v1",
            samplingFrequency: "24.6 kHz",
            nodeCount: 2,
            personalNotes: "Hand-tool racks and mortise-tenon samples arranged along north light.",
            moments: [moment1, moment2],
            visibility: .privateDraft,
            isDraft: false,
            coverImageName: "SandstoneArchway",
            latitude: 26.9142,
            longitude: 75.7891
        )

        self.sampleTrails = [heroTrail, stepwellTrail, terraceTrail, workshopTrail]
        self.activeTrail = heroTrail

        let dhunHaveli = Place(
            id: "dhun-haveli",
            name: "Dhun Haveli",
            tagline: "“A place, through its people.”",
            surveyYear: "Surv. 1884",
            district: "Jaipur / Dhun district",
            locality: "Dhun, Jaipur",
            description: "A 19th-century courtyard dwelling oriented around passive ventilation and shared light wells. Authors have traced movements from morning light to evening gathering.",
            coverImageName: "DhunHaveliEvening",
            trailsCount: 4,
            contributorsCount: 3,
            latitude: 26.9124,
            longitude: 75.7873,
            category: .courtyards,
            meshVersion: "LiDAR Mesh v2",
            floorLevels: [
                FloorLevel(id: "lvl-00", shortCode: "LVL 00", name: "Ground floor", elevationOffset: "+0.00m"),
                FloorLevel(id: "lvl-01", shortCode: "LVL 01", name: "Mezzanine", elevationOffset: "+3.20m"),
                FloorLevel(id: "lvl-02", shortCode: "LVL 02", name: "Upper terrace", elevationOffset: "+6.80m")
            ],
            authors: [
                PlaceAuthor(id: "a1", name: "Hiro", focusArea: "Courtyard & Light", role: "Architect & Spatial Explorer")
            ],
            trails: [
                TrailSummary(
                    id: "evening-through-haveli",
                    title: "An evening through the Haveli",
                    subtitle: "Worn sandstone lintels & passive evening drafts",
                    placeName: "Dhun Haveli",
                    authorName: "Hiro",
                    distanceMeters: 140,
                    momentsCount: 4,
                    floorCode: "LVL 00",
                    floorTitle: "Ground Floor",
                    coverImageName: "DhunHaveliEvening"
                ),
                TrailSummary(
                    id: "upper-terrace-dawn",
                    title: "Upper Terrace at Dawn",
                    subtitle: "Solar geometer alignments across roof overlook",
                    placeName: "Dhun Haveli",
                    authorName: "Hiro",
                    distanceMeters: 110,
                    momentsCount: 5,
                    floorCode: "LVL 02",
                    floorTitle: "Roof Overlook",
                    coverImageName: "DhunHaveliEvening"
                )
            ]
        )

        let craftQuarter = Place(
            id: "craft-quarter",
            name: "Dhun Craft Quarter",
            tagline: "Historic artisan lanes & joinery sheds",
            surveyYear: "Surv. 1912",
            district: "Dhun Artisan Lane",
            locality: "Artisan Lane, Dhun",
            description: "Woodblock print archives, timber dry-racks, and hand-chiseled masonry shops situated along cool shaded alleys.",
            coverImageName: "SandstoneArchway",
            trailsCount: 2,
            contributorsCount: 2,
            latitude: 26.9142,
            longitude: 75.7891,
            category: .studios,
            meshVersion: "LiDAR Mesh v1",
            floorLevels: [
                FloorLevel(id: "cq-00", shortCode: "LVL 00", name: "Alley Level")
            ],
            authors: [
                PlaceAuthor(id: "a2", name: "Hiro", focusArea: "Timber Yard", role: "Craft Researcher")
            ],
            trails: [
                TrailSummary(
                    id: "carpenters-lane",
                    title: "Carpenters' Lane Workshop",
                    subtitle: "Teak joinery & cedar scent cross-ventilation",
                    placeName: "Dhun Craft Quarter",
                    authorName: "Hiro",
                    distanceMeters: 62,
                    momentsCount: 2,
                    coverImageName: "SandstoneArchway"
                )
            ]
        )

        let steppedPavilion = Place(
            id: "stepped-pavilion",
            name: "Stepped Pavilion",
            tagline: "Water-facing public pavilion",
            surveyYear: "Surv. 1820",
            district: "East Cistern Bank",
            locality: "Reservoir Bank, Jaipur",
            description: "Tiered sandstone steps descending to the seasonal reservoir with carved stone brackets.",
            coverImageName: "DhunHaveliEvening",
            trailsCount: 1,
            contributorsCount: 1,
            latitude: 26.9160,
            longitude: 75.7845,
            category: .pavilions,
            meshVersion: "LiDAR Mesh v2",
            floorLevels: [
                FloorLevel(id: "sp-00", shortCode: "LVL 00", name: "Water Margin")
            ],
            authors: [],
            trails: []
        )

        self.places = [dhunHaveli, craftQuarter, steppedPavilion]
        self.selectedPlace = dhunHaveli
    }
}
