//
//  PlaceOverviewView.swift
//  Trails
//
//  Screen 2: Place Overview (Dhun Haveli), designed in docs/stitch/place_overview_dhun_haveli.
//  Presents place history, floor level filters, spatial previews, and curated trails list.
//

import SwiftUI

public struct PlaceOverviewView: View {
    @Environment(\.dismiss) private var dismiss
    public let place: Place

    @State private var selectedTab: PlaceViewMode = .spatialView
    @State private var selectedFloorCode: String = "LVL 00"
    @State private var selectedAuthorName: String = "Hiro"
    @State private var showingSpatialViewer: Bool = false
    @State private var showingScanner: Bool = false
    @State private var selectedTrail: TrailSummary?

    public init(place: Place) {
        self.place = place
    }

    enum PlaceViewMode: String, CaseIterable, Identifiable {
        case spatialView = "Spatial view"
        case trailList = "Trail list"

        var id: String { rawValue }
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            AppColors.canvas
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {

                    // MARK: - Place Hero & Title
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(place.name)
                                .font(AppFonts.displayLargeMobile)
                                .foregroundColor(AppColors.deepInk)

                            Spacer()

                            Text(place.surveyYear)
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.outline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(AppColors.surfaceContainerHigh)
                                .clipShape(Capsule())
                        }

                        Text(place.tagline)
                            .font(AppFonts.headlineMedium)
                            .foregroundColor(AppColors.terracotta)
                            .italic()

                        // Metadata Row
                        HStack(spacing: 16) {
                            Label(place.district, systemImage: "mappin.and.ellipse")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.onSurfaceVariant)

                            Label("\(place.trailsCount) public trails", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.primary)

