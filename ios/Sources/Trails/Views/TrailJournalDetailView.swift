//
//  TrailJournalDetailView.swift
//  Trails
//
//  Saved Trail Monograph Journal View.
//  Faithfully implements docs/stitch/v0.2.0/your_saved_trail_haveli_journal
//  compliant with PRD v0.2.0 §10, §11, and v0.2.1.
//

import SwiftUI
import AVKit

public struct TrailJournalDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var dataStore = TrailsDataStore.shared
    @StateObject private var audioManager = AudioManager.shared

    let trail: TrailDetail

    // Revisit & Presentation Replay
    @State private var showingRevisitReplay: Bool = false
    @State private var showingRetraceView: Bool = false
    @State private var selectedLinkedTrail: TrailDetail? = nil
    @State private var showingStartingPointPanoViewer: Bool = false

    // Media Viewer Sheets
    @State private var selectedPhotoURL: URL?
    @State private var selectedPhotoTitle: String = ""
    @State private var selectedVideoURL: URL?

    // Audio Playback state
    @State private var currentlyPlayingAudioId: String? = nil
    @State private var footsteps: [SIMD3<Float>] = []

    // Overflow & Management actions
    @State private var showingActionSheet: Bool = false
    @State private var showingEditSheet: Bool = false
    @State private var showingDeleteAlert: Bool = false

    // Photo & Video Memories Carousel
    @State private var currentMediaIndex: Int = 0

    // Edit fields
    @State private var editTitle: String = ""
    @State private var editNotes: String = ""

    public init(trail: TrailDetail) {
        self.trail = trail
        _editTitle = State(initialValue: trail.title)
        _editNotes = State(initialValue: trail.personalNotes)
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppColors.canvas
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        // MARK: - 1. Hero Cover Card
                        heroCoverCard

                        // MARK: - 2. Title & Curatorial Attribution
                        titleAndAttributionSection

                        // MARK: - 2.5 Retrace Provenance Card (if this is a retraced walk)
                        if trail.isRetrace {
                            retraceProvenanceCard
                        }

                        // MARK: - 3. Author's Personal Notes Callout
                        if !trail.personalNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            authorNotesCallout(trail.personalNotes)
                        } else {
                            authorNotesCallout("A few details I didn’t want to forget.")
                        }

                        // MARK: - 4. RoomPlan Spatial Route Map Card
                        roomPlanRoutePreviewCard

                        // MARK: - 4.5 Starting Point & Reference Frame Card
                        startingPointReferenceCard

                        // MARK: - 5. Primary Revisit Trail CTA Button
                        revisitTrailCTAButton

                        // MARK: - 6. Narrative Timeline: Moments Along This Trail
                        narrativeTimelineSection

                        // MARK: - 6.5 Retrace Walks & Replays (if this is an original reference trail)
                        if !trail.isRetrace {
                            retraceHistorySection
                        }

                        // MARK: - 7. End of Journal Entry Divider
                        journalConcludedMarker

                        // MARK: - 8. Bottom Trail Management Actions
                        bottomManagementActions

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Haptics.light()
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 15, weight: .semibold))
                            Text("My Trails")
                                .font(AppFonts.labelUI)
                        }
                        .foregroundColor(AppColors.primary)
                    }
                }

                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .clipShape(Circle())
                        Text(trail.isRetrace ? "Retraced Trail Record" : "Your Saved Trail")
                            .font(AppFonts.headlineSmall)
                            .foregroundColor(AppColors.primary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        // Share
                        ShareLink(
                            item: "Trail: \(trail.title)\n\(trail.subtitle)\nRecorded on Trails iOS",
                            subject: Text(trail.title)
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16))
                                .foregroundColor(AppColors.primary)
                        }

                        // More options
                        Button {
                            Haptics.light()
                            showingActionSheet = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16))
                                .foregroundColor(AppColors.primary)
                                .frame(width: 32, height: 32)
                                .background(AppColors.surfaceContainerLow)
                                .clipShape(Circle())
                        }
                    }
                }
            }
            // Fullscreen Linked Trail Detail View
            .fullScreenCover(item: $selectedLinkedTrail) { linkedTrail in
                TrailJournalDetailView(trail: linkedTrail)
            }
            // Fullscreen Revisit Spatial Memory Replay
            .fullScreenCover(isPresented: $showingRevisitReplay) {
                SpatialTrailViewerView()
                    .onAppear {
                        dataStore.activeTrail = trail
                    }
            }
            // Fullscreen Retrace Live Companion
            .fullScreenCover(isPresented: $showingRetraceView) {
                RetraceTrailView(referenceTrail: trail)
            }
            // Photo Viewer Sheet
            .sheet(item: Binding<IdentifiableURL?>(
                get: { selectedPhotoURL.map { IdentifiableURL(url: $0) } },
                set: { selectedPhotoURL = $0?.url }
            )) { item in
                FullScreenPhotoViewerSheet(photoURL: item.url, title: selectedPhotoTitle)
            }
            // Video Player Sheet
            .sheet(item: Binding<IdentifiableURL?>(
                get: { selectedVideoURL.map { IdentifiableURL(url: $0) } },
                set: { selectedVideoURL = $0?.url }
            )) { item in
                FullScreenVideoPlayerSheet(videoURL: item.url)
            }
            // Edit Details Sheet
            .sheet(isPresented: $showingEditSheet) {
                editTrailDetailsSheet
            }
            // Starting Point & 360 Reference Frame Sheet
            .sheet(isPresented: $showingStartingPointPanoViewer) {
                StartingPointPanoViewerSheet(trail: trail)
            }
            // Action Menu Confirmation Dialog
            .confirmationDialog("Trail Options", isPresented: $showingActionSheet, titleVisibility: .visible) {
                Button("Edit Details") {
                    editTitle = trail.title
                    editNotes = trail.personalNotes
                    showingEditSheet = true
                }
                Button("Delete from iPhone", role: .destructive) {
                    showingDeleteAlert = true
                }
                Button("Cancel", role: .cancel) {}
            }
            // Delete Trail Confirmation Alert
            .alert("Delete Trail?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    Haptics.heavy()
                    dataStore.deleteTrail(id: trail.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Permanently delete “\(trail.title)” and its \(trail.moments.count) recorded moments from this device? This cannot be undone.")
            }
            .onAppear {
                let loaded = TrailPackageStore.shared.loadFootsteps(for: trail.id)
                if !loaded.isEmpty {
                    footsteps = loaded
                } else {
                    footsteps = trail.moments.map { m in
                        SIMD3<Float>(Float(m.positionX / 24.0), Float((m.positionZ ?? 0) / 24.0), Float(m.positionY / 24.0))
                    }
                }
            }
            .onDisappear {
                audioManager.stopPlayback()
            }
        }
    }

    // MARK: - 1. Hero Cover Card: Photo Memories & Video Carousel

    private var mediaMoments: [SpatialMoment] {
        trail.moments.filter { m in
            ((m.hasPhoto || m.mediaType == "photo") && m.resolvedPhotoURL(trailId: trail.id, fallbackTrailId: trail.inspiredByTrailId) != nil)
            || ((m.hasVideo || m.mediaType == "video") && (m.resolvedVideoURL(trailId: trail.id, fallbackTrailId: trail.inspiredByTrailId) != nil || m.resolvedVideoThumbnailURL(trailId: trail.id, fallbackTrailId: trail.inspiredByTrailId) != nil))
        }
    }

    private var heroCoverCard: some View {
        ZStack(alignment: .bottomLeading) {
            if !mediaMoments.isEmpty {
                // Interactive Photo & Video Memories Carousel
                TabView(selection: $currentMediaIndex) {
                    ForEach(Array(mediaMoments.enumerated()), id: \.element.id) { index, moment in
                        ZStack(alignment: .center) {
                            if moment.hasVideo || moment.mediaType == "video" {
                                if let thumbURL = moment.resolvedVideoThumbnailURL(trailId: trail.id, fallbackTrailId: trail.inspiredByTrailId),
                                   let uiImage = UIImage(contentsOfFile: thumbURL.path) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 260)
                                        .clipped()
                                } else {
                                    ZStack {
                                        AppColors.primary
                                        Image(systemName: "video.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(AppColors.secondary.opacity(0.8))
                                    }
                                    .frame(height: 260)
                                }

                                // Play button overlay
                                Circle()
                                    .fill(AppColors.pureWhite.opacity(0.88))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(AppColors.primary)
                                            .offset(x: 1.5)
                                    )
                                    .shadow(color: Color.black.opacity(0.25), radius: 6)
                            } else {
                                if let photoURL = moment.resolvedPhotoURL(trailId: trail.id, fallbackTrailId: trail.inspiredByTrailId),
                                   let uiImage = UIImage(contentsOfFile: photoURL.path) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 260)
                                        .clipped()
                                } else {
                                    ZStack {
                                        AppColors.primary
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(AppColors.secondary.opacity(0.8))
                                    }
                                    .frame(height: 260)
                                }
                            }
                        }
                        .tag(index)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Haptics.selection()
                            if moment.hasVideo || moment.mediaType == "video" {
                                if let videoURL = moment.resolvedVideoURL(trailId: trail.id, fallbackTrailId: trail.inspiredByTrailId) {
                                    selectedVideoURL = videoURL
                                }
                            } else if let photoURL = moment.resolvedPhotoURL(trailId: trail.id, fallbackTrailId: trail.inspiredByTrailId) {
                                selectedPhotoURL = photoURL
                                selectedPhotoTitle = moment.title
                            }
                        }
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .frame(height: 260)
            } else {
                // Authentic Cartographic Spatial Header (Zero fake stock photos)
                ZStack {
                    LinearGradient(
                        colors: [AppColors.primary, AppColors.forestGreen],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(AppColors.secondary.opacity(0.18))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                    .font(.system(size: 22))
                                    .foregroundColor(AppColors.secondary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(trail.placeName)
                                    .font(AppFonts.headlineLarge)
                                    .foregroundColor(AppColors.pureWhite)
                                Text("Spatial Footprint · \(trail.floorCode)")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.secondary)
                            }
                        }

                        HStack(spacing: 14) {
                            Label("\(trail.distanceMeters)m Path", systemImage: "figure.walk")
                            Label("\(trail.moments.count) Stops", systemImage: "mappin.and.ellipse")
                            Label(trail.createdAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        }
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.pureWhite.opacity(0.9))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .padding(20)
                }
                .frame(height: 260)
            }

            // Dark gradient scrim for legibility
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.3), Color.black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            // Top Status & Counter Strip
            VStack {
                HStack {
                    if trail.isRetrace {
                        HStack(spacing: 6) {
                            Image(systemName: "figure.walk.motion")
                                .font(.system(size: 11, weight: .bold))
                            Text("RETRACE")
                                .font(AppFonts.labelSpatial)
                                .tracking(1.0)
                            if let sim = trail.retraceSimilarityIndex {
                                Text("· \(Int(sim * 100))% MATCH")
                                    .font(AppFonts.labelSpatial)
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: "#00838F"))
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                    } else {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(AppColors.primary)
                                .frame(width: 7, height: 7)
                            Text("SAVED ON THIS IPHONE")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.primary)
                                .tracking(1.0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.92))
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                    }

                    Spacer()

                    if mediaMoments.count > 1 {
                        HStack(spacing: 4) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 11))
                            Text("\(currentMediaIndex + 1) / \(mediaMoments.count)")
                                .font(AppFonts.labelSpatial)
                        }
                        .foregroundColor(AppColors.pureWhite)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                    }
                }
                .padding(14)

                Spacer()

                // Bottom Metadata Strip
                HStack(alignment: .bottom) {
                    if !mediaMoments.isEmpty, currentMediaIndex < mediaMoments.count {
                        let activeMoment = mediaMoments[currentMediaIndex]
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Image(systemName: activeMoment.hasVideo || activeMoment.mediaType == "video" ? "video.fill" : "camera.fill")
                                    .font(.system(size: 11))
                                Text("Stop \(activeMoment.index) · \(activeMoment.title)")
                                    .font(AppFonts.labelUI)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(AppColors.pureWhite)
                            .lineLimit(1)

                            if !activeMoment.subtitle.isEmpty {
                                Text(activeMoment.subtitle)
                                    .font(AppFonts.caption)
                                    .foregroundColor(AppColors.pureWhite.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                    } else {
                        Text("ID · \(trail.id.prefix(8).uppercased())")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    if mediaMoments.count > 1 {
                        HStack(spacing: 5) {
                            ForEach(0..<mediaMoments.count, id: \.self) { idx in
                                Circle()
                                    .fill(idx == currentMediaIndex ? AppColors.pureWhite : AppColors.pureWhite.opacity(0.4))
                                    .frame(width: idx == currentMediaIndex ? 7 : 5, height: idx == currentMediaIndex ? 7 : 5)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Capsule())
                    } else {
                        Text("\(trail.moments.count) Moments Recorded")
                            .font(AppFonts.labelMetric)
                            .foregroundColor(.white.opacity(0.95))
                    }
                }
                .padding(14)
            }
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    // MARK: - 2. Title & Attribution

    private var titleAndAttributionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(trail.title)
                .font(AppFonts.displayLargeMobile)
                .foregroundColor(AppColors.primary)
                .tracking(-0.5)
                .lineLimit(3)

            HStack(spacing: 8) {
                Text("A trail by \(trail.authorName.isEmpty ? "You" : trail.authorName)")
                    .font(AppFonts.labelUI)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.primary)

                Text("•")
                    .foregroundColor(AppColors.outlineVariant)

                Text(trail.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(AppColors.onSurfaceVariant)

                if !trail.wing.isEmpty {
                    Text("•")
                        .foregroundColor(AppColors.outlineVariant)
                    Text(trail.wing)
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.onSurfaceVariant)
                }
            }
        }
    }

    // MARK: - 2.5 Retrace Provenance Card

    private var retraceProvenanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#00838F").opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: "figure.walk.motion")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "#00838F"))
                }

                Text("RETRACED TRAIL RECORD")
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(Color(hex: "#00838F"))
                    .tracking(1.0)

                Spacer()

                if let sim = trail.retraceSimilarityIndex {
                    Text("\(Int(sim * 100))% MATCH")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: "#00838F"))
                        .clipShape(Capsule())
                }
            }

            if let refTitle = trail.retraceReferenceTrailTitle {
                Text("Retraced from “\(refTitle)”")
                    .font(AppFonts.headlineSmall)
                    .foregroundColor(AppColors.deepInk)
            }

            Text("Recorded on \(trail.createdAt.formatted(date: .abbreviated, time: .shortened)) by \(trail.authorName.isEmpty ? "You" : trail.authorName). This is a verified walk recorded on its own merit with \(trail.distanceMeters)m of physical tracking and \(trail.moments.count) checkpoints.")
                .font(AppFonts.bodySmall)
                .foregroundColor(AppColors.onSurfaceVariant)

            if let refId = trail.inspiredByTrailId,
               let originalTrail = dataStore.savedTrails.first(where: { $0.id == refId }) ?? dataStore.sampleTrails.first(where: { $0.id == refId }) {
                Button {
                    Haptics.selection()
                    selectedLinkedTrail = originalTrail
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                        Text("View Original Reference Trail")
                            .font(AppFonts.labelSpatial)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#00838F"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color(hex: "#00838F").opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color(hex: "#00838F").opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(hex: "#00838F").opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - 3. Author Notes Callout

    private func authorNotesCallout(_ notes: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("“")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundColor(AppColors.secondary)
                .offset(y: -4)

            Text(notes)
                .font(AppFonts.headlineMedium)
                .italic()
                .foregroundColor(AppColors.onSurfaceVariant)
                .lineSpacing(4)

            Spacer()
        }
        .padding(16)
        .background(AppColors.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 2)
    }

    // MARK: - 4. RoomPlan Spatial Route Card

    private var roomPlanRoutePreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.secondary)
                    Text("ROOMPLAN SPATIAL ROUTE")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.secondary)
                        .tracking(1.5)
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(AppColors.forestGreen)
                        .frame(width: 6, height: 6)
                    Text("LiDAR 6DOF")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.outline)
                }
            }

            Button {
                Haptics.medium()
                showingRevisitReplay = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    RoomLayoutView(
                        capturedRoom: nil,
                        footsteps: footsteps,
                        moments: trail.moments
                    )
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(AppColors.outlineVariant.opacity(0.3), lineWidth: 1)
                    )

                    // Floating Inspection Pill
                    HStack(spacing: 8) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 13, weight: .bold))
                        Text("Explore 3D Replay")
                            .font(AppFonts.labelSpatial)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
                    .padding(14)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 4.5 Starting Point & Reference Frame Card

    private var startingPointReferenceCard: some View {
        let startPhotoURL = trail.resolvedStartFrameURL(fallbackTrailId: trail.inspiredByTrailId)
        let heading = trail.startHeadingDegrees ?? trail.moments.first?.headingDegrees ?? 0.0

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#00838F").opacity(0.18))
                            .frame(width: 28, height: 28)
                        Image(systemName: "figure.walk.arrival")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "#00838F"))
                    }

                    Text("STARTING POINT & REFERENCE FRAME")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(Color(hex: "#00838F"))
                        .tracking(1.0)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "safari.fill")
                        .font(.system(size: 11))
                    Text("Facing \(Int(heading))°")
                        .font(AppFonts.labelSpatial)
                }
                .foregroundColor(Color(hex: "#00838F"))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(hex: "#00838F").opacity(0.12))
                .clipShape(Capsule())
            }

            // Image Preview (Interactive tap opens 360 / Reference Frame Viewer)
            Button {
                Haptics.light()
                showingStartingPointPanoViewer = true
            } label: {
                ZStack(alignment: .bottomLeading) {
                    if let url = startPhotoURL, let uiImage = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .clipped()
                    } else if let asset = trail.moments.first?.photoAssetName, let uiImage = UIImage(named: asset) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .clipped()
                    } else {
                        ZStack {
                            Color(hex: "#101622")
                            VStack(spacing: 6) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 32))
                                    .foregroundColor(AppColors.outline)
                                Text("Starting Vantage Photo")
                                    .font(AppFonts.caption)
                                    .foregroundColor(AppColors.secondary)
                            }
                        }
                        .frame(height: 180)
                    }

                    // Scrim
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Starting Origin Landmark")
                                .font(AppFonts.headlineSmall)
                                .foregroundColor(.white)
                            Text("Stand here facing \(Int(heading))° to align before retracing")
                                .font(AppFonts.caption)
                                .foregroundColor(Color.white.opacity(0.85))
                        }

                        Spacer()

                        HStack(spacing: 5) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 12))
                            Text("Explore Vantage")
                                .font(AppFonts.labelSpatial)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                    }
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(16)
        .background(AppColors.pureWhite)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    // MARK: - 4. Retrace & Revisit CTAs (PRD v0.3.0)

    private var revisitTrailCTAButton: some View {
        VStack(spacing: 10) {
            // Primary: Retrace Trail (Walk along with live guidance)
            Button {
                Haptics.medium()
                showingRetraceView = true
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#00E5FF").opacity(0.2))
                            .frame(width: 32, height: 32)
                        Image(systemName: "figure.walk.motion")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(hex: "#00E5FF"))
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Retrace this trail")
                            .font(AppFonts.headlineSmall)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text("Follow along with turn guidance & comparison")
                            .font(AppFonts.caption)
                            .foregroundColor(Color.white.opacity(0.75))
                    }

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(AppColors.primary)
                .clipShape(Capsule())
                .shadow(color: AppColors.primary.opacity(0.25), radius: 8, x: 0, y: 4)
            }

            // Secondary: Explore 3D Virtual Replay
            Button {
                Haptics.light()
                showingRevisitReplay = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Explore 3D Virtual Replay")
                        .font(AppFonts.labelUI)
                        .fontWeight(.medium)
                }
                .foregroundColor(AppColors.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(AppColors.surfaceContainerLow)
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - 5. Narrative Timeline Section

    private var narrativeTimelineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(AppColors.secondary)
                        .frame(width: 8, height: 8)
                    Text("Moments along this trail")
                        .font(AppFonts.headlineSmall)
                        .foregroundColor(AppColors.primary)
                }

                Spacer()

                Text("\(trail.moments.count) STOPS")
                    .font(AppFonts.labelMetric)
                    .foregroundColor(AppColors.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColors.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.top, 8)

            // Timeline Items with Vertical Thread
            VStack(spacing: 0) {
                ForEach(trail.moments) { moment in
                    timelineMomentItem(moment, isLast: moment.id == trail.moments.last?.id)
                }
            }
        }
    }

    // MARK: - Timeline Item Container

    private func timelineMomentItem(_ moment: SpatialMoment, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Vertical Thread & Node
            VStack(spacing: 0) {
                // Waypoint Ring
                ZStack {
                    Circle()
                        .fill(AppColors.canvas)
                        .frame(width: 20, height: 20)
                    Circle()
                        .fill(AppColors.secondary)
                        .frame(width: 10, height: 10)
                }
                .padding(.top, 22)

                // Connecting Line
                if !isLast {
                    Rectangle()
                        .fill(AppColors.surfaceContainerHighest)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 20)

            // Moment Card
            momentContentCard(moment)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Moment Card Dispatcher

    @ViewBuilder
    private func momentContentCard(_ moment: SpatialMoment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Moment Header Bar
            HStack {
                Text(momentBadgeLabel(for: moment))
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(AppColors.secondary)
                    .tracking(1.0)
                    .textCase(.uppercase)

                Spacer()

                Image(systemName: momentIconName(for: moment))
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.outline)
            }

            // Photo Moment
            if moment.hasPhoto || moment.mediaType == "photo" {
                photoMomentView(moment)
            }

            // Video Moment
            if moment.hasVideo || moment.mediaType == "video" {
                videoMomentView(moment)
            }

            // Audio Moment
            if moment.hasAudio || moment.mediaType == "voice" {
                audioMomentView(moment)
            }

            // Title & Narrative
            VStack(alignment: .leading, spacing: 4) {
                Text("\(moment.index). \(moment.title)")
                    .font(AppFonts.headlineSmall)
                    .foregroundColor(AppColors.primary)

                if !moment.narrative.isEmpty {
                    Text(moment.narrative)
                        .font(AppFonts.bodyMedium)
                        .foregroundColor(AppColors.onSurfaceVariant)
                        .lineSpacing(3)
                }
            }

            // Architectural / Field Note
            if !moment.architecturalNote.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.secondary)
                    Text(moment.architecturalNote)
                        .font(AppFonts.bodySmall)
                        .italic()
                        .foregroundColor(AppColors.outline)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.surfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(AppColors.pureWhite)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
    }

    // MARK: - Photo Moment

    private func photoMomentView(_ moment: SpatialMoment) -> some View {
        Button {
            if let url = moment.resolvedPhotoURL(trailId: trail.id, fallbackTrailId: trail.inspiredByTrailId) {
                Haptics.light()
                selectedPhotoTitle = moment.title
                selectedPhotoURL = url
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let photoURL = moment.resolvedPhotoURL(trailId: trail.id, fallbackTrailId: trail.inspiredByTrailId),
                   let uiImage = UIImage(contentsOfFile: photoURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipped()
                } else if let assetName = moment.photoAssetName, !assetName.isEmpty {
                    Image(assetName)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(AppColors.surfaceContainer)
                        .frame(height: 180)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 32))
                                .foregroundColor(AppColors.outline)
                        )
                }

                // Expand icon badge
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Circle())
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Video Moment

    private func videoMomentView(_ moment: SpatialMoment) -> some View {
        Button {
            if let videoURL = moment.resolvedVideoURL(trailId: trail.id, fallbackTrailId: trail.inspiredByTrailId) {
                Haptics.light()
                selectedVideoURL = videoURL
            }
        } label: {
            ZStack {
                if let thumbURL = moment.resolvedVideoThumbnailURL(trailId: trail.id, fallbackTrailId: trail.inspiredByTrailId),
                   let thumbImage = UIImage(contentsOfFile: thumbURL.path) {
                    Image(uiImage: thumbImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 180)
                        .clipped()
                } else if let assetName = moment.videoThumbnailAssetName, !assetName.isEmpty {
                    Image(assetName)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 180)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.85))
                        .frame(height: 180)
                }

                // Play Button Overlay
                Circle()
                    .fill(Color.black.opacity(0.65))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .offset(x: 2)
                    )

                // Duration badge
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(moment.videoDuration ?? "00:10")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Capsule())
                            .padding(8)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Audio Moment

    private func audioMomentView(_ moment: SpatialMoment) -> some View {
        let isThisPlaying = currentlyPlayingAudioId == moment.id && audioManager.isPlaying

        return HStack(spacing: 12) {
            // Play/Pause button
            Button {
                Haptics.light()
                if isThisPlaying {
                    audioManager.stopPlayback()
                    currentlyPlayingAudioId = nil
                } else {
                    if let url = moment.resolvedAudioURL(trailId: trail.id) {
                        currentlyPlayingAudioId = moment.id
                        audioManager.playAudio(url: url)
                    }
                }
            } label: {
                Circle()
                    .fill(AppColors.primary)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .offset(x: isThisPlaying ? 0 : 1)
                    )
            }

            // Waveform visualizer
            HStack(spacing: 3) {
                ForEach(0..<18, id: \.self) { barIndex in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isThisPlaying ? AppColors.primary : AppColors.primary.opacity(0.35))
                        .frame(
                            width: 3,
                            height: isThisPlaying
                                ? CGFloat(8 + ((barIndex * 7) % 24))
                                : CGFloat(6 + ((barIndex * 3) % 16))
                        )
                        .animation(
                            isThisPlaying
                                ? .easeInOut(duration: 0.25).repeatForever().delay(Double(barIndex) * 0.03)
                                : .default,
                            value: isThisPlaying
                        )
                }
            }
            .frame(height: 32)

            Spacer()

            // Sample rate / duration
            VStack(alignment: .trailing, spacing: 2) {
                Text(moment.audioDuration ?? "0:24")
                    .font(AppFonts.labelMetric)
                    .foregroundColor(AppColors.primary)
                Text("48 kHz")
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(AppColors.outline)
            }
        }
        .padding(10)
        .background(AppColors.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 6.5 Retrace Walks & Replays

    private var retraceHistorySection: some View {
        let completedRetraces = dataStore.savedTrails.filter { $0.inspiredByTrailId == trail.id }
        let retraceSessions = TrailPackageStore.shared.loadRetraceSessions(for: trail.id)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: "#00838F"))
                        .frame(width: 8, height: 8)
                    Text("Retrace Walks & Replays")
                        .font(AppFonts.headlineSmall)
                        .foregroundColor(AppColors.primary)
                }

                Spacer()

                Text("\(max(completedRetraces.count, retraceSessions.count)) Recorded")
                    .font(AppFonts.labelMetric)
                    .foregroundColor(Color(hex: "#00838F"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: "#00838F").opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.top, 8)

            if completedRetraces.isEmpty && retraceSessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "figure.walk.motion")
                        .font(.system(size: 26))
                        .foregroundColor(AppColors.outline)
                    Text("No retraced walks recorded yet")
                        .font(AppFonts.headlineSmall)
                        .foregroundColor(AppColors.onSurfaceVariant)
                    Text("Walk this trail using “Retrace this trail” above to document your own walk on its own merit.")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(AppColors.surfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                VStack(spacing: 10) {
                    ForEach(completedRetraces) { retraceTrail in
                        Button {
                            Haptics.selection()
                            selectedLinkedTrail = retraceTrail
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: "#00838F").opacity(0.15))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "figure.walk.motion")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(Color(hex: "#00838F"))
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(retraceTrail.title)
                                            .font(AppFonts.headlineSmall)
                                            .foregroundColor(AppColors.deepInk)
                                            .lineLimit(1)

                                        if let sim = retraceTrail.retraceSimilarityIndex {
                                            Text("\(Int(sim * 100))% MATCH")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color(hex: "#00838F"))
                                                .clipShape(Capsule())
                                        }
                                    }

                                    Text("\(retraceTrail.distanceMeters)m · By \(retraceTrail.authorName) · \(retraceTrail.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(AppFonts.caption)
                                        .foregroundColor(AppColors.secondary)
                                }

                                Spacer()

                                HStack(spacing: 4) {
                                    Text("View")
                                        .font(AppFonts.labelSpatial)
                                        .foregroundColor(Color(hex: "#00838F"))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Color(hex: "#00838F"))
                                }
                            }
                            .padding(14)
                            .background(AppColors.surfaceContainerLow)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: - 7. End of Entry Divider

    private var journalConcludedMarker: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(AppColors.outlineVariant)
                .frame(height: 1)
            Text("JOURNAL ENTRY CONCLUDED")
                .font(AppFonts.labelSpatial)
                .foregroundColor(AppColors.outline)
                .tracking(1.5)
            Rectangle()
                .fill(AppColors.outlineVariant)
                .frame(height: 1)
        }
        .padding(.vertical, 16)
        .opacity(0.7)
    }

    // MARK: - 7. Bottom Management Actions

    private var bottomManagementActions: some View {
        VStack(spacing: 12) {
            Button {
                Haptics.light()
                editTitle = trail.title
                editNotes = trail.personalNotes
                showingEditSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15))
                    Text("Edit trail details")
                        .font(AppFonts.labelUI)
                        .fontWeight(.medium)
                }
                .foregroundColor(AppColors.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(AppColors.surfaceContainer)
                .clipShape(Capsule())
            }

            Button {
                Haptics.light()
                showingDeleteAlert = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                    Text("Delete local trail from this device")
                        .font(AppFonts.labelSpatial)
                        .underline()
                }
                .foregroundColor(AppColors.outline)
                .padding(.vertical, 8)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Edit Sheet

    private var editTrailDetailsSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Trail Title")) {
                    TextField("Title", text: $editTitle)
                        .font(AppFonts.bodyMedium)
                }

                Section(header: Text("Field Notes / Reflection")) {
                    TextEditor(text: $editNotes)
                        .frame(minHeight: 100)
                        .font(AppFonts.bodyMedium)
                }
            }
            .navigationTitle("Edit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingEditSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Haptics.success()
                        var updated = trail
                        updated.title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? trail.title : editTitle
                        updated.personalNotes = editNotes
                        dataStore.updateTrail(trail: updated)
                        showingEditSheet = false
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func momentBadgeLabel(for moment: SpatialMoment) -> String {
        switch moment.mediaType {
        case "photo": return "Spatial Photo · Stop \(moment.index)"
        case "video": return "Spatial Video · Stop \(moment.index)"
        case "voice": return "Ambient Field Audio"
        default: return "Field Observation"
        }
    }

    private func momentIconName(for moment: SpatialMoment) -> String {
        switch moment.mediaType {
        case "photo": return "camera.fill"
        case "video": return "video.fill"
        case "voice": return "waveform"
        default: return "pencil.line"
        }
    }
}

