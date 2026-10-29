//
//  ExploreDhunMapView.swift
//  Trails
//
//  Screen 1: Explore Dhun Map, designed in docs/stitch/explore_dhun_map.
//  Expresses architectural minimalism with tactile Apple-native controls.
//

import SwiftUI
import CoreLocation

public struct ExploreDhunMapView: View {
    @ObservedObject var dataStore = TrailsDataStore.shared
    @State private var searchText: String = ""
    @State private var selectedCategory: PlaceCategory = .all
    @State private var selectedPlaceForNavigation: Place?
    @State private var showingPlaceDetail: Bool = false
    @State private var showingScanner: Bool = false
    @State private var activeMapPlaceId: String = "dhun-haveli"

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background Canvas
                AppColors.canvas
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {

                        // MARK: - Search & Filters Header
                        VStack(spacing: 12) {
                            // Search Pill
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(AppColors.onSurfaceVariant)

                                TextField("Search places, trails, or people...", text: $searchText)
                                    .font(AppFonts.bodyMedium)
                                    .foregroundColor(AppColors.deepInk)

                                Button {
                                    // Filter action
                                } label: {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 15))
                                        .foregroundColor(AppColors.onSurfaceVariant)
                                        .frame(width: 32, height: 32)
                                        .background(AppColors.surfaceContainerHigh.opacity(0.6))
                                        .clipShape(Circle())
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AppColors.pureWhite)
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)

                            // Category Filter Ribbon
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(PlaceCategory.allCases) { category in
                                        Button {
                                            selectedCategory = category
                                        } label: {
                                            Text(category.rawValue)
                                                .font(AppFonts.labelUI)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(
                                                    selectedCategory == category
                                                        ? AppColors.primary
                                                        : AppColors.pureWhite
                                                )
                                                .foregroundColor(
                                                    selectedCategory == category
                                                        ? AppColors.onPrimary
                                                        : AppColors.onSurfaceVariant
                                                )
                                                .clipShape(Capsule())
                                                .shadow(
                                                    color: Color.black.opacity(selectedCategory == category ? 0.08 : 0.03),
                                                    radius: 4,
                                                    x: 0,
                                                    y: 2
                                                )
                                        }
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        // MARK: - Stylized Architectural Map Canvas
                        ArchitecturalMapCard(
                            places: filteredPlaces,
                            selectedPlaceId: $activeMapPlaceId,
                            onSelectPlace: { place in
                                activeMapPlaceId = place.id
                                selectedPlaceForNavigation = place
                                showingPlaceDetail = true
                            }
                        )
                        .frame(height: 360)
                        .padding(.horizontal, 16)

                        // MARK: - Trails Around You Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Trails around you")
                                        .font(AppFonts.headlineSmall)
                                        .foregroundColor(AppColors.deepInk)

                                    Text("Human perspectives left in real spaces")
                                        .font(AppFonts.bodySmall)
                                        .foregroundColor(AppColors.onSurfaceVariant)
                                }

                                Spacer()

                                Text("18 nearby")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.outline)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppColors.surfaceContainerHigh)
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, 16)

                            // Place Cards List
                            VStack(spacing: 12) {
                                ForEach(filteredPlaces) { place in
                                    PlaceCardView(place: place) {
                                        selectedPlaceForNavigation = place
                                        showingPlaceDetail = true
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        // Bottom breathing room for Floating Action Button
                        Spacer(minLength: 100)
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - Floating "Start a Trail" Pill Action
                Button {
                    showingScanner = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Start a trail")
                                .font(AppFonts.headlineSmall)
                            Text("LiDAR ready")
                                .font(AppFonts.labelSpatial)
                                .opacity(0.8)
                        }
                    }
                    .foregroundColor(AppColors.onPrimary)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
                    .shadow(color: AppColors.primaryDark.opacity(0.25), radius: 12, x: 0, y: 6)
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 8) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppColors.primary)

                        Text("TRAILS")
                            .font(AppFonts.headlineSmall)
                            .tracking(1.5)
                            .foregroundColor(AppColors.primary)
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("Explore")
                        .font(AppFonts.headlineSmall)
                        .foregroundColor(AppColors.deepInk)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Circle()
                        .fill(AppColors.surfaceContainerHigh)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(AppColors.terracotta)
                        )
                }
            }
            .navigationDestination(isPresented: $showingPlaceDetail) {
                if let place = selectedPlaceForNavigation {
                    PlaceOverviewView(place: place)
                }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                TrailsScanView()
            }
        }
    }

    private var filteredPlaces: [Place] {
        if selectedCategory == .all {
            return dataStore.places
        }
        return dataStore.places.filter { $0.category == selectedCategory }
    }
}

