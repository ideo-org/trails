//
//  MyTrailsView.swift
//  Trails
//
//  Primary Spatial Journal & Map Collection screen.
//  Faithfully implements docs/stitch/v0.2.0/my_trails_spatial_journal and map_world_overview
//  compliant with PRD v0.2.0 §5, §11, and §12.
//

import SwiftUI
import MapKit

public struct MyTrailsView: View {
    @ObservedObject var dataStore = TrailsDataStore.shared

    @State private var showingScanner: Bool = false
    @State private var showingFilterSheet: Bool = false
    @State private var selectedTrailForRevisit: TrailDetail?
    @State private var selectedPlaceForCollection: Place?
    @State private var selectedPlaceOnMap: Place?
    @State private var selectedTrailOnMap: TrailDetail?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var showTrailsTray: Bool = true

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppColors.canvas
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top App Header Bar
                    topHeaderBar

                    // Segmented Mode Selector [ Journal | Map ] (PRD §11 & §12)
                    segmentedModePicker
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)

                    // Content Viewport: Journal View vs Map View
                    if dataStore.collectionMode == .journal {
                        journalScrollView
                    } else {
                        mapContentView
                    }
                }

                // Floating Sticky "Start a trail" Action (Journal View only when trails are present)
                if dataStore.collectionMode == .journal && !dataStore.filteredTrails.isEmpty {
                    floatingStartTrailButton
                        .padding(.bottom, 24)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showingScanner) {
                ScannerView()
            }
            .fullScreenCover(item: $selectedTrailForRevisit) { trail in
                TrailJournalDetailView(trail: trail)
                    .onAppear {
                        dataStore.activeTrail = trail
                    }
            }
            .navigationDestination(item: $selectedPlaceForCollection) { place in
                PlaceCollectionView(place: place)
            }
            .sheet(isPresented: $showingFilterSheet) {
                MapFilterDateRangeSheet()
            }
            .onAppear {
                dataStore.reloadFromDisk()
            }
        }
    }

    // MARK: - Top Header Bar

    private var topHeaderBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .shadow(color: AppColors.primary.opacity(0.12), radius: 4, x: 0, y: 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("SPATIAL JOURNAL")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.secondary)
                        .tracking(1.5)

                    Text("My Trails")
                        .font(AppFonts.headlineMedium)
                        .foregroundColor(AppColors.primary)
                }
            }

            Spacer()

            Button {
                showingFilterSheet = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.onSurfaceVariant)
                    .frame(width: 40, height: 40)
                    .background(AppColors.surfaceContainerLow)
                    .clipShape(Circle())
            }

            NavigationLink {
                UserProfileView()
            } label: {
                Circle()
                    .fill(AppColors.primary)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 15))
                            .foregroundColor(AppColors.onPrimary)
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(AppColors.canvas.opacity(0.95))
    }

    // MARK: - Segmented Mode Picker [ Journal | Map ]

    private var segmentedModePicker: some View {
        HStack {
            Spacer()
            HStack(spacing: 4) {
                ForEach(CollectionMode.allCases) { mode in
                    Button {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            dataStore.collectionMode = mode
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if mode == .map && dataStore.collectionMode == .map {
                                Circle()
                                    .fill(AppColors.secondary)
                                    .frame(width: 6, height: 6)
                            }
                            Text(mode.rawValue)
                                .font(AppFonts.labelUI)
                                .foregroundColor(dataStore.collectionMode == mode ? AppColors.onPrimary : AppColors.onSurfaceVariant)
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 8)
                        .background(dataStore.collectionMode == mode ? AppColors.primary : Color.clear)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(4)
            .background(AppColors.surfaceContainer)
            .clipShape(Capsule())
            Spacer()
        }
    }

    // MARK: - Journal View Mode

    private var journalScrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {

                // Search Bar
                searchBar

                // My Trails Provenance Filter (PRD v0.4.0 §14: All | Recorded by me | Downloaded)
                myTrailsProvenanceFilter

                if dataStore.filteredTrails.isEmpty {
                    if dataStore.searchText.isEmpty && dataStore.selectedPlaceFilter == nil && dataStore.selectedYearFilter == nil {
                        // PRD §7 First launch / honest empty state
                        firstLaunchEmptyState
                    } else {
                        noResultsView
                    }
                } else {
                    // Recoverable Drafts (PRD §21 & §23)
                    if !dataStore.userDrafts.isEmpty {
                        recoverableDraftsSection
                    }

                    // Latest Encounter Hero Card (Stitch design specification)
                    if let hero = dataStore.filteredTrails.first {
                        latestEncounterSection(hero)
                    }

                    // Earlier Trails Section
                    if dataStore.filteredTrails.count > 1 {
                        earlierTrailsSection(Array(dataStore.filteredTrails.dropFirst()))
                    }

                    // Introspective Reflection Prompt
                    introspectiveReflectionCard
                }

                // Explicitly Separated Sample Reference (PRD §7 & §26)
                if let sample = dataStore.sampleMonograph {
                    sampleReferenceSection(sample)
                }

                Spacer(minLength: 120)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.outline)
                .font(.system(size: 16))

            TextField("Search your trails and locations...", text: $dataStore.searchText)
                .font(AppFonts.bodyMedium)
                .foregroundColor(AppColors.deepInk)

            if !dataStore.searchText.isEmpty {
                Button {
                    dataStore.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.outline)
                }
            }

            Text("LOCAL")
                .font(AppFonts.labelSpatial)
                .foregroundColor(AppColors.outline)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.surfaceContainer)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.surfaceContainerLow)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 2)
        .padding(.horizontal, 20)
    }

    // MARK: - My Trails Provenance Filter (PRD v0.4.0 §14)

    private var myTrailsProvenanceFilter: some View {
        HStack(spacing: 6) {
            ForEach(MyTrailsFilter.allCases) { filter in
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.25)) {
                        dataStore.myTrailsFilter = filter
                    }
                } label: {
                    Text(filter.rawValue)
                        .font(AppFonts.labelSpatial)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(dataStore.myTrailsFilter == filter ? AppColors.primary : AppColors.surfaceContainerHigh)
                        .foregroundColor(dataStore.myTrailsFilter == filter ? AppColors.onPrimary : AppColors.deepInk)
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Latest Encounter Hero Card

    private func latestEncounterSection(_ hero: TrailDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LATEST ENCOUNTER")
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(AppColors.secondary)
                    .tracking(1.5)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(AppColors.primary)
                        .frame(width: 6, height: 6)
                    Text("Active Point Mesh")
                        .font(AppFonts.labelMetric)
                        .foregroundColor(AppColors.outline)
                }
            }
            .padding(.horizontal, 22)

            Button {
                selectedTrailForRevisit = hero
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    // Image / Cover Bed: Authentic media or architectural cartographic header
                    let heroMedia = hero.moments.filter { m in
                        ((m.hasPhoto || m.mediaType == "photo") && m.resolvedPhotoURL(trailId: hero.id, fallbackTrailId: hero.inspiredByTrailId) != nil)
                        || ((m.hasVideo || m.mediaType == "video") && (m.resolvedVideoURL(trailId: hero.id, fallbackTrailId: hero.inspiredByTrailId) != nil || m.resolvedVideoThumbnailURL(trailId: hero.id, fallbackTrailId: hero.inspiredByTrailId) != nil))
                    }

                    ZStack(alignment: .bottomLeading) {
                        if let first = heroMedia.first {
                            if first.hasVideo || first.mediaType == "video",
                               let thumbURL = first.resolvedVideoThumbnailURL(trailId: hero.id, fallbackTrailId: hero.inspiredByTrailId),
                               let uiImage = UIImage(contentsOfFile: thumbURL.path) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 240)
                                    .clipped()
                            } else if let photoURL = first.resolvedPhotoURL(trailId: hero.id, fallbackTrailId: hero.inspiredByTrailId),
                                      let uiImage = UIImage(contentsOfFile: photoURL.path) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 240)
                                    .clipped()
                            } else {
                                cartographicHeroHeader(for: hero)
                            }
                        } else if let coverURL = hero.resolvedCoverImageURL() ?? hero.resolvedStartFrameURL(),
                                  let uiImage = UIImage(contentsOfFile: coverURL.path) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 240)
                                .clipped()
                        } else {
                            cartographicHeroHeader(for: hero)
                        }

                        // Dark gradient scrim
                        LinearGradient(
                            colors: [Color.clear, AppColors.primary.opacity(0.85)],
                            startPoint: .center,
                            endPoint: .bottom
                        )

                        // Top Hardware Badge
                        VStack {
                            HStack {
                                if hero.isRetrace {
                                    HStack(spacing: 5) {
                                        Image(systemName: "figure.walk.motion")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("RETRACE")
                                            .font(AppFonts.labelSpatial)
                                        if let sim = hero.retraceSimilarityIndex {
                                            Text("· \(Int(sim * 100))% MATCH")
                                                .font(AppFonts.labelSpatial)
                                        }
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(hex: "#00838F"))
                                    .clipShape(Capsule())
                                } else if hero.isPublished {
                                    HStack(spacing: 5) {
                                        Image(systemName: "globe.americas.fill")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(AppColors.forestGreen)
                                        Text("PUBLISHED · REV \(hero.publishedRevision ?? 1)")
                                            .font(AppFonts.labelSpatial)
                                            .foregroundColor(AppColors.forestGreen)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(AppColors.pureWhite.opacity(0.95))
                                    .clipShape(Capsule())
                                } else {
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(AppColors.primary)
                                            .frame(width: 6, height: 6)
                                        Text("Saved on this iPhone")
                                            .font(AppFonts.labelSpatial)
                                            .foregroundColor(AppColors.primary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(AppColors.pureWhite.opacity(0.92))
                                    .clipShape(Capsule())
                                }

                                Spacer()

                                if heroMedia.count > 1 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "photo.stack")
                                            .font(.system(size: 11))
                                        Text("\(heroMedia.count) Moments")
                                            .font(AppFonts.labelSpatial)
                                    }
                                    .foregroundColor(AppColors.pureWhite)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(16)
                            Spacer()
                        }

                        // Bottom Title & Attribution
                        VStack(alignment: .leading, spacing: 4) {
                            Text(hero.title)
                                .font(AppFonts.headlineLarge)
                                .foregroundColor(AppColors.pureWhite)
                                .multilineTextAlignment(.leading)

                            HStack(spacing: 6) {
                                Text("A trail by \(hero.authorName)")
                                    .font(AppFonts.bodySmall)
                                    .foregroundColor(AppColors.surfaceContainerHigh.opacity(0.9))

                                if let refTitle = hero.retraceReferenceTrailTitle {
                                    Text("·")
                                        .foregroundColor(AppColors.surfaceContainerHigh.opacity(0.6))
                                    Text("Retraced from “\(refTitle)”")
                                        .font(AppFonts.caption)
                                        .foregroundColor(Color(hex: "#00E5FF"))
                                }
                            }
                        }
                        .padding(16)
                    }

                    // Bottom Card Spec Sheet
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(hero.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.secondary)

                            Spacer()

                            Text(hero.meshDensity)
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.outline)
                        }

                        Divider()

                        HStack {
                            HStack(spacing: 8) {
                                Text("\(hero.moments.count) moments")
                                    .font(AppFonts.labelMetric)
                                    .foregroundColor(AppColors.primary)

                                HStack(spacing: 4) {
                                    if hero.photoCount > 0 {
                                        Image(systemName: "camera")
                                            .font(.system(size: 11))
                                    }
                                    if hero.videoCount > 0 {
                                        Image(systemName: "video.fill")
                                            .font(.system(size: 11))
                                    }
                                    if hero.audioCount > 0 {
                                        Image(systemName: "mic")
                                            .font(.system(size: 11))
                                    }
                                    Text(hero.mediaSummary)
                                        .font(AppFonts.labelSpatial)
                                }
                                .foregroundColor(AppColors.onSurfaceVariant)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppColors.surfaceContainer)
                                .clipShape(Capsule())
                            }

                            Spacer()

                            HStack(spacing: 4) {
                                Text("Walk path")
                                    .font(AppFonts.labelUI)
                                    .foregroundColor(AppColors.primary)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(AppColors.primary)
                            }
                        }
                    }
                    .padding(16)
                    .background(AppColors.pureWhite)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                .padding(.horizontal, 20)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private func cartographicHeroHeader(for trail: TrailDetail) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#151C24"), Color(hex: "#0D1318")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 8) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 34))
                    .foregroundColor(AppColors.secondary.opacity(0.9))

                Text("\(trail.distanceMeters)m Spatial Footprint · \(trail.floorCode)")
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(AppColors.pureWhite.opacity(0.75))
                    .tracking(1.0)
            }
        }
        .frame(height: 240)
    }

    // MARK: - Earlier Trails Section

    private func earlierTrailsSection(_ trails: [TrailDetail]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Earlier Trails")
                    .font(AppFonts.headlineMedium)
                    .foregroundColor(AppColors.primary)

                Spacer()

                Text("\(trails.count) Local Archives")
                    .font(AppFonts.labelMetric)
                    .foregroundColor(AppColors.secondary)
            }
            .padding(.horizontal, 22)

            VStack(spacing: 10) {
                ForEach(trails) { trail in
                    Button {
                        selectedTrailForRevisit = trail
                    } label: {
                        HStack(spacing: 14) {
                            // Left Icon Thumbnail
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(trail.isRetrace ? Color(hex: "#00838F").opacity(0.12) : AppColors.surfaceContainerHigh)
                                    .frame(width: 44, height: 44)

                                Image(systemName: trail.isRetrace ? "figure.walk.motion" : (trail.floorCode == "LVL 02" ? "sunset.fill" : "square.3.layers.3d.down.right"))
                                    .font(.system(size: 18))
                                    .foregroundColor(trail.isRetrace ? Color(hex: "#00838F") : AppColors.primary)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(trail.title)
                                        .font(AppFonts.headlineSmall)
                                        .foregroundColor(AppColors.deepInk)
                                        .lineLimit(1)

                                    if trail.isRetrace {
                                        Text("RETRACE")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(hex: "#00838F"))
                                            .clipShape(Capsule())
                                    }
                                }

                                HStack(spacing: 6) {
                                    Text(trail.placeName)
                                        .font(AppFonts.bodySmall)
                                        .foregroundColor(AppColors.onSurfaceVariant)

                                    Text("·")
                                        .foregroundColor(AppColors.outline)

                                    Text("\(trail.moments.count) moments")
                                        .font(AppFonts.labelSpatial)
                                        .foregroundColor(AppColors.secondary)

                                    if let sim = trail.retraceSimilarityIndex {
                                        Text("·")
                                            .foregroundColor(AppColors.outline)
                                        Text("\(Int(sim * 100))% match")
                                            .font(AppFonts.labelSpatial)
                                            .foregroundColor(Color(hex: "#00838F"))
                                    }
                                }

                                if trail.isDownloaded {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.system(size: 8))
                                            .foregroundColor(AppColors.forestGreen)
                                        Text("Downloaded · By @\(trail.creatorUsername ?? trail.authorName)")
                                            .font(AppFonts.labelSpatial)
                                            .foregroundColor(AppColors.forestGreen)
                                    }
                                    .padding(.top, 2)
                                } else if let refTitle = trail.retraceReferenceTrailTitle {
                                    Text("Retraced from “\(refTitle)”")
                                        .font(AppFonts.caption)
                                        .foregroundColor(AppColors.secondary)
                                        .lineLimit(1)
                                } else if trail.isPublished {
                                    HStack(spacing: 4) {
                                        Image(systemName: "globe.americas.fill")
                                            .font(.system(size: 8))
                                            .foregroundColor(AppColors.forestGreen)
                                        Text("Published · Rev \(trail.publishedRevision ?? 1)")
                                            .font(AppFonts.labelSpatial)
                                            .foregroundColor(AppColors.forestGreen)
                                    }
                                    .padding(.top, 2)
                                } else {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(AppColors.primary)
                                            .frame(width: 5, height: 5)
                                        Text("Saved on this iPhone")
                                            .font(AppFonts.labelSpatial)
                                            .foregroundColor(AppColors.primary)
                                    }
                                    .padding(.top, 2)
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 8) {
                                Text("\(trail.distanceMeters)m")
                                    .font(AppFonts.labelMetric)
                                    .foregroundColor(AppColors.outline)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppColors.outlineVariant)
                            }
                        }
                        .padding(16)
                        .background(AppColors.surfaceContainerLow)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Introspective Reflection Card

    private var introspectiveReflectionCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 20))
                .foregroundColor(AppColors.secondary)

            Text("“What would you like to remember about being here?”")
                .font(AppFonts.headlineMedium)
                .italic()
                .foregroundColor(AppColors.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Text("LiDAR scans, ambient sounds, and notes remain encrypted and entirely local to your device.")
                .font(AppFonts.bodySmall)
                .foregroundColor(AppColors.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(AppColors.surfaceContainerHigh.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Map View Mode (PRD §11.2 & docs/stitch/v0.2.0/map_world_overview)

    private var mapContentView: some View {
        ZStack(alignment: .bottom) {
            // Interactive Map Canvas
            Map(position: $mapPosition) {
                // Pins for each trail with coordinates
                ForEach(dataStore.filteredTrails.filter { $0.coordinate != nil }) { trail in
                    Annotation(trail.title, coordinate: trail.coordinate!) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedTrailOnMap = trail
                                selectedPlaceOnMap = nil
                            }
                        } label: {
                            trailMapMarker(trail: trail, isSelected: selectedTrailOnMap?.id == trail.id)
                        }
                    }
                }

                // Pins for places
                ForEach(dataStore.places.filter { $0.latitude != 0 && $0.longitude != 0 }) { place in
                    Annotation(place.name, coordinate: place.coordinate) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedPlaceOnMap = place
                                selectedTrailOnMap = nil
                            }
                        } label: {
                            placeMapMarker(place: place, isSelected: selectedPlaceOnMap?.id == place.id)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()
            .onAppear {
                focusMapOnTrails()
            }
            .onChange(of: dataStore.filteredTrails.count) { _, _ in
                focusMapOnTrails()
            }

            // Top Map HUD (Filters & Search)
            VStack(spacing: 8) {
                searchBar
                    .padding(.top, 4)

                // Filter Summary Chips
                HStack(spacing: 8) {
                    Button {
                        showingFilterSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(dataStore.selectedYearFilter ?? "All Time")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                        }
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.deepInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColors.surfaceContainerHigh)
                        .clipShape(Capsule())
                    }

                    if dataStore.selectedPlaceFilter != nil {
                        Button {
                            dataStore.selectedPlaceFilter = nil
                        } label: {
                            HStack(spacing: 4) {
                                Text(dataStore.selectedPlaceFilter!)
                                Image(systemName: "xmark")
                                    .font(.system(size: 9))
                            }
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.deepInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppColors.surfaceContainerHigh)
                            .clipShape(Capsule())
                        }
                    }

                    Spacer()

                    Text("\(dataStore.filteredTrails.count) trails · \(dataStore.places.count) places")
                        .font(AppFonts.labelMetric)
                        .foregroundColor(AppColors.onSurfaceVariant)
                }
                .padding(.horizontal, 24)

                Spacer()
            }

            // Floating Map Controls (Right Side)
            VStack(spacing: 8) {
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.35)) {
                        focusMapOnTrails()
                    }
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 15))
                        .foregroundColor(AppColors.primary)
                        .frame(width: 38, height: 38)
                        .background(AppColors.pureWhite.opacity(0.92))
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 2)
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, selectedTrailOnMap != nil || selectedPlaceOnMap != nil ? 220 : (showTrailsTray ? 150 : 70))
            .frame(maxWidth: .infinity, alignment: .trailing)

            // Bottom Overlays: Selected Trail Drawer, Selected Place Drawer, or Accessible Trails Tray
            if let trail = selectedTrailOnMap {
                selectedTrailDrawer(trail)
            } else if let place = selectedPlaceOnMap {
                selectedPlaceDrawer(place)
            } else {
                mapTrailsTray
            }
        }
    }

    private func focusMapOnTrails() {
        let trailsWithCoords = dataStore.filteredTrails.compactMap { $0.coordinate }

        if !trailsWithCoords.isEmpty {
            var minLat = trailsWithCoords[0].latitude
            var maxLat = trailsWithCoords[0].latitude
            var minLon = trailsWithCoords[0].longitude
            var maxLon = trailsWithCoords[0].longitude

            for c in trailsWithCoords {
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
                latitudeDelta: max(0.015, (maxLat - minLat) * 1.5),
                longitudeDelta: max(0.015, (maxLon - minLon) * 1.5)
            )
            mapPosition = .region(MKCoordinateRegion(center: center, span: span))
        } else if let firstPlace = dataStore.places.first(where: { $0.latitude != 0 && $0.longitude != 0 }) {
            mapPosition = .region(MKCoordinateRegion(
                center: firstPlace.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))
        }
    }

    private func trailMapMarker(trail: TrailDetail, isSelected: Bool) -> some View {
        VStack(spacing: 3) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(AppColors.primary.opacity(0.25))
                        .frame(width: 38, height: 38)
                }
                Circle()
                    .fill(isSelected ? AppColors.primary : AppColors.forestGreen)
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
            }

            Text(trail.title)
                .font(AppFonts.labelSpatial)
                .foregroundColor(AppColors.deepInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppColors.pureWhite.opacity(0.92))
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
        }
    }

    private func placeMapMarker(place: Place, isSelected: Bool) -> some View {
        VStack(spacing: 3) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(AppColors.terracotta.opacity(0.25))
                        .frame(width: 38, height: 38)
                }
                Circle()
                    .fill(AppColors.terracotta)
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
            }

            Text(place.name)
                .font(AppFonts.labelSpatial)
                .foregroundColor(AppColors.deepInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppColors.pureWhite.opacity(0.92))
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
        }
    }

    private func selectedTrailDrawer(_ trail: TrailDetail) -> some View {
        VStack(spacing: 10) {
            // Drag indicator handle
            Capsule()
                .fill(AppColors.outline.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trail.title)
                            .font(AppFonts.headlineLarge)
                            .foregroundColor(AppColors.primary)
                            .lineLimit(1)

                        Text(trail.placeName.isEmpty ? trail.locality : "\(trail.placeName) · \(trail.locality)")
                            .font(AppFonts.bodySmall)
                            .foregroundColor(AppColors.onSurfaceVariant)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            selectedTrailOnMap = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(AppColors.outline.opacity(0.7))
                    }
                }

                HStack(spacing: 12) {
                    Label("\(trail.distanceMeters)m", systemImage: "figure.walk")
                        .font(AppFonts.labelMetric)
                        .foregroundColor(AppColors.primary)

                    Text("·")
                        .foregroundColor(AppColors.outline)

                    Label("\(trail.moments.count) moments", systemImage: "sparkles")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.secondary)

                    Spacer()

                    Text(trail.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.outline)
                }

                HStack(spacing: 12) {
                    Button {
                        selectedTrailForRevisit = trail
                    } label: {
                        HStack {
                            Text("Open Trail")
                                .font(AppFonts.labelUI)
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .foregroundColor(AppColors.onPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(AppColors.primary)
                        .clipShape(Capsule())
                    }

                    Button {
                        dataStore.activeTrail = trail
                        showingScanner = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "record.circle")
                            Text("Record Here")
                        }
                        .font(AppFonts.labelUI)
                        .foregroundColor(AppColors.primary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(AppColors.surfaceContainerLow)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppColors.border, lineWidth: 1))
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .background(AppColors.pureWhite)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: -4)
        .padding(.horizontal, 16)
        .padding(.bottom, 80)
        .gesture(
            DragGesture().onEnded { value in
                if value.translation.height > 35 {
                    withAnimation(.spring(response: 0.25)) {
                        selectedTrailOnMap = nil
                    }
                }
            }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func selectedPlaceDrawer(_ place: Place) -> some View {
        VStack(spacing: 10) {
            // Drag indicator handle
            Capsule()
                .fill(AppColors.outline.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(AppFonts.headlineLarge)
                            .foregroundColor(AppColors.primary)

                        Text(place.locality)
                            .font(AppFonts.bodySmall)
                            .foregroundColor(AppColors.onSurfaceVariant)
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            selectedPlaceOnMap = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(AppColors.outline.opacity(0.7))
                    }
                }

                if !place.description.isEmpty {
                    Text(place.description)
                        .font(AppFonts.bodyMedium)
                        .foregroundColor(AppColors.deepInk)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    Button {
                        selectedPlaceForCollection = place
                    } label: {
                        HStack {
                            Text("Open Place Collection (\(place.trailsCount))")
                                .font(AppFonts.labelUI)
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .foregroundColor(AppColors.onPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(AppColors.primary)
                        .clipShape(Capsule())
                    }

                    Button {
                        dataStore.startTrailAtPlace(place)
                        showingScanner = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "record.circle")
                            Text("Record Here")
                        }
                        .font(AppFonts.labelUI)
                        .foregroundColor(AppColors.primary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(AppColors.surfaceContainerLow)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppColors.border, lineWidth: 1))
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .background(AppColors.pureWhite)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: -4)
        .padding(.horizontal, 16)
        .padding(.bottom, 80)
        .gesture(
            DragGesture().onEnded { value in
                if value.translation.height > 35 {
                    withAnimation(.spring(response: 0.25)) {
                        selectedPlaceOnMap = nil
                    }
                }
            }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var mapTrailsTray: some View {
        VStack(spacing: 8) {
            // Header bar of tray with toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showTrailsTray.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.system(size: 13, weight: .semibold))
                    Text("My Trails (\(dataStore.filteredTrails.count))")
                        .font(AppFonts.labelUI)
                    Image(systemName: showTrailsTray ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(AppColors.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppColors.pureWhite.opacity(0.95))
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
            }

            if showTrailsTray && !dataStore.filteredTrails.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(dataStore.filteredTrails) { trail in
                            Button {
                                if let coord = trail.coordinate {
                                    withAnimation(.spring(response: 0.35)) {
                                        mapPosition = .region(MKCoordinateRegion(
                                            center: coord,
                                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                        ))
                                        selectedTrailOnMap = trail
                                    }
                                } else {
                                    selectedTrailForRevisit = trail
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(AppColors.surfaceContainerHigh)
                                            .frame(width: 40, height: 40)
                                        Image(systemName: trail.coordinate != nil ? "mappin.and.ellipse" : "figure.walk")
                                            .font(.system(size: 16))
                                            .foregroundColor(AppColors.primary)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(trail.title)
                                            .font(AppFonts.labelUI)
                                            .fontWeight(.semibold)
                                            .foregroundColor(AppColors.deepInk)
                                            .lineLimit(1)

                                        HStack(spacing: 4) {
                                            Text("\(trail.distanceMeters)m")
                                                .font(AppFonts.labelMetric)
                                                .foregroundColor(AppColors.outline)
                                            Text("·")
                                                .foregroundColor(AppColors.outline)
                                            Text("\(trail.moments.count) moments")
                                                .font(AppFonts.caption)
                                                .foregroundColor(AppColors.secondary)
                                        }
                                    }

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(AppColors.outlineVariant)
                                        .padding(.leading, 4)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(AppColors.pureWhite)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                }
            }
        }
        .padding(.bottom, 80)
    }

    // MARK: - Empty / No Results View (docs/stitch/v0.2.0/map_no_results_state)

    private var noResultsView: some View {
        VStack(spacing: 14) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 42))
                .foregroundColor(AppColors.outline.opacity(0.6))
                .padding(.top, 40)

            Text("No Matching Trails Found")
                .font(AppFonts.headlineMedium)
                .foregroundColor(AppColors.primary)

            Text("Try searching for another place, or clear your active filters.")
                .font(AppFonts.bodyMedium)
                .foregroundColor(AppColors.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                dataStore.clearFilters()
            } label: {
                Text("Clear filters")
                    .font(AppFonts.labelUI)
                    .foregroundColor(AppColors.onPrimary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - First Launch Honest Empty State (PRD §7)

    private var firstLaunchEmptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "map.fill")
                .font(.system(size: 48))
                .foregroundColor(AppColors.terracotta)
                .padding(.top, 40)

            VStack(spacing: 8) {
                Text("Keep the places you experience, and the moments you want to remember.")
                    .font(AppFonts.headlineLarge)
                    .foregroundColor(AppColors.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Text("Start recording a journey. Capture photos, videos, voice notes, and thoughts as you walk.")
                    .font(AppFonts.bodyMedium)
                    .foregroundColor(AppColors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            Button {
                Haptics.success()
                dataStore.targetPlaceForRecording = nil
                showingScanner = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 16, weight: .bold))
                    Text("Start a trail")
                        .font(AppFonts.headlineSmall)
                }
                .foregroundColor(AppColors.onPrimary)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(AppColors.primary)
                .clipShape(Capsule())
                .shadow(color: AppColors.primary.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Recoverable Drafts (PRD §21 & §23)

    private var recoverableDraftsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RECOVERABLE DRAFTS")
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(AppColors.terracotta)
                    .tracking(1.5)

                Spacer()

                Text("\(dataStore.userDrafts.count) pending")
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(AppColors.outline)
            }
            .padding(.horizontal, 22)

            ForEach(dataStore.userDrafts) { draft in
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.terracotta)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.title)
                            .font(AppFonts.labelUI)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.primary)

                        Text("Interrupted · \(draft.moments.count) moments · \(draft.updatedAt.formatted(date: .omitted, time: .shortened))")
                            .font(AppFonts.caption)
                            .foregroundColor(AppColors.onSurfaceVariant)
                    }

                    Spacer()

                    Button {
                        selectedTrailForRevisit = draft
                    } label: {
                        Text("Resume")
                            .font(AppFonts.labelSpatial)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.onPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppColors.primary)
                            .clipShape(Capsule())
                    }
                }
                .padding(14)
                .background(AppColors.surfaceContainerLow)
                .cornerRadius(14)
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Explicit Sample Reference Section (PRD §7 & §26)

    private func sampleReferenceSection(_ sample: TrailDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("EXPLORE SAMPLE MONOGRAPH")
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(AppColors.secondary)
                    .tracking(1.5)

                Spacer()

                Text("Architectural Reference")
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(AppColors.outline)
            }
            .padding(.horizontal, 22)

            Button {
                selectedTrailForRevisit = sample
            } label: {
                HStack(spacing: 14) {
                    if let firstPhoto = sample.moments.first(where: { $0.hasPhoto }),
                       let photoURL = firstPhoto.resolvedPhotoURL(trailId: sample.id),
                       let uiImage = UIImage(contentsOfFile: photoURL.path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipped()
                            .cornerRadius(12)
                    } else {
                        ZStack {
                            AppColors.surfaceContainerHigh
                            Image(systemName: "doc.text.image")
                                .font(.system(size: 24))
                                .foregroundColor(AppColors.secondary)
                        }
                        .frame(width: 64, height: 64)
                        .cornerRadius(12)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(sample.title)
                            .font(AppFonts.labelUI)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.primary)
                            .lineLimit(1)

                        Text(sample.subtitle)
                            .font(AppFonts.caption)
                            .foregroundColor(AppColors.onSurfaceVariant)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text("Sample Monograph")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.mutedBrass)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.surfaceContainerHigh)
                                .clipShape(Capsule())

                            Text("· \(sample.moments.count) Moments")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.outline)
                        }
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.outlineVariant)
                }
                .padding(14)
                .background(AppColors.surfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.top, 16)
    }

    // MARK: - Floating "Start a trail" CTA Button

    private var floatingStartTrailButton: some View {
        Button {
            dataStore.targetPlaceForRecording = nil
            showingScanner = true
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(AppColors.terracotta)
                    .frame(width: 8, height: 8)

                Text("Start a trail")
                    .font(AppFonts.labelUI)
                    .fontWeight(.semibold)

                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(AppColors.onPrimary)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(AppColors.primary)
            .clipShape(Capsule())
            .shadow(color: AppColors.primary.opacity(0.35), radius: 10, x: 0, y: 5)
        }
    }
}