// MARK: - Identifiable URL Helper

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Starting Point & 360 Reference Frame Pano Viewer

private struct StartingPointPanoViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let trail: TrailDetail
    @StateObject private var locationManager = TrailsLocationManager()

    @State private var dragOffset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero

    private var targetHeading: Double {
        trail.startHeadingDegrees ?? trail.moments.first?.headingDegrees ?? 0.0
    }

    private var currentHeading: Double {
        locationManager.currentHeading ?? 0.0
    }

    private var headingDelta: Double {
        var diff = targetHeading - currentHeading
        while diff > 180 { diff -= 360 }
        while diff < -180 { diff += 360 }
        return diff
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Bar
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Circle())
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("ORIGIN REFERENCE VANTAGE")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(Color(hex: "#00E5FF"))
                                .tracking(1.2)
                            if trail.isStartingFramePano == true {
                                Text("360° PANO")
                                    .font(.system(size: 8, weight: .black, design: .rounded))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color(hex: "#00E5FF"))
                                    .clipShape(Capsule())
                            }
                        }

                        Text(trail.title)
                            .font(AppFonts.headlineSmall)
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                // Immersive Panoramic / Frame Viewport
                ZStack {
                    if let url = trail.resolvedStartFrameURL(fallbackTrailId: trail.inspiredByTrailId),
                       let uiImage = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .offset(x: accumulatedOffset.width + dragOffset.width)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .gesture(
                                DragGesture()
                                    .onChanged { val in dragOffset = val.translation }
                                    .onEnded { val in
                                        accumulatedOffset.width += val.translation.width
                                        dragOffset = .zero
                                    }
                            )
                    } else if let asset = trail.moments.first?.photoAssetName, let uiImage = UIImage(named: asset) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .offset(x: accumulatedOffset.width + dragOffset.width)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 48))
                                .foregroundColor(Color(hex: "#00E5FF"))
                            Text("No starting reference frame recorded")
                                .font(AppFonts.headlineSmall)
                                .foregroundColor(.white)
                        }
                    }

                    // Scrims
                    LinearGradient(
                        colors: [Color.black.opacity(0.5), Color.clear, Color.black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)

                    // Pan Hint Overlay
                    VStack {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.draw")
                                .font(.system(size: 11))
                            Text("Drag horizontally to inspect surrounding vantage")
                                .font(AppFonts.labelSpatial)
                        }
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .padding(.top, 14)

                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom Compass & Physical Orientation Navigation Dock
                VStack(spacing: 12) {
                    HStack(spacing: 14) {
                        // Dynamic Compass Dial
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 2)
                                .frame(width: 52, height: 52)

                            Image(systemName: "location.north.line.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(abs(headingDelta) < 15 ? Color(hex: "#00E5FF") : Color.orange)
                                .rotationEffect(Angle(degrees: headingDelta))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(abs(headingDelta) < 15 ? Color.green : Color.orange)
                                    .frame(width: 7, height: 7)
                                Text("TARGET HEADING · \(Int(targetHeading))°")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(abs(headingDelta) < 15 ? Color.green : Color.orange)
                            }

                            if abs(headingDelta) < 15 {
                                Text("Facing starting vantage point ✓")
                                    .font(AppFonts.headlineSmall)
                                    .foregroundColor(.white)
                            } else {
                                Text("Turn \(Int(abs(headingDelta)))° \(headingDelta > 0 ? "Right" : "Left") to align")
                                    .font(AppFonts.headlineSmall)
                                    .foregroundColor(.white)
                            }

                            Text("Stand at this physical location and face \(Int(targetHeading))° before beginning your retrace.")
                                .font(AppFonts.caption)
                                .foregroundColor(Color.white.opacity(0.75))
                        }

                        Spacer()
                    }
                }
                .padding(18)
                .background(Color(hex: "#101622"))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            locationManager.requestAccessIfNeeded()
        }
    }
}
