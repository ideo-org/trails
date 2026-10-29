//
//  TrailsDataStore.swift
//  Trails
//
//  Data store providing mock and user-generated data for places and spatial trails,
//  aligned with the Dhun Architectural Quarter design monograph.
//

import Foundation
import Combine

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
    }

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

        // Remove from drafts if present
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
            positionX: 0.18,
            positionY: 0.65
        )

        let moment2 = SpatialMoment(
            id: "m2",
            index: 2,
            title: "The Light Well Lintels",
            subtitle: "Echo of footsteps here is softer",
            narrative: "Stand directly under the east archway. Look up before you walk through—notice how the hand-chiseled lintels taper upward to draw smoke and hot air toward the open court.",
            architecturalNote: "Late 18th-century craft detail, undamaged corner joinery.",
            distanceAlongPathMeters: 18,
            relativeElevation: "+0.00m",
            audioDuration: "0:42",
            hasAudio: true,
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
            positionX: 0.62,
            positionY: 0.35
        )

        let moment4 = SpatialMoment(
            id: "m4",
            index: 4,
            title: "Rear Alcove Breeze",
            subtitle: "Cold draft from the sub-floor ducts",
            narrative: "A subtle cooling cross-current washes across this recessed alcove, drawn up from the subterranean rainwater cistern below.",
            architecturalNote: "Sub-floor thermal convection flue connected to north light shaft.",
            distanceAlongPathMeters: 92,
            relativeElevation: "+1.80m",
            audioDuration: "1:15",
            hasAudio: true,
            positionX: 0.78,
            positionY: 0.22
        )

        let throughTheCourtyard = TrailDetail(
            id: "through-the-courtyard",
            title: "Through the Courtyard",
            subtitle: "Morning light & ventilation paths",
            placeId: "dhun-haveli",
            placeName: "Dhun Haveli",
            wing: "Ground Floor, Courtyard wing",
            authorName: "Hiro",
            authorRole: "Architect & Spatial Explorer",
            distanceMeters: 140,
            floorCode: "LVL 00",
            floorTitle: "Ground Floor",
            meshDensity: "98% density",
            samplingFrequency: "24.6 kHz",
            nodeCount: 4,
            personalNotes: "Recorded early morning while the stone was still cool. Follow the path along the water drainage channels towards the eastern light shaft.",
            moments: [moment1, moment2, moment3, moment4],
            visibility: .publicPlace,
            isDraft: false
        )

        let draftTrail = TrailDetail(
            id: "draft-courtyard",
            title: "Through the Courtyard",
            subtitle: "Morning light & ventilation paths",
            placeId: "dhun-haveli",
            placeName: "Dhun Haveli",
            wing: "Ground Floor, Courtyard wing",
            authorName: "Hiro",
            authorRole: "Architect & Spatial Explorer",
            distanceMeters: 140,
            floorCode: "LVL 00",
            floorTitle: "Ground Floor",
            meshDensity: "98% density",
            samplingFrequency: "24.6 kHz",
            nodeCount: 4,
            personalNotes: "Recorded early morning while the stone was still cool. Follow the path along the water drainage toward the central cistern.",
            moments: [moment1, moment2, moment3, moment4],
            visibility: .privateDraft,
            isDraft: true
        )

        self.sampleTrails = [throughTheCourtyard]
        self.userDrafts = [draftTrail]
        self.activeTrail = throughTheCourtyard

        let dhunHaveli = Place(
            id: "dhun-haveli",
            name: "Dhun Haveli",
            tagline: "“A place, through its people.”",
            surveyYear: "Surv. 1884",
            district: "Jaipur / Dhun district",
            description: "A 19th-century courtyard dwelling oriented around passive ventilation and shared light wells. Authors have traced movements from morning light to evening gathering.",
            trailsCount: 8,
            contributorsCount: 6,
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
                PlaceAuthor(id: "a1", name: "Hiro", focusArea: "Courtyard", role: "Architect & Spatial Explorer"),
                PlaceAuthor(id: "a2", name: "Maya", focusArea: "Acoustics", role: "Sound Artist"),
                PlaceAuthor(id: "a3", name: "Kael", focusArea: "Shadows", role: "Solar Geometer"),
                PlaceAuthor(id: "a4", name: "Sarah", focusArea: "Terrace", role: "Historian")
            ],
            trails: [
                TrailSummary(
                    id: "through-the-courtyard",
                    title: "Through the Courtyard",
                    subtitle: "Morning light & ventilation paths",
                    placeName: "Dhun Haveli",
                    authorName: "Hiro",
                    distanceMeters: 140,
                    momentsCount: 4,
                    floorCode: "LVL 00",
                    floorTitle: "Ground Floor"
                ),
                TrailSummary(
                    id: "upper-jharokha",
                    title: "Upper Jharokha Breezeway",
                    subtitle: "Wind-catcher balconies & roof overlook",
                    placeName: "Dhun Haveli",
                    authorName: "Maya",
                    distanceMeters: 95,
                    momentsCount: 3,
                    floorCode: "LVL 01",
                    floorTitle: "Mezzanine"
                ),
                TrailSummary(
                    id: "water-channels",
                    title: "Water Channels & Basements",
                    subtitle: "Subterranean cistern acoustics",
                    placeName: "Dhun Haveli",
                    authorName: "Kael",
                    distanceMeters: 210,
                    momentsCount: 6,
                    floorCode: "LVL 00",
                    floorTitle: "Ground Floor"
                )
            ]
        )

        let printWorkshop = Place(
            id: "print-workshop",
            name: "Print Workshop",
            tagline: "Historic press room & bindery",
            surveyYear: "Surv. 1912",
            district: "Dhun Artisan Lane",
            description: "Woodblock print archives and drying racks situated around north-facing clerestory glazing.",
            trailsCount: 5,
            contributorsCount: 4,
            latitude: 26.9142,
            longitude: 75.7891,
            category: .studios,
            meshVersion: "LiDAR Mesh v1",
            floorLevels: [
                FloorLevel(id: "pw-00", shortCode: "LVL 00", name: "Press Floor")
            ],
            authors: [
                PlaceAuthor(id: "pw-a1", name: "Arjun", focusArea: "Press Room", role: "Master Printer")
            ],
            trails: [
                TrailSummary(
                    id: "pw-trail-1",
                    title: "The Drying Loft Walk",
                    subtitle: "Clerestory cross breeze & paper scent",
                    placeName: "Print Workshop",
                    authorName: "Arjun",
                    distanceMeters: 80,
                    momentsCount: 3
                )
            ]
        )

        let steppedPavilion = Place(
            id: "stepped-pavilion",
            name: "Stepped Pavilion",
            tagline: "Water-facing public pavilion",
            surveyYear: "Surv. 1820",
            district: "East Cistern Bank",
            description: "Tiered sandstone steps descending to the seasonal reservoir with carved stone brackets.",
            trailsCount: 3,
            contributorsCount: 3,
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

        let neemCourtyard = Place(
            id: "neem-courtyard",
            name: "Neem Courtyard",
            tagline: "Canopied community shade ring",
            surveyYear: "Surv. 1940",
            district: "South Quarter",
            description: "Centuries-old Neem tree ring surrounded by perimeter clay brick benches.",
            trailsCount: 2,
            contributorsCount: 2,
            latitude: 26.9100,
            longitude: 75.7860,
            category: .courtyards,
            meshVersion: "LiDAR Mesh v1",
            floorLevels: [
                FloorLevel(id: "nc-00", shortCode: "LVL 00", name: "Canopy Level")
            ],
            authors: [],
            trails: []
        )

        self.places = [dhunHaveli, printWorkshop, steppedPavilion, neemCourtyard]
        self.selectedPlace = dhunHaveli
    }
}
