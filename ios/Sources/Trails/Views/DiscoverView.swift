//
//  DiscoverView.swift
//  Trails
//
//  Primary Community Discovery screen compliant with PRD v0.4.0 §3, §5, §6, §7, §8, §9, §10, §19, §20.
//  Unified browsing in Journal and Map mode sharing DiscoveryState.
//

import SwiftUI
import MapKit

public struct DiscoverView: View {
    @StateObject private var viewModel = DiscoverViewModel()
    @ObservedObject private var bookmarksStore = BookmarksStore.shared
    @ObservedObject private var downloadManager = TrailDownloadManager.shared

    @State private var showingAreaFilterSheet: Bool = false
    @State private var showingCreatorFilterSheet: Bool = false
    @State private var selectedRecordForDetail: DiscoveryRecord? = nil
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var selectedRecordOnMap: DiscoveryRecord? = nil

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppColors.canvas
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Shared Header (PRD §5)
                    headerView

                    // Active Filters Summary Bar (PRD §5 & §7)
                    if hasActiveFilters {
                        activeFiltersBar
                    }

                    // Content Viewport: Journal vs Map mode (PRD §5)
                    if viewModel.state.presentationMode == .journal {
                        journalScrollView
                    } else {
                        mapContentView
                    }
                }

                // Bookmark Toast Notification (PRD §11)
                if let toast = bookmarksStore.toastMessage {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "bookmark.fill")
                                .foregroundColor(AppColors.terracotta)
                            Text(toast)
                                .font(AppFonts.labelUI)
                                .foregroundColor(AppColors.deepInk)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(AppColors.surfaceContainerLow)
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
                        .padding(.bottom, 24)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.3), value: toast)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingAreaFilterSheet) {
                areaFilterSelectionSheet
            }
            .sheet(isPresented: $showingCreatorFilterSheet) {
                creatorFilterSelectionSheet
            }
            .sheet(item: $selectedRecordForDetail) { record in
                PublicTrailDetailView(record: record)
            }
            .onChange(of: viewModel.state.selectedTrailId) { _, trailId in
                if let trailId, let found = viewModel.records.first(where: { $0.trailId == trailId }) {
                    selectedRecordForDetail = found
                    viewModel.state.selectedTrailId = nil
                }
            }
        }
    }

    // MARK: - Header Bar (PRD §5)

    private var headerView: some View {
        VStack(spacing: 12) {
            // Top Title Bar
            HStack {
                HStack(spacing: 10) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                        .shadow(color: AppColors.primary.opacity(0.12), radius: 4, x: 0, y: 2)

                    Text("Discover")
                        .font(AppFonts.headlineMedium)
                        .foregroundColor(AppColors.primary)
                }

                Spacer()

                // Refresh Button
                Button {
                    Haptics.selection()
                    Task { await viewModel.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16))
                        .foregroundColor(AppColors.onSurfaceVariant)
                        .frame(width: 36, height: 36)
                        .background(AppColors.surfaceContainerLow)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Search Bar (PRD §5 & §8)
            searchBarWithAutocomplete

            // Mode Picker [ Journal | Map ] (PRD §5: Distinct clean row matching My Trails)
            segmentedModePicker

            // Filter Pills Bar (Equal prominence - PRD §5: [Area] [Creator] [Saved])
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Area Filter Pill (PRD §5 & §6)
                    Button {
                        Haptics.selection()
                        showingAreaFilterSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 11))
                            Text(viewModel.state.areaFilter.title)
                                .font(AppFonts.labelSpatial)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(viewModel.state.areaFilter != .all ? AppColors.primary : AppColors.surfaceContainerHigh)
                        .foregroundColor(viewModel.state.areaFilter != .all ? AppColors.onPrimary : AppColors.deepInk)
                        .clipShape(Capsule())
                    }

                    // Creator Filter Pill (PRD §5 & §7)
                    Button {
                        Haptics.selection()
                        showingCreatorFilterSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 11))
                            Text(viewModel.state.selectedCreator != nil ? "@\(viewModel.state.selectedCreator!.username)" : "Creator")
                                .font(AppFonts.labelSpatial)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(viewModel.state.selectedCreator != nil ? AppColors.primary : AppColors.surfaceContainerHigh)
                        .foregroundColor(viewModel.state.selectedCreator != nil ? AppColors.onPrimary : AppColors.deepInk)
                        .clipShape(Capsule())
                    }

                    // Saved Filter Pill (PRD §5 & §11)
                    Button {
                        Haptics.selection()
                        viewModel.toggleBookmarkedOnly()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.state.bookmarkedOnly ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 11))
                            Text("Saved")
                                .font(AppFonts.labelSpatial)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(viewModel.state.bookmarkedOnly ? AppColors.terracotta : AppColors.surfaceContainerHigh)
                        .foregroundColor(viewModel.state.bookmarkedOnly ? .white : AppColors.deepInk)
                        .clipShape(Capsule())
                    }

                    if hasActiveFilters {
                        Button {
                            Haptics.selection()
                            viewModel.clearFilters()
                        } label: {
                            Text("Reset")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.outline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(AppColors.surfaceContainerLow)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 6)
        }
        .background(AppColors.canvas.opacity(0.96))
    }


    // MARK: - Search Bar with Autocomplete Dropdown (PRD §8)

    private var searchBarWithAutocomplete: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.outline)
                    .font(.system(size: 15))

                TextField("Search trails, places, or creators...", text: Binding(
                    get: { viewModel.state.query },
                    set: { viewModel.updateSearchQuery($0) }
                ))
                .font(AppFonts.bodyMedium)
                .foregroundColor(AppColors.deepInk)

                if !viewModel.state.query.isEmpty {
                    Button {
                        viewModel.updateSearchQuery("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.outline)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppColors.surfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)

            // Autocomplete results overlay (PRD §8: Trails, Creators, Places distinction)
            if !viewModel.searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.searchResults) { item in
                        Button {
                            Haptics.selection()
                            viewModel.selectSearchResult(item)
                        } label: {
                            HStack(spacing: 10) {
                                switch item {
                                case .trail(let t):
                                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                        .foregroundColor(AppColors.primary)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(t.title)
                                            .font(AppFonts.bodySmall)
                                            .foregroundColor(AppColors.deepInk)
                                        Text("Trail · by @\(t.username)")
                                            .font(AppFonts.caption)
                                            .foregroundColor(AppColors.outline)
                                    }
                                case .creator(let c):
                                    Image(systemName: "person.circle.fill")
                                        .foregroundColor(AppColors.secondary)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("@\(c.username)")
                                            .font(AppFonts.bodySmall)
                                            .foregroundColor(AppColors.deepInk)
                                        Text("Creator · \(c.trailCount) published trails")
                                            .font(AppFonts.caption)
                                            .foregroundColor(AppColors.outline)
                                    }
                                case .place(let p):
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundColor(AppColors.terracotta)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(p.name)
                                            .font(AppFonts.bodySmall)
                                            .foregroundColor(AppColors.deepInk)
                                        Text("Place · \(p.locality)")
                                            .font(AppFonts.caption)
                                            .foregroundColor(AppColors.outline)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        Divider()
                    }
                }
                .background(AppColors.pureWhite)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Segmented Mode Picker [ Journal | Map ]

    private var segmentedModePicker: some View {
        HStack {
            Spacer()
            HStack(spacing: 4) {
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        viewModel.state.presentationMode = .journal
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Journal")
                            .font(AppFonts.labelUI)
                            .foregroundColor(viewModel.state.presentationMode == .journal ? AppColors.onPrimary : AppColors.onSurfaceVariant)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(viewModel.state.presentationMode == .journal ? AppColors.primary : Color.clear)
                    .clipShape(Capsule())
                }

                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        viewModel.state.presentationMode = .map
                    }
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.state.presentationMode == .map {
                            Circle()
                                .fill(AppColors.secondary)
                                .frame(width: 6, height: 6)
                        }
                        Text("Map")
                            .font(AppFonts.labelUI)
                            .foregroundColor(viewModel.state.presentationMode == .map ? AppColors.onPrimary : AppColors.onSurfaceVariant)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(viewModel.state.presentationMode == .map ? AppColors.primary : Color.clear)
                    .clipShape(Capsule())
                }
            }
            .padding(4)
            .background(AppColors.surfaceContainer)
            .clipShape(Capsule())
            Spacer()
        }
    }

    // MARK: - Active Filters Bar (PRD §5 & §7)

    private var hasActiveFilters: Bool {
        viewModel.state.areaFilter != .all ||
        viewModel.state.selectedCreator != nil ||
        viewModel.state.bookmarkedOnly
    }

    private var activeFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Area Active Filter Chip
                if viewModel.state.areaFilter != .all {
                    activeFilterChip(label: viewModel.state.areaFilter.title) {
                        viewModel.setAreaFilter(.all)
                    }
                }

                // Creator Active Filter Chip
                if let creator = viewModel.state.selectedCreator {
                    activeFilterChip(label: "@\(creator.username)") {
                        viewModel.setCreatorFilter(nil)
                    }

                    // PRD §7: If creator is filtered and area is also constrained, provide:
                    // "Show all trails by @creator"
                    if viewModel.state.areaFilter != .all {
                        Button {
                            Haptics.selection()
                            viewModel.showAllTrailsByCurrentCreator()
                        } label: {
                            Text("Show all trails by @\(creator.username)")
                                .font(AppFonts.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(AppColors.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AppColors.primary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }

                // Saved Chip
                if viewModel.state.bookmarkedOnly {
                    activeFilterChip(label: "Saved") {
                        viewModel.toggleBookmarkedOnly()
                    }
                }

                // Clear all
                Button {
                    Haptics.selection()
                    viewModel.clearFilters()
                } label: {
                    Text("Clear All")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.outline)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
    }

    private func activeFilterChip(label: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(AppFonts.caption)
                .foregroundColor(AppColors.deepInk)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppColors.outline)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(AppColors.surfaceContainerHigh)
        .clipShape(Capsule())
    }

    // MARK: - Journal Presentation Mode (PRD §9)

    private var journalScrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {

                if viewModel.isLoading && viewModel.displayedRecords.isEmpty {
                    loadingView
                } else if viewModel.displayedRecords.isEmpty {
                    // Empty and Error States (PRD §20)
                    emptyStateView
                } else {
                    // Trail Cards List
                    ForEach(viewModel.displayedRecords) { record in
                        PublicTrailCardView(
                            record: record,
                            onSelect: {
                                selectedRecordForDetail = record
                            },
                            onSelectCreator: { creatorId in
                                if let found = viewModel.creators.first(where: { $0.creatorId == creatorId }) {
                                    viewModel.setCreatorFilter(found)
                                }
                            }
                        )
                    }

                    // Inform user of anchor-less trails if any exist in the unfiltered catalogue (PRD §6)
                    if !viewModel.unlocatedRecords.isEmpty && viewModel.state.areaFilter == .all {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(AppColors.outline)
                            Text("\(viewModel.unlocatedRecords.count) trail(s) are acoustic or spatial studies without a physical map anchor.")
                                .font(AppFonts.caption)
                                .foregroundColor(AppColors.outline)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                    }
                }

                Spacer(minLength: 120)
            }
            .padding(.top, 12)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Connecting to trails.logos registry...")
                .font(AppFonts.bodySmall)
                .foregroundColor(AppColors.outline)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Empty & Error State (PRD §20)

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "globe")
                .font(.system(size: 40))
                .foregroundColor(AppColors.outlineVariant)

            if hasActiveFilters {
                Text("No matching trails found")
                    .font(AppFonts.headlineSmall)
                    .foregroundColor(AppColors.deepInk)

                Text("No trails matched your combined active filters.")
                    .font(AppFonts.bodySmall)
                    .foregroundColor(AppColors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button("Reset Filters") {
                    viewModel.clearFilters()
                }
                .font(AppFonts.labelUI)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(AppColors.primary)
                .foregroundColor(AppColors.onPrimary)
                .clipShape(Capsule())
            } else {
                Text("Catalogue is currently empty")
                    .font(AppFonts.headlineSmall)
                    .foregroundColor(AppColors.deepInk)

                Text("Be the first to publish an owned spatial trail to the decentralized registry.")
                    .font(AppFonts.bodySmall)
                    .foregroundColor(AppColors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Map Presentation Mode (PRD §10)
    // Seamless container connected to DiscoveryState without interfering with the user's ongoing map section fixes.

    private var mapContentView: some View {
        ZStack(alignment: .bottom) {
            Map(position: $mapPosition) {
                ForEach(viewModel.locatedRecords) { record in
                    if let anchor = record.discoveryAnchor {
                        Annotation(record.title, coordinate: CLLocationCoordinate2D(latitude: anchor.latitude, longitude: anchor.longitude)) {
                            Button {
                                Haptics.selection()
                                withAnimation(.spring(response: 0.3)) {
                                    selectedRecordOnMap = record
                                }
                            } label: {
                                VStack(spacing: 3) {
                                    ZStack {
                                        Circle()
                                            .fill(AppColors.primary.opacity(selectedRecordOnMap?.trailId == record.trailId ? 0.3 : 0.15))
                                            .frame(width: selectedRecordOnMap?.trailId == record.trailId ? 38 : 30, height: selectedRecordOnMap?.trailId == record.trailId ? 38 : 30)

                                        Circle()
                                            .fill(AppColors.primary)
                                            .frame(width: 14, height: 14)

                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 5, height: 5)
                                    }

                                    Text(record.title)
                                        .font(AppFonts.labelSpatial)
                                        .foregroundColor(AppColors.deepInk)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(AppColors.pureWhite.opacity(0.94))
                                        .clipShape(Capsule())
                                        .shadow(color: Color.black.opacity(0.08), radius: 4)
                                }
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()
            .onAppear {
                focusMapOnLocatedRecords()
            }
            .onChange(of: viewModel.locatedRecords.count) { _, _ in
                focusMapOnLocatedRecords()
            }

            // Bottom drawer when a trail marker is selected
            if let record = selectedRecordOnMap {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.25)) {
                                selectedRecordOnMap = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(AppColors.outline)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    PublicTrailCardView(
                        record: record,
                        onSelect: {
                            selectedRecordForDetail = record
                        },
                        onSelectCreator: { creatorId in
                            if let found = viewModel.creators.first(where: { $0.creatorId == creatorId }) {
                                viewModel.setCreatorFilter(found)
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .background(
                    AppColors.canvas
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: Color.black.opacity(0.14), radius: 16, y: -4)
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if viewModel.locatedRecords.isEmpty {
                VStack(spacing: 8) {
                    Text("No Trails with Map Anchors")
                        .font(AppFonts.headlineSmall)
                        .foregroundColor(AppColors.deepInk)
                    Text("Published trails without coordinates appear in Journal view.")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.outline)
                }
                .padding(16)
                .background(AppColors.surfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private func focusMapOnLocatedRecords() {
        let coords = viewModel.locatedRecords.compactMap { r -> CLLocationCoordinate2D? in
            guard let a = r.discoveryAnchor else { return nil }
            return CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude)
        }
        guard !coords.isEmpty else {
            if let userLoc = TrailsLocationManager.shared.lastKnownLocation {
                mapPosition = .region(MKCoordinateRegion(
                    center: userLoc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
            return
        }
        var minLat = coords[0].latitude
        var maxLat = coords[0].latitude
        var minLon = coords[0].longitude
        var maxLon = coords[0].longitude
        for c in coords {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, (maxLat - minLat) * 1.5),
            longitudeDelta: max(0.02, (maxLon - minLon) * 1.5)
        )
        withAnimation(.easeInOut(duration: 0.4)) {
            mapPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    // MARK: - Area Filter Selection Sheet (PRD §6)

    private var areaFilterSelectionSheet: some View {
        NavigationStack {
            List {
                Section("Geographic Scopes") {
                    Button {
                        viewModel.setAreaFilter(.all)
                        showingAreaFilterSheet = false
                    } label: {
                        HStack {
                            Text("All areas (No geographic restriction)")
                            Spacer()
                            if viewModel.state.areaFilter == .all {
                                Image(systemName: "checkmark").foregroundColor(AppColors.primary)
                            }
                        }
                    }

                    Button {
                        // Near me (PRD §6)
                        if let loc = TrailsLocationManager.shared.lastKnownLocation {
                            viewModel.setAreaFilter(.nearMe(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, radiusKm: 25.0))
                        } else {
                            TrailsLocationManager.shared.requestAccessIfNeeded()
                            viewModel.setAreaFilter(.all)
                        }
                        showingAreaFilterSheet = false
                    } label: {
                        HStack {
                            Text("Near me")
                            Spacer()
                            if case .nearMe = viewModel.state.areaFilter {
                                Image(systemName: "checkmark").foregroundColor(AppColors.primary)
                            }
                        }
                    }
                }

                
            }
            .navigationTitle("Select Area")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingAreaFilterSheet = false }
                }
            }
        }
    }

    // MARK: - Creator Filter Selection Sheet (PRD §7)

    private var creatorFilterSelectionSheet: some View {
        NavigationStack {
            List {
                Button {
                    viewModel.setCreatorFilter(nil)
                    showingCreatorFilterSheet = false
                } label: {
                    HStack {
                        Text("All Creators")
                        Spacer()
                        if viewModel.state.selectedCreator == nil {
                            Image(systemName: "checkmark").foregroundColor(AppColors.primary)
                        }
                    }
                }

                if viewModel.displayedCreators.isEmpty {
                    Section {
                        Text("No other creators discovered yet.")
                            .font(AppFonts.caption)
                            .foregroundColor(AppColors.outline)
                    }
                } else {
                    Section("Published Creators") {
                        ForEach(viewModel.displayedCreators) { creator in
                            Button {
                                viewModel.setCreatorFilter(creator)
                                showingCreatorFilterSheet = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("@\(creator.username)")
                                            .font(AppFonts.bodyMedium)
                                            .foregroundColor(AppColors.deepInk)
                                        Text(creator.displayName)
                                            .font(AppFonts.caption)
                                            .foregroundColor(AppColors.secondary)
                                    }
                                    Spacer()
                                    Text("\(creator.trailCount) trails")
                                        .font(AppFonts.labelSpatial)
                                        .foregroundColor(AppColors.outline)
                                    if viewModel.state.selectedCreator?.creatorId == creator.creatorId {
                                        Image(systemName: "checkmark").foregroundColor(AppColors.primary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Testing & Samples") {
                    Toggle(isOn: Binding(
                        get: { viewModel.state.includeTestTrails },
                        set: { viewModel.setIncludeTestTrails($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include test trails & creators")
                                .font(AppFonts.bodyMedium)
                                .foregroundColor(AppColors.deepInk)
                            Text("Shows seed records and @test-* accounts")
                                .font(AppFonts.caption)
                                .foregroundColor(AppColors.onSurfaceVariant)
                        }
                    }
                }
            }
            .navigationTitle("Select Creator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingCreatorFilterSheet = false }
                }
            }
        }
    }
}
