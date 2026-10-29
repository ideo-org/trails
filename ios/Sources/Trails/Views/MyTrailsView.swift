//
//  MyTrailsView.swift
//  Trails
//
//  Screen 2: My Trails, managing private saved scans and drafts (PRD v0.1.0 §7.1 & §10.2).
//

import SwiftUI

public struct MyTrailsView: View {
    @ObservedObject var dataStore = TrailsDataStore.shared
    @State private var searchText: String = ""
    @State private var selectedTrailForReview: TrailDetail?
    @State private var selectedTrailForViewer: TrailDetail?
    @State private var showingScanner: Bool = false
    @State private var trailToDelete: TrailDetail?
    @State private var showingDeleteAlert: Bool = false

    public init() {}

    private var filteredSavedTrails: [TrailDetail] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return dataStore.savedTrails
        }
        return dataStore.savedTrails.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.placeName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredDrafts: [TrailDetail] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return dataStore.userDrafts
        }
        return dataStore.userDrafts.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.placeName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredSampleTrails: [TrailDetail] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return dataStore.sampleTrails
        }
        return dataStore.sampleTrails.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.placeName.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppColors.canvas
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        // Header Narrative
                        VStack(alignment: .leading, spacing: 4) {
                            Text("My Trails")
                                .font(AppFonts.displayLargeMobile)
                                .foregroundColor(AppColors.deepInk)

                            Text("Spatial captures and drafts stored privately on this device.")
                                .font(AppFonts.bodyMedium)
                                .foregroundColor(AppColors.onSurfaceVariant)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                        // Search Bar
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(AppColors.outline)
                            TextField("Search trails and locations", text: $searchText)
                                .font(AppFonts.bodyMedium)
                                .foregroundColor(AppColors.deepInk)
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(AppColors.outline)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppColors.pureWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                        .padding(.horizontal, 20)

                        // Empty State Check
                        if filteredSavedTrails.isEmpty && filteredDrafts.isEmpty && filteredSampleTrails.isEmpty {
                            emptyStateView
                        } else {
                            // Section 1: Private Drafts (if any)
                            if !filteredDrafts.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Private Drafts (\(filteredDrafts.count))")
                                        .font(AppFonts.headlineSmall)
                                        .foregroundColor(AppColors.deepInk)
                                        .padding(.horizontal, 20)

                                    ForEach(filteredDrafts) { draft in
                                        trailCard(draft, isDraft: true)
                                    }
                                }
                            }

                            // Section 2: Saved Trails (Local on device)
                            if !filteredSavedTrails.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Saved Trails (\(filteredSavedTrails.count))")
                                        .font(AppFonts.headlineSmall)
                                        .foregroundColor(AppColors.deepInk)
                                        .padding(.horizontal, 20)

                                    ForEach(filteredSavedTrails) { trail in
                                        trailCard(trail, isDraft: false)
                                    }
                                }
                            }

                            // Section 3: Reference Sample Walk (Clearly marked sample per PRD §17)
                            if !filteredSampleTrails.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Reference Monograph")
                                            .font(AppFonts.headlineSmall)
                                            .foregroundColor(AppColors.deepInk)
                                        Spacer()
                                        Text("Sample Content")
                                            .font(AppFonts.labelSpatial)
                                            .foregroundColor(AppColors.outline)
                                    }
                                    .padding(.horizontal, 20)

                                    ForEach(filteredSampleTrails) { sample in
                                        trailCard(sample, isDraft: false, isSample: true)
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 100)
                    }
                }

                // New Recording CTA Floating Button
                Button {
                    showingScanner = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "record.circle.fill")
                            .font(.system(size: 16))
                        Text("Record New Spatial Trail")
                            .font(AppFonts.labelUI)
                    }
                    .foregroundColor(AppColors.onPrimary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
                    .shadow(color: AppColors.primaryDark.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedTrailForReview) { trail in
                ReviewPublishTrailView()
                    .onAppear {
                        dataStore.activeTrail = trail
                    }
            }
            .fullScreenCover(item: $selectedTrailForViewer) { trail in
                SpatialTrailViewerView()
                    .onAppear {
                        dataStore.activeTrail = trail
                    }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                NavigationStack {
                    ScannerView()
                }
            }
            .alert("Delete Trail?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let t = trailToDelete {
                        dataStore.deleteTrail(id: t.id)
                    }
                    trailToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    trailToDelete = nil
                }
            } message: {
                Text("“\(trailToDelete?.title ?? "This trail")” and its on-device capture files will be permanently removed.")
            }
            .onAppear {
                dataStore.reloadFromDisk()
            }
        }
    }

    // MARK: - Trail Card View

    private func trailCard(_ trail: TrailDetail, isDraft: Bool, isSample: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trail.title)
                        .font(AppFonts.headlineMedium)
                        .foregroundColor(AppColors.deepInk)

                    Text("\(trail.placeName) · \(trail.floorTitle)")
                        .font(AppFonts.bodySmall)
                        .foregroundColor(AppColors.outline)
                }

                Spacer()

                if isDraft {
                    Text("DRAFT")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.terracotta)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.terracotta.opacity(0.12))
                        .clipShape(Capsule())
                } else if isSample {
                    Text("SAMPLE")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.outline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.surfaceContainerHigh)
                        .clipShape(Capsule())
                } else {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.primary)
                }
            }

            HStack(spacing: 12) {
                Label("\(trail.distanceMeters)m", systemImage: "figure.walk")
                    .font(AppFonts.labelSpatial)
                Label("\(trail.moments.count) moments", systemImage: "flag.fill")
                    .font(AppFonts.labelSpatial)
                Label(trail.meshDensity, systemImage: "square.3.layers.3d.down.right")
                    .font(AppFonts.labelSpatial)
            }
            .foregroundColor(AppColors.onSurfaceVariant)

            HStack(spacing: 10) {
                Button {
                    selectedTrailForViewer = trail
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "view.3d")
                        Text("3D Replay")
                    }
                    .font(AppFonts.labelUI)
                    .foregroundColor(AppColors.onPrimary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
                }

                Button {
                    selectedTrailForReview = trail
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                        Text("Details")
                    }
                    .font(AppFonts.labelUI)
                    .foregroundColor(AppColors.deepInk)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(AppColors.surfaceContainerHigh)
                    .clipShape(Capsule())
                }

                Spacer()

                if !isSample {
                    Button {
                        trailToDelete = trail
                        showingDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.outline)
                            .padding(10)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(AppColors.pureWhite)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
        .padding(.horizontal, 20)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 48))
                .foregroundColor(AppColors.outline.opacity(0.6))
                .padding(.top, 40)

            Text("No Saved Trails Yet")
                .font(AppFonts.headlineLarge)
                .foregroundColor(AppColors.deepInk)

            Text("Walk an indoor space and capture your path, structure, and moments.")
                .font(AppFonts.bodyMedium)
                .foregroundColor(AppColors.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showingScanner = true
            } label: {
                Text("Start First Recording")
                    .font(AppFonts.labelUI)
                    .foregroundColor(AppColors.onPrimary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