// MARK: - Architectural Map Card Component

struct ArchitecturalMapCard: View {
    let places: [Place]
    @Binding var selectedPlaceId: String
    let onSelectPlace: (Place) -> Void

    var body: some View {
        ZStack {
            // Map Drawing Geometry
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(hex: "#F5F1E8"))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )

            // Stylized vector map elements
            Canvas { context, size in
                // Water Canal
                var waterPath = Path()
                waterPath.move(to: CGPoint(x: 0, y: size.height * 0.2))
                waterPath.addCurve(
                    to: CGPoint(x: size.width, y: size.height * 0.35),
                    control1: CGPoint(x: size.width * 0.3, y: size.height * 0.05),
                    control2: CGPoint(x: size.width * 0.7, y: size.height * 0.45)
                )
                waterPath.addLine(to: CGPoint(x: size.width, y: 0))
                waterPath.addLine(to: CGPoint(x: 0, y: 0))
                waterPath.closeSubpath()
                context.fill(waterPath, with: .color(Color(hex: "#DDE5E7")))

                // Courtyard green volumes
                let courtyard1 = CGRect(x: size.width * 0.32, y: size.height * 0.3, width: size.width * 0.35, height: size.height * 0.28)
                context.fill(Path(roundedRect: courtyard1, cornerRadius: 12), with: .color(Color(hex: "#E2E8DF")))
                context.stroke(Path(roundedRect: courtyard1, cornerRadius: 12), with: .color(Color(hex: "#D3DDD0")), lineWidth: 1)

                let courtyard2 = CGRect(x: size.width * 0.1, y: size.height * 0.55, width: size.width * 0.2, height: size.height * 0.18)
                context.fill(Path(roundedRect: courtyard2, cornerRadius: 8), with: .color(Color(hex: "#E2E8DF").opacity(0.8)))

                let courtyard3 = CGRect(x: size.width * 0.72, y: size.height * 0.5, width: size.width * 0.22, height: size.height * 0.2)
                context.fill(Path(roundedRect: courtyard3, cornerRadius: 8), with: .color(Color(hex: "#E2E8DF").opacity(0.9)))

                // Street Grid Vectors
                var roadPath = Path()
                roadPath.move(to: CGPoint(x: 0, y: size.height * 0.42))
                roadPath.addLine(to: CGPoint(x: size.width, y: size.height * 0.42))
                roadPath.move(to: CGPoint(x: size.width * 0.48, y: 0))
                roadPath.addLine(to: CGPoint(x: size.width * 0.48, y: size.height))
                context.stroke(roadPath, with: .color(Color.white), lineWidth: 6)
                context.stroke(roadPath, with: .color(Color(hex: "#E6E1D6")), lineWidth: 2)

                // Active Terracotta Trail Vector
                var trailPath = Path()
                trailPath.move(to: CGPoint(x: size.width * 0.38, y: size.height * 0.48))
                trailPath.addLine(to: CGPoint(x: size.width * 0.45, y: size.height * 0.38))
                trailPath.addLine(to: CGPoint(x: size.width * 0.55, y: size.height * 0.42))
                trailPath.addLine(to: CGPoint(x: size.width * 0.60, y: size.height * 0.52))
                context.stroke(trailPath, with: .color(AppColors.terracotta), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            // Map Pins Overlay
            VStack {
                HStack {
                    // Stepped Pavilion Pin
                    MapPinBadge(title: "Stepped Pavilion", count: "3", isSelected: selectedPlaceId == "stepped-pavilion") {
                        if let p = places.first(where: { $0.id == "stepped-pavilion" }) {
                            onSelectPlace(p)
                        }
                    }
                    .offset(x: 20, y: 40)

                    Spacer()

                    // Print Workshop Pin
                    MapPinBadge(title: "Print Workshop", count: "5", isSelected: selectedPlaceId == "print-workshop") {
                        if let p = places.first(where: { $0.id == "print-workshop" }) {
                            onSelectPlace(p)
                        }
                    }
                    .offset(x: -20, y: 60)
                }

                Spacer()

                // Dhun Haveli Main Marker (Center)
                MapPinBadge(title: "Dhun Haveli", count: "8 trails", isSelected: selectedPlaceId == "dhun-haveli", isProminent: true) {
                    if let p = places.first(where: { $0.id == "dhun-haveli" }) {
                        onSelectPlace(p)
                    }
                }
                .offset(y: -40)

                Spacer()

                HStack {
                    // Neem Courtyard Pin
                    MapPinBadge(title: "Neem Courtyard", count: "2", isSelected: selectedPlaceId == "neem-courtyard") {
                        if let p = places.first(where: { $0.id == "neem-courtyard" }) {
                            onSelectPlace(p)
                        }
                    }
                    .offset(x: 30, y: -20)

                    Spacer()
                }
            }

            // Map Tools Dock (Floating Right)
            VStack(spacing: 8) {
                Button {
                    // Location center
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.deepInk)
                        .frame(width: 36, height: 36)
                        .background(AppColors.pureWhite.opacity(0.9))
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                }

                Button {
                    // Layers toggle
                } label: {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.deepInk)
                        .frame(width: 36, height: 36)
                        .background(AppColors.pureWhite.opacity(0.9))
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(16)
        }
    }
}