                            Label("\(place.contributorsCount) contributors", systemImage: "person.2")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.onSurfaceVariant)
                        }
                        .padding(.top, 4)

                        Text(place.description)
                            .font(AppFonts.bodyMedium)
                            .foregroundColor(AppColors.deepInk)
                            .lineSpacing(4)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    // MARK: - Segmented Mode Toggle (Spatial View vs Trail List)
                    HStack(spacing: 0) {
                        Button {
                            selectedTab = .spatialView
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "view.3d")
                                Text("Spatial view")
                            }
                            .font(AppFonts.labelUI)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selectedTab == .spatialView ? AppColors.pureWhite : Color.clear)
                            .foregroundColor(selectedTab == .spatialView ? AppColors.primary : AppColors.onSurfaceVariant)
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(selectedTab == .spatialView ? 0.06 : 0), radius: 4, x: 0, y: 2)
                        }

                        Button {
                            selectedTab = .trailList
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "list.bullet")
                                Text("Trail list (\(place.trails.count))")
                            }
                            .font(AppFonts.labelUI)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selectedTab == .trailList ? AppColors.pureWhite : Color.clear)
                            .foregroundColor(selectedTab == .trailList ? AppColors.primary : AppColors.onSurfaceVariant)
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(selectedTab == .trailList ? 0.06 : 0), radius: 4, x: 0, y: 2)
                        }
                    }
                    .padding(4)
                    .background(AppColors.surfaceContainerHigh)
                    .clipShape(Capsule())
                    .padding(.horizontal, 20)

                    // MARK: - Floor Level Filter Pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(place.floorLevels) { level in
                                Button {
                                    selectedFloorCode = level.shortCode
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(level.shortCode)
                                            .font(AppFonts.labelMetric)
                                        Text("·")
                                        Text(level.name)
                                            .font(AppFonts.labelUI)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        selectedFloorCode == level.shortCode
                                            ? AppColors.primary
                                            : AppColors.pureWhite
                                    )
                                    .foregroundColor(
                                        selectedFloorCode == level.shortCode
                                            ? AppColors.onPrimary
                                            : AppColors.deepInk
                                    )
                                    .clipShape(Capsule())
                                    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // MARK: - Author Filter Chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(place.authors) { author in
                                Button {
                                    selectedAuthorName = author.name
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(AppColors.surfaceContainerHigh)
                                            .frame(width: 20, height: 20)
                                            .overlay(
                                                Text(String(author.name.prefix(1)))
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundColor(AppColors.deepInk)
                                            )

                                        Text("\(author.name) (\(author.focusArea))")
                                            .font(AppFonts.labelUI)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        selectedAuthorName == author.name
                                            ? AppColors.surfaceContainerHighest
                                            : AppColors.pureWhite
                                    )
                                    .foregroundColor(AppColors.deepInk)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(selectedAuthorName == author.name ? AppColors.terracotta : Color.clear, lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    if selectedTab == .spatialView {
                        // MARK: - Spatial Architectural Plan Canvas
                        VStack(spacing: 12) {
                            SpatialFloorPlanView(floorCode: selectedFloorCode)
                                .frame(height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(AppColors.border, lineWidth: 1)
                                )

                            // Active Curated Trail Card
                            CuratedTrailHeroCard(
                                title: "Through the Courtyard",
                                subtitle: "Morning light & ventilation paths",
                                author: "Hiro",
                                authorRole: "Architect & Spatial Explorer",
                                distanceMeters: 140,
                                momentsCount: 4,
                                onExplore: {
                                    showingSpatialViewer = true
                                }
                            )
                        }
                        .padding(.horizontal, 20)
                    } else {
                        // MARK: - Trails List View
                        VStack(spacing: 12) {
                            ForEach(place.trails) { trail in
                                TrailListItemCard(trail: trail) {
                                    selectedTrail = trail
                                    showingSpatialViewer = true
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // MARK: - Secondary Actions
                    HStack(spacing: 12) {
                        Button {
                            // Shuffle / random trail
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "shuffle")
                                Text("Select another")
                            }
                            .font(AppFonts.labelUI)
                            .foregroundColor(AppColors.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppColors.pureWhite)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(AppColors.border, lineWidth: 1)
                            )
                        }

                        Button {
                            showingScanner = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "mappin.and.ellipse")
                                Text("Leave a trail here")
                            }
                            .font(AppFonts.labelUI)
                            .foregroundColor(AppColors.onPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppColors.primary)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 40)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Place Detail")
                    .font(AppFonts.headlineSmall)
                    .foregroundColor(AppColors.deepInk)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    // Share place
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15))
                        .foregroundColor(AppColors.deepInk)
                }
            }
        }
        .fullScreenCover(isPresented: $showingSpatialViewer) {
            SpatialTrailViewerView()
        }
        .fullScreenCover(isPresented: $showingScanner) {
            TrailsScanView()
        }
    }
}

// MARK: - Spatial Floor Plan Canvas

struct SpatialFloorPlanView: View {
    let floorCode: String

