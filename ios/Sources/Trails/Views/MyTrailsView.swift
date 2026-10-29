//
//  MyTrailsView.swift
//  Trails
//
//  Primary Spatial Journal & Map Collection screen.
//  Faithfully implements docs/stitch/v0.2.0/my_trails_spatial_journal and map_world_overview
//  compliant with PRD v0.2.0 §5, §11, and §12.
//

import SwiftUI

public struct MyTrailsView: View {
    @ObservedObject var dataStore = TrailsDataStore.shared

    @State private var showingScanner: Bool = false
    @State private var showingFilterSheet: Bool = false
    @State private var selectedTrailForRevisit: TrailDetail?
    @State private var selectedPlaceForCollection: Place?
    @State private var selectedPlaceOnMap: Place?

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

                // Floating Sticky "Start a trail" Action (PRD §5 & Stitch Design)
                floatingStartTrailButton
                    .padding(.bottom, 24)
            }
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showingScanner) {
                ScannerView()
            }
            .fullScreenCover(item: $selectedTrailForRevisit) { trail in
                SpatialTrailViewerView()
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
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
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

                if dataStore.filteredTrails.isEmpty {
                    noResultsView
                } else {
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
                    // Image / Cover Bed
                    ZStack(alignment: .bottomLeading) {
                        Image(hero.coverImageName ?? "DhunHaveliEvening")
                            .resizable()
                            .scaledToFill()
                            .frame(height: 240)
                            .clipped()

                        // Dark gradient scrim
                        LinearGradient(
                            colors: [Color.clear, AppColors.primary.opacity(0.85)],
                            startPoint: .center,
                            endPoint: .bottom
                        )

                        // Top Hardware Badge
                        VStack {
                            HStack {
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

                                Spacer()
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

                            Text("A trail by \(hero.authorName)")
                                .font(AppFonts.bodySmall)
                                .foregroundColor(AppColors.surfaceContainerHigh.opacity(0.9))
                        }
                        .padding(16)
                    }

                    // Bottom Card Spec Sheet
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Yesterday · 18:40", systemImage: "clock")
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
                                    Image(systemName: "camera")
                                        .font(.system(size: 11))
                                    Image(systemName: "mic")
                                        .font(.system(size: 11))
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
                                    .fill(AppColors.surfaceContainerHigh)
                                    .frame(width: 44, height: 44)

                                Image(systemName: trail.floorCode == "LVL 02" ? "sunset.fill" : "square.3.layers.3d.down.right")
                                    .font(.system(size: 18))
                                    .foregroundColor(AppColors.primary)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(trail.title)
                                    .font(AppFonts.headlineSmall)
                                    .foregroundColor(AppColors.deepInk)
                                    .lineLimit(1)

                                HStack(spacing: 6) {
                                    Text(trail.placeName)
                                        .font(AppFonts.bodySmall)
                                        .foregroundColor(AppColors.onSurfaceVariant)

                                    Text("·")
                                        .foregroundColor(AppColors.outline)

                                    Text("\(trail.moments.count) moments")
                                        .font(AppFonts.labelSpatial)
                                        .foregroundColor(AppColors.secondary)
                                }

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
            // Cartographic Limestone Map Bed
            ZStack {
                Color(hex: "#F5F1E8")
                    .ignoresSafeArea()

                // Stylized Continental Hairlines & Grid
                Canvas { context, size in
                    // Grid lines
                    let step: CGFloat = 40
                    for x in stride(from: 0, through: size.width, by: step) {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(AppColors.outlineVariant.opacity(0.35)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                    }
                    for y in stride(from: 0, through: size.height, by: step) {
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(path, with: .color(AppColors.outlineVariant.opacity(0.35)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                    }

                    // Equator accent
                    var eqPath = Path()
                    eqPath.move(to: CGPoint(x: 0, y: size.height * 0.45))
                    eqPath.addLine(to: CGPoint(x: size.width, y: size.height * 0.45))
                    context.stroke(eqPath, with: .color(AppColors.outline.opacity(0.4)), style: StrokeStyle(lineWidth: 0.75, dash: [4, 4]))

                    // Connective geodetic arc between places
                    var arc = Path()
                    arc.move(to: CGPoint(x: size.width * 0.58, y: size.height * 0.42))
                    arc.addQuadCurve(to: CGPoint(x: size.width * 0.64, y: size.height * 0.46), control: CGPoint(x: size.width * 0.61, y: size.height * 0.40))
                    context.stroke(arc, with: .color(AppColors.terracotta.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
                .ignoresSafeArea()

                // Place Markers on Map
                GeometryReader { geo in
                    ForEach(dataStore.places) { place in
                        // Normalized projection onto map
                        let posX = geo.size.width * 0.60 + CGFloat(place.longitude - 75.7873) * 1200
                        let posY = geo.size.height * 0.44 - CGFloat(place.latitude - 26.9124) * 1200

                        Button {
                            withAnimation(.spring(response: 0.35)) {
                                selectedPlaceOnMap = place
                            }
                        } label: {
                            VStack(spacing: 3) {
                                ZStack {
                                    Circle()
                                        .fill(AppColors.terracotta.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                    Circle()
                                        .fill(AppColors.terracotta)
                                        .frame(width: 14, height: 14)
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 4, height: 4)
                                }

                                Text(place.name)
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.deepInk)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(AppColors.pureWhite.opacity(0.9))
                                    .clipShape(Capsule())
                                    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                            }
                        }
                        .position(x: max(50, min(geo.size.width - 50, posX)), y: max(50, min(geo.size.height - 120, posY)))
                    }
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
            }

            // Bottom Selected Place Drawer (docs/stitch/v0.2.0/map_city_place_selection)
            if let place = selectedPlaceOnMap ?? dataStore.places.first {
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

                        Text("\(place.trailsCount) trails")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.terracotta)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColors.terracotta.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(place.description)
                        .font(AppFonts.bodyMedium)
                        .foregroundColor(AppColors.deepInk)
                        .lineLimit(2)

                    HStack(spacing: 12) {
                        Button {
                            selectedPlaceForCollection = place
                        } label: {
                            HStack {
                                Text("Open Place Collection")
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
                .padding(20)
                .background(AppColors.pureWhite)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.black.opacity(0.1), radius: 16, x: 0, y: -4)
                .padding(.horizontal, 16)
                .padding(.bottom, 80)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Empty / No Results View (docs/stitch/v0.2.0/map_no_results_state)

    private var noResultsView: some View {
        VStack(spacing: 14) {
            Image(systemName: "travel_explore")
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
