//
//  DiscoverViewModel.swift
//  Trails
//
//  Shared discovery query state and coordinator for PRD v0.4.0 §5, §6, §7, §8, §18, §19, §20.
//  Maintains unified DiscoveryState across Journal and Map modes.
//

import Foundation
import Combine
import CoreLocation

public struct DiscoveryState: Equatable {
    public var presentationMode: CollectionMode = .journal
    public var areaFilter: DiscoveryAreaFilter = .all
    public var selectedCreator: CreatorRecord? = nil
    public var bookmarkedOnly: Bool = false
    public var includeTestTrails: Bool = false
    public var query: String = ""
    public var sort: DiscoverySort = .recentlyPublished
    public var selectedTrailId: String? = nil
}

public enum SearchResultItem: Identifiable, Hashable {
    case trail(DiscoveryRecord)
    case creator(CreatorRecord)
    case place(Place)

    public var id: String {
        switch self {
        case .trail(let t): return "trail-\(t.trailId)"
        case .creator(let c): return "creator-\(c.creatorId)"
        case .place(let p): return "place-\(p.id)"
        }
    }
}

@MainActor
public final class DiscoverViewModel: ObservableObject {
    @Published public var state: DiscoveryState = DiscoveryState()
    @Published public private(set) var records: [DiscoveryRecord] = []
    @Published public private(set) var creators: [CreatorRecord] = []
    @Published public private(set) var availablePlaces: [Place] = []
    @Published public private(set) var searchResults: [SearchResultItem] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var isSearching: Bool = false

    private static let includeTestTrailsKey = "trails_discover_include_test_trails"
    private let client = TrailsLogosClient.shared
    private let bookmarksStore = BookmarksStore.shared
    private let locationManager = TrailsLocationManager.shared
    private var cancellables = Set<AnyCancellable>()

    public init() {
        self.state.includeTestTrails = UserDefaults.standard.bool(forKey: Self.includeTestTrailsKey)
        self.availablePlaces = TrailsDataStore.shared.places

        // React to bookmark changes
        bookmarksStore.$bookmarkedIds
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        Task {
            await reload()
        }
    }

    // MARK: - Query & Filter Execution (PRD §5, §6, §7, §8)

    public func reload() async {
        self.isLoading = true
        self.errorMessage = nil

        do {
            // Load creators
            let fetchedCreators = try await client.fetchCreators()
            self.creators = fetchedCreators

            // Fetch discovery records matching current area and creator filters
            let area = state.areaFilter
            let creatorId = state.selectedCreator?.creatorId
            let query = state.query.trimmingCharacters(in: .whitespaces).isEmpty ? nil : state.query

            let fetched = try await client.fetchDiscoveryRecords(
                area: area,
                creatorId: creatorId,
                query: query
            )
            self.records = fetched
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
            // Fall back to locally bookmarked records if offline (PRD §20)
            if self.records.isEmpty {
                self.records = Array(bookmarksStore.bookmarkedRecords.values)
            }
        }
    }

    // MARK: - Test & Dummy Trails Filter Logic

    public static func isTestRecord(_ record: DiscoveryRecord) -> Bool {
        let u = record.username.lowercased()
        let c = record.creatorId.lowercased()
        let t = record.trailId.lowercased()
        let title = record.title.lowercased()
        return u.hasPrefix("test-") || u.hasPrefix("test_") ||
               c.hasPrefix("test-") || c.hasPrefix("test_") || c.contains("-test-") ||
               t.hasPrefix("test-") || t.hasPrefix("test_") ||
               title.contains("(sample)") || title.contains("(test)") ||
               u == "soundcraft" || u == "hiro" || u == "mira" ||
               t == "acoustic-resonance-study" || t == "mission-peak-ridge" || t == "dhun-haveli-courtyard"
    }

    public static func isTestCreator(_ creator: CreatorRecord) -> Bool {
        let u = creator.username.lowercased()
        let c = creator.creatorId.lowercased()
        let d = creator.displayName.lowercased()
        return u.hasPrefix("test-") || u.hasPrefix("test_") ||
               c.hasPrefix("test-") || c.hasPrefix("test_") || c.contains("-test-") ||
               d.contains("(test)") || d.contains("(sample)") ||
               u == "soundcraft" || u == "hiro" || u == "mira"
    }

    public var displayedCreators: [CreatorRecord] {
        if state.includeTestTrails {
            return creators
        }
        return creators.filter { !Self.isTestCreator($0) }
    }

    // MARK: - Filtered Records Display (Unified for Journal and Map)

