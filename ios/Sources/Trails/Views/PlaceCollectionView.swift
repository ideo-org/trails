//
//  PlaceCollectionView.swift
//  Trails
//
//  Place Collection screen grouping multiple independent trails at one location.
//  Faithfully implements docs/stitch/v0.2.0/place_collection_dhun_haveli
//  compliant with PRD v0.2.0 §12 & §13.
//

import SwiftUI

public struct PlaceCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var dataStore = TrailsDataStore.shared

    let place: Place
    @State private var showingScanner: Bool = false
    @State private var selectedTrailForRevisit: TrailDetail?

    public init(place: Place) {
        self.place = place
    }

    private var placeTrails: [TrailDetail] {
        dataStore.allDisplayTrails.filter {
            $0.placeId == place.id || $0.placeName == place.name
        }
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            AppColors.canvas
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {

                    // Top Place Identity & Archive Metadata
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(AppColors.secondary)
                                    .frame(width: 8, height: 8)
                                Text("Architectural Survey Archive")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.secondary)
                                    .textCase(.uppercase)
                                    .tracking(1.2)
                            }

                            Spacer()

                            Label("Private Vault", systemImage: "lock.fill")
                                .font(AppFonts.labelMetric)
                                .foregroundColor(AppColors.onSurfaceVariant)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(AppColors.surfaceContainer)
                                .clipShape(Capsule())
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.name)
                                .font(AppFonts.displayLargeMobile)
                                .foregroundColor(AppColors.primary)

                            Label("\(place.locality) · \(placeTrails.count) Spatial Trails Documented", systemImage: "location.fill")
                                .font(AppFonts.bodySmall)
                                .foregroundColor(AppColors.onSurfaceVariant)
                        }

                        // Curated Photography Visual Frame
                        ZStack(alignment: .bottomLeading) {
                            Image(place.coverImageName ?? "DhunHaveliEvening")
                                .resizable()
                                .scaledToFill()
                                .frame(height: 220)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                            LinearGradient(
                                colors: [Color.clear, AppColors.primary.opacity(0.85)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Spatial Taxonomy · Haveli No. 04")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.secondary)
                                    .textCase(.uppercase)

                                Text(place.description)
                                    .font(AppFonts.bodySmall)
                                    .foregroundColor(AppColors.pureWhite.opacity(0.95))
                                    .lineLimit(2)
                            }
                            .padding(16)
                        }

                        // Quick Actions
                        HStack(spacing: 10) {
                            Button {
                                dataStore.startTrailAtPlace(place)
                                showingScanner = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Start another trail here")
                                }
                                .font(AppFonts.labelUI)
                                .fontWeight(.semibold)
                                .foregroundColor(AppColors.onPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppColors.primary)
                                .clipShape(Capsule())
                            }

                            Button {
                                dataStore.collectionMode = .map
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "map")
                                    Text("View on map")
                                }
                                .font(AppFonts.labelUI)
                                .foregroundColor(AppColors.primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(AppColors.surfaceContainerLow)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(AppColors.border, lineWidth: 1))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    // Recorded Journeys Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Recorded Journeys", systemImage: "timeline.selection")
                                .font(AppFonts.headlineMedium)
                                .foregroundColor(AppColors.primary)

                            Spacer()

                            Text("\(placeTrails.count) Records · LiDAR v2")
                                .font(AppFonts.labelMetric)
                                .foregroundColor(AppColors.outline)
                        }
                        .padding(.horizontal, 22)

                        VStack(spacing: 12) {
                            ForEach(placeTrails) { trail in
                                Button {
                                    selectedTrailForRevisit = trail
                                } label: {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text(trail.floorCode)
                                                .font(AppFonts.labelSpatial)
                                                .foregroundColor(AppColors.onPrimary)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(AppColors.primary)
                                                .clipShape(Capsule())

                                            Text(trail.meshDensity)
                                                .font(AppFonts.labelMetric)
                                                .foregroundColor(AppColors.onSurfaceVariant)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(AppColors.surfaceContainer)
                                                .clipShape(Capsule())

                                            Spacer()

                                            HStack(spacing: 4) {
                                                Circle()
                                                    .fill(AppColors.secondary)
                                                    .frame(width: 6, height: 6)
                                                Text("ACTIVE SURVEY")
                                                    .font(AppFonts.labelMetric)
                                                    .foregroundColor(AppColors.secondary)
                                            }
                                        }

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(trail.title)
                                                .font(AppFonts.headlineSmall)
                                                .foregroundColor(AppColors.deepInk)

                                            Text("Recorded by \(trail.authorName) · \(trail.moments.count) moments · \(trail.distanceMeters)m")
                                                .font(AppFonts.bodySmall)
                                                .foregroundColor(AppColors.onSurfaceVariant)
                                        }

                                        // "Inspired by" Relationship Note (PRD §12.3)
                                        if let note = trail.inspiredByNote {
                                            HStack(alignment: .top, spacing: 6) {
                                                Image(systemName: "quote.opening")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(AppColors.secondary)
                                                Text(note)
                                                    .font(AppFonts.bodySmall)
                                                    .italic()
                                                    .foregroundColor(AppColors.deepInk.opacity(0.8))
                                            }
                                            .padding(10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(AppColors.surfaceContainerLow)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }

                                        HStack {
                                            Text(trail.personalNotes)
                                                .font(AppFonts.bodySmall)
                                                .foregroundColor(AppColors.outline)
                                                .lineLimit(2)

                                            Spacer()

                                            HStack(spacing: 4) {
                                                Text("Explore")
                                                    .font(AppFonts.labelUI)
                                                    .foregroundColor(AppColors.primary)
                                                Image(systemName: "arrow.right")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(AppColors.primary)
                                            }
                                        }
                                    }
                                    .padding(18)
                                    .background(AppColors.pureWhite)
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 40)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Journal")
                    }
                    .font(AppFonts.labelUI)
                    .foregroundColor(AppColors.primary)
                }
            }
        }
        .fullScreenCover(isPresented: $showingScanner) {
            ScannerView()
        }
        .fullScreenCover(item: $selectedTrailForRevisit) { trail in
            SpatialTrailViewerView()
                .onAppear {
                    dataStore.activeTrail = trail
                }
        }
    }
}
