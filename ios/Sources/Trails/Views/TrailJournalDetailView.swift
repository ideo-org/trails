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

                        // MARK: - 3. Author's Personal Notes Callout
                        if !trail.personalNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            authorNotesCallout(trail.personalNotes)
                        } else {
                            authorNotesCallout("A few details I didn’t want to forget.")
                        }

                        // MARK: - 4. RoomPlan Spatial Route Map Card
                        roomPlanRoutePreviewCard

                        // MARK: - 5. Primary Revisit Trail CTA Button
                        revisitTrailCTAButton

                        // MARK: - 6. Narrative Timeline: Moments Along This Trail
                        narrativeTimelineSection

                        // MARK: - 6. End of Journal Entry Divider
                        journalConcludedMarker

                        // MARK: - 7. Bottom Trail Management Actions
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
                        Text("Your Saved Trail")
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
            // Fullscreen Revisit Spatial Memory Replay
            .fullScreenCover(isPresented: $showingRevisitReplay) {
                SpatialTrailViewerView()
                    .onAppear {
                        dataStore.activeTrail = trail
                    }
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

    // MARK: - 1. Hero Cover Card

    private var heroCoverCard: some View {
        ZStack(alignment: .bottomLeading) {
            // Background Image
            if let firstPhoto = trail.moments.first(where: { $0.hasPhoto }),
               let photoURL = firstPhoto.resolvedPhotoURL(trailId: trail.id),
               let uiImage = UIImage(contentsOfFile: photoURL.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 260)
                    .clipped()
            } else if let assetName = trail.coverImageName, !assetName.isEmpty {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 260)
                    .clipped()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [AppColors.primary, AppColors.forestGreen],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack(spacing: 8) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 38))
                            .foregroundColor(AppColors.secondary)
                        Text(trail.placeName)
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .frame(height: 260)
            }

            // Dark gradient scrim for legibility
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.3), Color.black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Top Status Chip
            VStack {
                HStack {
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

                    Spacer()
                }
                .padding(14)

                Spacer()

                // Bottom Metadata Strip
                HStack {
                    Text("ID · \(trail.id.prefix(8).uppercased())")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Capsule())

                    Spacer()

                    Text("\(trail.moments.count) Moments Recorded")
                        .font(AppFonts.labelMetric)
                        .foregroundColor(.white.opacity(0.95))
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

    // MARK: - 4. Revisit Trail CTA

    private var revisitTrailCTAButton: some View {
        Button {
            Haptics.medium()
            showingRevisitReplay = true
        } label: {
            HStack(spacing: 10) {
                Text("Revisit trail")
                    .font(AppFonts.headlineSmall)
                    .fontWeight(.semibold)

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(AppColors.primary)
            .clipShape(Capsule())
            .shadow(color: AppColors.primary.opacity(0.2), radius: 8, x: 0, y: 4)
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
            if let url = moment.resolvedPhotoURL(trailId: trail.id) {
                Haptics.light()
                selectedPhotoTitle = moment.title
                selectedPhotoURL = url
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let photoURL = moment.resolvedPhotoURL(trailId: trail.id),
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
            if let videoURL = moment.resolvedVideoURL(trailId: trail.id) {
                Haptics.light()
                selectedVideoURL = videoURL
            }
        } label: {
            ZStack {
                if let thumbURL = moment.resolvedVideoThumbnailURL(trailId: trail.id),
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

    // MARK: - 6. End of Entry Divider

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