// MARK: - Map Pin Badge

struct MapPinBadge: View {
    let title: String
    let count: String
    var isSelected: Bool = false
    var isProminent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isProminent ? AppColors.terracotta : AppColors.mutedBrass)
                    .frame(width: isProminent ? 10 : 8, height: isProminent ? 10 : 8)

                Text(title)
                    .font(isProminent ? AppFonts.headlineSmall : AppFonts.bodySmall)
                    .foregroundColor(AppColors.deepInk)

                Text(count)
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(AppColors.onSurfaceVariant)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.surfaceContainerHigh)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, isProminent ? 14 : 10)
            .padding(.vertical, isProminent ? 8 : 6)
            .background(AppColors.pureWhite.opacity(0.95))
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 3)
            .overlay(
                Capsule()
                    .stroke(isProminent ? AppColors.terracotta.opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
        }
    }
}

// MARK: - Place Card View

struct PlaceCardView: View {
    let place: Place
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.name)
                            .font(AppFonts.headlineMedium)
                            .foregroundColor(AppColors.deepInk)

                        Text(place.tagline)
                            .font(AppFonts.bodyMedium)
                            .foregroundColor(AppColors.onSurfaceVariant)
                            .italic()
                    }

                    Spacer()

                    Text(place.surveyYear)
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.outline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.surfaceContainerHigh)
                        .clipShape(Capsule())
                }

                // Place Metadata Badges
                HStack(spacing: 12) {
                    Label("\(place.trailsCount) paths", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.terracotta)

                    Label(place.meshVersion, systemImage: "view.3d")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.primary)

                    Spacer()

                    // Authors row
                    HStack(spacing: -6) {
                        ForEach(place.authors.prefix(3)) { author in
                            Circle()
                                .fill(AppColors.surfaceContainerHigh)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Text(String(author.name.prefix(1)))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(AppColors.deepInk)
                                )
                                .overlay(
                                    Circle().stroke(AppColors.pureWhite, lineWidth: 1.5)
                                )
                        }
                    }
                }
            }
            .padding(18)
            .background(AppColors.pureWhite)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