    public var displayedRecords: [DiscoveryRecord] {
        var items = records

        // Filter out dummy/test trails unless user explicitly toggles includeTestTrails
        if !state.includeTestTrails {
            items = items.filter { !Self.isTestRecord($0) }
        }

        // Apply Bookmarked filter (PRD §11)
        if state.bookmarkedOnly {
            items = items.filter { bookmarksStore.isBookmarked(trailId: $0.trailId) }
        }

        // Apply sort
        switch state.sort {
        case .recentlyPublished:
            items.sort { $0.publishedAt > $1.publishedAt }
        case .nearest:
            if let userLoc = locationManager.lastKnownLocation {
                items.sort { a, b in
                    guard let aAnchor = a.discoveryAnchor else { return false }
                    guard let bAnchor = b.discoveryAnchor else { return true }
                    let distA = userLoc.distance(from: CLLocation(latitude: aAnchor.latitude, longitude: aAnchor.longitude))
                    let distB = userLoc.distance(from: CLLocation(latitude: bAnchor.latitude, longitude: bAnchor.longitude))
                    return distA < distB
                }
            } else {
                items.sort { $0.publishedAt > $1.publishedAt }
            }
        }

        return items
    }

    // Records that possess discovery anchors (suitable for Map rendering - PRD §6 & §10)
    public var locatedRecords: [DiscoveryRecord] {
        displayedRecords.filter { $0.discoveryAnchor != nil }
    }

    // Records without anchors (PRD §6: Trails without an anchor)
    public var unlocatedRecords: [DiscoveryRecord] {
        displayedRecords.filter { $0.discoveryAnchor == nil }
    }

    // MARK: - Filter Modification Actions

    public func setIncludeTestTrails(_ include: Bool) {
        state.includeTestTrails = include
        UserDefaults.standard.set(include, forKey: Self.includeTestTrailsKey)
        objectWillChange.send()
    }

    public func toggleIncludeTestTrails() {
        setIncludeTestTrails(!state.includeTestTrails)
    }

    public func setAreaFilter(_ filter: DiscoveryAreaFilter) {
        state.areaFilter = filter
        Task { await reload() }
    }

    public func setCreatorFilter(_ creator: CreatorRecord?) {
        state.selectedCreator = creator
        Task { await reload() }
    }

    public func toggleBookmarkedOnly() {
        state.bookmarkedOnly.toggle()
    }

    public func showAllTrailsByCurrentCreator() {
        // PRD §7: Provide "Show all trails by @creator" — removes area restriction while retaining creator
        state.areaFilter = .all
        Task { await reload() }
    }

    public func clearFilters() {
        state.areaFilter = .all
        state.selectedCreator = nil
        state.bookmarkedOnly = false
        state.query = ""
        Task { await reload() }
    }

    // MARK: - Search Autocomplete & Selection (PRD §8)

    public func updateSearchQuery(_ text: String) {
        state.query = text
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else {
            searchResults = []
            Task { await reload() }
            return
        }

        // Categorize into Trails, Creators, Places (PRD §8)
        var results: [SearchResultItem] = []

        // Trails (honors test trails toggle)
        let matchingTrails = displayedRecords.filter {
            $0.title.lowercased().contains(trimmed) ||
            ($0.placeLabel?.lowercased().contains(trimmed) ?? false)
        }
        for t in matchingTrails.prefix(3) {
            results.append(.trail(t))
        }

        // Creators (honors test trails toggle)
        let matchingCreators = displayedCreators.filter {
            $0.username.lowercased().contains(trimmed) ||
            $0.displayName.lowercased().contains(trimmed)
        }
        for c in matchingCreators.prefix(2) {
            results.append(.creator(c))
        }

        // Places
        let matchingPlaces = availablePlaces.filter {
            $0.name.lowercased().contains(trimmed) ||
            $0.locality.lowercased().contains(trimmed)
        }
        for p in matchingPlaces.prefix(2) {
            results.append(.place(p))
        }

        self.searchResults = results
        Task { await reload() }
    }

    public func selectSearchResult(_ item: SearchResultItem) {
        switch item {
        case .trail(let t):
            // Selecting trail opens detail
            state.selectedTrailId = t.trailId
            state.query = ""
            searchResults = []
        case .creator(let c):
            // Selecting creator applies its filter
            setCreatorFilter(c)
            state.query = ""
            searchResults = []
        case .place(let p):
            // Selecting place sets geographic context
            setAreaFilter(.chosenPlace(p))
            state.query = ""
            searchResults = []
        }
    }
}