// MARK: - Date Range & Year Filter Sheet (docs/stitch/v0.2.0/map_filter_date_range)

private struct MapFilterDateRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var dataStore = TrailsDataStore.shared

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Filter Collection")
                    .font(AppFonts.headlineMedium)
                    .foregroundColor(AppColors.primary)

                // Year selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("RECORDING YEAR")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.secondary)

                    HStack(spacing: 8) {
                        Button {
                            dataStore.selectedYearFilter = nil
                        } label: {
                            Text("All Time")
                                .font(AppFonts.labelUI)
                                .foregroundColor(dataStore.selectedYearFilter == nil ? AppColors.onPrimary : AppColors.deepInk)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(dataStore.selectedYearFilter == nil ? AppColors.primary : AppColors.surfaceContainerLow)
                                .clipShape(Capsule())
                        }

                        ForEach(dataStore.availableYears, id: \.self) { year in
                            Button {
                                dataStore.selectedYearFilter = year
                            } label: {
                                Text(year)
                                    .font(AppFonts.labelUI)
                                    .foregroundColor(dataStore.selectedYearFilter == year ? AppColors.onPrimary : AppColors.deepInk)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(dataStore.selectedYearFilter == year ? AppColors.primary : AppColors.surfaceContainerLow)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                // Place filter
                VStack(alignment: .leading, spacing: 8) {
                    Text("PLACE ASSOCIATION")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button {
                                dataStore.selectedPlaceFilter = nil
                            } label: {
                                Text("All Places")
                                    .font(AppFonts.labelUI)
                                    .foregroundColor(dataStore.selectedPlaceFilter == nil ? AppColors.onPrimary : AppColors.deepInk)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(dataStore.selectedPlaceFilter == nil ? AppColors.primary : AppColors.surfaceContainerLow)
                                    .clipShape(Capsule())
                            }

                            ForEach(dataStore.places) { place in
                                Button {
                                    dataStore.selectedPlaceFilter = place.name
                                } label: {
                                    Text(place.name)
                                        .font(AppFonts.labelUI)
                                        .foregroundColor(dataStore.selectedPlaceFilter == place.name ? AppColors.onPrimary : AppColors.deepInk)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(dataStore.selectedPlaceFilter == place.name ? AppColors.primary : AppColors.surfaceContainerLow)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    Button("Reset All") {
                        dataStore.clearFilters()
                        dismiss()
                    }
                    .font(AppFonts.labelUI)
                    .foregroundColor(AppColors.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColors.surfaceContainerHigh)
                    .clipShape(Capsule())

                    Button("Apply Filters") {
                        dismiss()
                    }
                    .font(AppFonts.labelUI)
                    .foregroundColor(AppColors.onPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
                }
            }
            .padding(24)
            .background(AppColors.canvas.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .presentationDetents([.height(340)])
    }
}