    var body: some View {
        ZStack {
            Color(hex: "#FAF8F5")

            // Floor plan wireframes
            Canvas { context, size in
                // Outer wall bounds
                let outerRect = CGRect(x: 24, y: 24, width: size.width - 48, height: size.height - 48)
                context.stroke(Path(outerRect), with: .color(AppColors.deepInk.opacity(0.3)), lineWidth: 2)

                // Central open Courtyard Light Well
                let courtRect = CGRect(x: size.width * 0.35, y: size.height * 0.30, width: size.width * 0.30, height: size.height * 0.40)
                context.fill(Path(courtRect), with: .color(AppColors.canvas))
                context.stroke(Path(courtRect), with: .color(AppColors.terracotta.opacity(0.4)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                // Perimeter Rooms
                let westWing = CGRect(x: 24, y: 24, width: size.width * 0.28, height: size.height - 48)
                context.stroke(Path(westWing), with: .color(AppColors.deepInk.opacity(0.2)), lineWidth: 1)

                let eastWing = CGRect(x: size.width * 0.72, y: 24, width: size.width * 0.28 - 24, height: size.height - 48)
                context.stroke(Path(eastWing), with: .color(AppColors.deepInk.opacity(0.2)), lineWidth: 1)

                // Terracotta Active Path
                var path = Path()
                path.move(to: CGPoint(x: 36, y: size.height * 0.75))
                path.addLine(to: CGPoint(x: size.width * 0.35, y: size.height * 0.65))
                path.addLine(to: CGPoint(x: size.width * 0.50, y: size.height * 0.35))
                path.addLine(to: CGPoint(x: size.width * 0.65, y: size.height * 0.50))
                path.addLine(to: CGPoint(x: size.width * 0.85, y: size.height * 0.40))

                context.stroke(path, with: .color(AppColors.terracotta), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))

                // Waypoint Moment Nodes (Muted Brass pins)
                let waypoints = [
                    CGPoint(x: 36, y: size.height * 0.75),
                    CGPoint(x: size.width * 0.35, y: size.height * 0.65),
                    CGPoint(x: size.width * 0.50, y: size.height * 0.35),
                    CGPoint(x: size.width * 0.85, y: size.height * 0.40)
                ]

                for pt in waypoints {
                    let halo = CGRect(x: pt.x - 8, y: pt.y - 8, width: 16, height: 16)
                    context.fill(Path(ellipseIn: halo), with: .color(AppColors.mutedBrass.opacity(0.25)))
                    let pin = CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)
                    context.fill(Path(ellipseIn: pin), with: .color(AppColors.mutedBrass))
                }
            }

            // Monograph Scale HUD
            VStack {
                HStack {
                    Text("\(floorCode) · GROUND | 1:50")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.outline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.pureWhite.opacity(0.85))
                        .clipShape(Capsule())

                    Spacer()

                    Text("LiDAR MESH 24.6 kHz")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.pureWhite.opacity(0.85))
                        .clipShape(Capsule())
                }
                .padding(12)

                Spacer()
            }
        }
    }
}

// MARK: - Curated Trail Hero Card

struct CuratedTrailHeroCard: View {
    let title: String
    let subtitle: String
    let author: String
    let authorRole: String
    let distanceMeters: Int
    let momentsCount: Int
    let onExplore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppFonts.headlineMedium)
                        .foregroundColor(AppColors.deepInk)

                    Text(subtitle)
                        .font(AppFonts.bodySmall)
                        .foregroundColor(AppColors.onSurfaceVariant)
                }

                Spacer()

                Text("ACTIVE TRAIL")
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(AppColors.terracotta)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.terracotta.opacity(0.12))
                    .clipShape(Capsule())
            }

            // Author & Metric Bar
            HStack(spacing: 12) {
                Circle()
                    .fill(AppColors.surfaceContainerHigh)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(author.prefix(1)))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AppColors.deepInk)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(author)
                        .font(AppFonts.headlineSmall)
                        .foregroundColor(AppColors.deepInk)
                    Text(authorRole)
                        .font(AppFonts.bodySmall)
                        .foregroundColor(AppColors.outline)
                }

                Spacer()

                HStack(spacing: 8) {
                    Text("\(distanceMeters)m")
                        .font(AppFonts.labelMetric)
                        .foregroundColor(AppColors.deepInk)
                    Text("·")
                    Text("\(momentsCount) moments")
                        .font(AppFonts.labelMetric)
                        .foregroundColor(AppColors.deepInk)
                }
            }

            // Primary Explore Button
            Button(action: onExplore) {
                HStack {
                    Text("Explore trail")
                        .font(AppFonts.headlineSmall)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(AppColors.onPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .background(AppColors.primary)
                .clipShape(Capsule())
            }
        }
        .padding(18)
        .background(AppColors.pureWhite)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }
}

// MARK: - Trail List Item Card

struct TrailListItemCard: View {
    let trail: TrailSummary
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                Circle()
                    .fill(AppColors.surfaceContainerHigh)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.terracotta)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(trail.title)
                        .font(AppFonts.headlineSmall)
                        .foregroundColor(AppColors.deepInk)

                    Text(trail.subtitle)
                        .font(AppFonts.bodySmall)
                        .foregroundColor(AppColors.onSurfaceVariant)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(trail.authorName)
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.primary)
                        Text("·")
                        Text("\(trail.distanceMeters)m")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.outline)
                        Text("·")
                        Text("\(trail.momentsCount) moments")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.outline)
                    }
                    .padding(.top, 2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.outlineVariant)
            }
            .padding(16)
            .background(AppColors.pureWhite)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
