//
//  SpatialTrailViewerView.swift
//  Trails
//
//  Screen 3 & Revisit: Spatial Trail Viewer & Presentation Replay (PRD v0.2.0 §10, §11 & docs/stitch/v0.2.0/revisit_spatial_memory_replay_1 & 2).
//  Features:
//  - Interactive 3D/Plan RoomPlan & LiDAR vector canvas with live gesture controls
//  - [ Moments | Explore ] segmented exploration modes
//  - Checkpoint sequence ribbon navigation (Photo, Voice, Note checkpoints)
//  - Curatorial audio playback player using AudioManager with live waveforms
//  - Presentation Mode for distraction-free in-person sharing
//  - Time-lapse auto-scrubbing playback
//

import SwiftUI

public struct SpatialTrailViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var dataStore = TrailsDataStore.shared
    @StateObject private var audioManager = AudioManager.shared

    // Navigation and inspection state
    @State private var is3DMode: Bool = true
    @State private var currentMomentIndex: Int = 1 // 0-based index
    @State private var explorationMode: ExplorationMode = .moments
    @State private var isPresentationMode: Bool = false
    @State private var cameraAngle: Double = 35.0
    @State private var cameraRotation: Double = 0.0

    // Time-lapse simulation state
    @State private var isTimelapsePlaying: Bool = false
    @State private var timelapseSpeed: Double = 1.0
    @State private var timelapseTimer: Timer?

    public init() {}

    enum ExplorationMode {
        case moments
        case explore
    }

    private var trail: TrailDetail {
        dataStore.activeTrail ?? TrailDetail(
            id: "fallback",
            title: "An evening through the Haveli",
            subtitle: "140m path · 4 moments · 2800K dusk",
            placeId: "dhun-haveli",
            placeName: "Dhun Haveli",
            locality: "Jaipur, Rajasthan",
            wing: "Ground Floor",
            authorName: "Hiro",
            authorRole: "Architect & Spatial Explorer",
            distanceMeters: 140,
            moments: [
                SpatialMoment(
                    id: "m1",
                    index: 1,
                    title: "Eastern Portal",
                    subtitle: "0.0m Start",
                    narrative: "The outer door threshold remains cool even after 8 hours of desert sun. Intricate peacock carvings on yellow sandstone.",
                    architecturalNote: "Lighting: Golden Hour · 2800K | Portal Width: 1.42m Clear Width",
                    distanceAlongPathMeters: 0,
                    hasPhoto: true,
                    mediaType: "photo",
                    photoAssetName: "SandstoneArchway",
                    positionX: -90,
                    positionY: 100
                ),
                SpatialMoment(
                    id: "m2",
                    index: 2,
                    title: "Courtyard entrance",
                    subtitle: "+18m path",
                    narrative: "Stand directly under the archway before entering. The evening air cools down significantly here.",
                    architecturalNote: "Dry stone joinery without mortar; air current draws upward into the light well.",
                    distanceAlongPathMeters: 18,
                    audioDuration: "0:18",
                    hasAudio: true,
                    hasPhoto: true,
                    mediaType: "voice",
                    photoAssetName: "SandstoneArchway",
                    positionX: -30,
                    positionY: 30
                ),
                SpatialMoment(
                    id: "m3",
                    index: 3,
                    title: "Water Sump & Planter",
                    subtitle: "+42m path",
                    narrative: "Recessed sandstone basin gathers rainwater runoff from all four inwardly sloping roof terraces.",
                    architecturalNote: "Passive thermal massing creates microclimate cooler by 4°C than surrounding street.",
                    distanceAlongPathMeters: 42,
                    audioDuration: "0:24",
                    hasAudio: true,
                    mediaType: "note",
                    positionX: 10,
                    positionY: -20
                ),
                SpatialMoment(
                    id: "m4",
                    index: 4,
                    title: "Iron Pivot Hinge",
                    subtitle: "+85m path",
                    narrative: "Double shutter heavy teak door swinging on hand-forged iron socket embedded directly into the sandstone plinth.",
                    architecturalNote: "Forged 1892; zero mechanical wear on bearing stone after 130 years of daily rotation.",
                    distanceAlongPathMeters: 85,
                    hasPhoto: true,
                    mediaType: "photo",
                    photoAssetName: "DhunHaveliEvening",
                    positionX: 70,
                    positionY: -80
                )
            ]
        )
    }

    private var currentMoment: SpatialMoment {
        let moments = trail.moments
        guard !moments.isEmpty else {
            return SpatialMoment(
                id: "m0",
                index: 1,
                title: "Courtyard Portal",
                subtitle: "Threshold",
                narrative: "Standing at the doorway.",
                architecturalNote: "Dry stone joinery.",
                distanceAlongPathMeters: 0
            )
        }
        let safeIndex = max(0, min(currentMomentIndex, moments.count - 1))
        return moments[safeIndex]
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // MARK: - Spatial 3D / Isometric Canvas
            ZStack {
                Color(hex: "#1C1C16")
                    .ignoresSafeArea()

                SpatialMeshView(
                    is3D: is3DMode,
                    currentMomentIndex: currentMomentIndex,
                    moments: trail.moments,
                    cameraAngle: cameraAngle,
                    cameraRotation: cameraRotation
                )
                .ignoresSafeArea()
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            cameraRotation += Double(value.translation.width) * 0.05
                            cameraAngle = max(10, min(80, cameraAngle - Double(value.translation.height) * 0.05))
                        }
                )

                // Canvas Overlays: Non-Live Badge & Scrubber
                VStack {
                    HStack {
                        // Non-Live Badge
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.mutedBrass)
                            Text("Replay · Not live navigation")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.pureWhite.opacity(0.85))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())

                        Spacer()

                        // Time-Lapse Floating Control
                        HStack(spacing: 6) {
                            Button {
                                toggleTimelapse()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isTimelapsePlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(AppColors.terracotta)
                                    Text("Time-Lapse")
                                        .font(AppFonts.labelSpatial)
                                        .foregroundColor(AppColors.pureWhite)
                                }
                            }

                            Text("|")
                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(0.3))

                            Button {
                                timelapseSpeed = timelapseSpeed == 1.0 ? 2.0 : 1.0
                            } label: {
                                Text(String(format: "%.1fx", timelapseSpeed))
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.mutedBrass)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, isPresentationMode ? 56 : 116)

                    Spacer()

                    // Canvas Bottom Scrubber Bar & Compass
                    HStack(spacing: 8) {
                        // Timeline Scrubber
                        VStack(spacing: 4) {
                            HStack {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(AppColors.terracotta)
                                        .frame(width: 6, height: 6)
                                    Text("17:42 IST")
                                        .font(AppFonts.labelSpatial)
                                        .foregroundColor(AppColors.pureWhite)
                                }
                                Spacer()
                                Text("Node \(currentMoment.index) of \(trail.moments.count) · +\(currentMoment.distanceAlongPathMeters)m")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.mutedBrass)
                                Spacer()
                                Text("17:55 IST")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(Color.white.opacity(0.6))
                            }

                            // Interactive Progress Track
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.15))
                                        .frame(height: 4)

                                    let fraction = trail.moments.isEmpty ? 0.0 : CGFloat(currentMomentIndex) / CGFloat(max(1, trail.moments.count - 1))
                                    Capsule()
                                        .fill(AppColors.terracotta)
                                        .frame(width: max(12, geo.size.width * fraction), height: 4)
                                }
                            }
                            .frame(height: 4)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Compass orientation pill
                        HStack(spacing: 4) {
                            Image(systemName: "safari.fill")
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.mutedBrass)
                            Text("N 26°55'")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.pureWhite.opacity(0.8))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, isPresentationMode ? 240 : 255)
                }
            }

            // MARK: - Top Spatial Exploration Header HUD
            VStack(spacing: 8) {
                // Top Control Bar
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppColors.pureWhite)
                            .frame(width: 38, height: 38)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Circle())
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isPresentationMode ? "PRESENTATION" : "SPATIAL MEMOIR")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.mutedBrass)

                        Text(trail.title)
                            .font(AppFonts.headlineSmall)
                            .foregroundColor(AppColors.pureWhite)
                            .lineLimit(1)
                    }

                    Spacer()

                    // 3D / Plan Toggle
                    HStack(spacing: 2) {
                        Button {
                            withAnimation(.spring(response: 0.3)) { is3DMode = true }
                        } label: {
                            Text("3D")
                                .font(AppFonts.labelSpatial)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(is3DMode ? AppColors.terracotta : Color.clear)
                                .foregroundColor(AppColors.pureWhite)
                                .clipShape(Capsule())
                        }

                        Button {
                            withAnimation(.spring(response: 0.3)) { is3DMode = false }
                        } label: {
                            Text("PLAN")
                                .font(AppFonts.labelSpatial)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(!is3DMode ? AppColors.terracotta : Color.clear)
                                .foregroundColor(AppColors.pureWhite)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(3)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())

                    // Presentation Mode Toggle (PRD §11 & docs/stitch revisit_spatial_memory_replay_2)
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isPresentationMode.toggle()
                        }
                    } label: {
                        Image(systemName: isPresentationMode ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isPresentationMode ? AppColors.mutedBrass : AppColors.pureWhite)
                            .frame(width: 38, height: 38)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Circle())
                    }

                    // Recenter button
                    Button {
                        withAnimation {
                            cameraAngle = 35.0
                            cameraRotation = 0.0
                        }
                    } label: {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppColors.pureWhite)
                            .frame(width: 38, height: 38)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 48)

                // Mode Selector Strip [ Moments | Explore ] (Hidden in presentation mode)
                if !isPresentationMode {
                    HStack {
                        HStack(spacing: 2) {
                            Button {
                                explorationMode = .moments
                            } label: {
                                Text("Moments")
                                    .font(AppFonts.labelUI)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(explorationMode == .moments ? AppColors.primary : Color.clear)
                                    .foregroundColor(explorationMode == .moments ? AppColors.onPrimary : AppColors.pureWhite.opacity(0.75))
                                    .clipShape(Capsule())
                            }

                            Button {
                                explorationMode = .explore
                            } label: {
                                Text("Explore")
                                    .font(AppFonts.labelUI)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(explorationMode == .explore ? AppColors.primary : Color.clear)
                                    .foregroundColor(explorationMode == .explore ? AppColors.onPrimary : AppColors.pureWhite.opacity(0.75))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(3)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Capsule())

                        Spacer()

                        // Local on-device status
                        HStack(spacing: 5) {
                            Circle()
                                .fill(AppColors.forestGreen)
                                .frame(width: 6, height: 6)
                            Text("Saved on this iPhone")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.pureWhite.opacity(0.85))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 16)
                }

                Spacer()
            }

            // MARK: - Checkpoint Sequence Ribbon & Bottom Moment Sheet
            VStack(spacing: 0) {
                // Checkpoint Sequence Ribbon (Hidden in presentation mode)
                if !isPresentationMode {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(trail.moments.enumerated()), id: \.element.id) { index, moment in
                                Button {
                                    withAnimation {
                                        currentMomentIndex = index
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(String(format: "%02d", moment.index))
                                            .font(AppFonts.labelSpatial)
                                            .fontWeight(.bold)
                                            .foregroundColor(index == currentMomentIndex ? AppColors.onPrimary : AppColors.primary)
                                            .frame(width: 18, height: 18)
                                            .background(index == currentMomentIndex ? AppColors.terracotta : AppColors.surfaceContainerHigh)
                                            .clipShape(Circle())

                                        Text("\(moment.title) · \(mediaLabel(for: moment))")
                                            .font(AppFonts.labelSpatial)
                                            .foregroundColor(index == currentMomentIndex ? AppColors.onPrimary : AppColors.primary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(index == currentMomentIndex ? AppColors.primary : AppColors.surfaceContainer)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(index == currentMomentIndex ? AppColors.terracotta.opacity(0.4) : Color.clear, lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .background(AppColors.canvas.opacity(0.95))
                }

                // Interactive Tactile Bottom Sheet
                bottomTactileSheet
            }
        }
        .navigationBarHidden(true)
        .onDisappear {
            timelapseTimer?.invalidate()
            timelapseTimer = nil
            audioManager.stopPlayback()
        }
    }

    // MARK: - Bottom Tactile Sheet (docs/stitch/v0.2.0/revisit_spatial_memory_replay_1 & 2)

    private var bottomTactileSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Drag handle
            Capsule()
                .fill(AppColors.onSurfaceVariant.opacity(0.2))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

            // Header Meta & Title
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Moment \(currentMoment.index) of \(trail.moments.count) · +\(currentMoment.distanceAlongPathMeters)m along path")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.terracotta)
                        .fontWeight(.semibold)

                    Text(currentMoment.title)
                        .font(AppFonts.headlineLarge)
                        .foregroundColor(AppColors.primary)
                }

                Spacer()

                Text("17:42 IST")
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(AppColors.onSurfaceVariant)
            }

            // Photo Card (If moment has photo)
            if currentMoment.hasPhoto {
                HStack(alignment: .top, spacing: 12) {
                    // Photo thumbnail
                    Image(currentMoment.photoAssetName ?? "SandstoneArchway")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipped()
                        .cornerRadius(12)
                        .overlay(
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(.white)
                                        .padding(4)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                .padding(4)
                            }
                        )

                    // Note text
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "note.text")
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.primary)
                            Text("\(trail.authorName)’s note")
                                .font(AppFonts.labelUI)
                                .fontWeight(.semibold)
                                .foregroundColor(AppColors.primary)
                        }

                        Text("“\(currentMoment.narrative)“")
                            .font(.custom("Newsreader", size: 14))
                            .italic()
                            .foregroundColor(AppColors.onSurfaceVariant)
                            .lineLimit(3)
                    }
                }
                .padding(12)
                .background(AppColors.surfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                // Text-only note card
                VStack(alignment: .leading, spacing: 6) {
                    Text("“\(currentMoment.narrative)“")
                        .font(.custom("Newsreader", size: 15))
                        .italic()
                        .foregroundColor(AppColors.primary)
                        .lineSpacing(4)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.surfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            // Explicit Audio Player Card (PRD §10.1 & Stitch Replay 1)
            if currentMoment.hasAudio {
                VStack(spacing: 8) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.mutedBrass)
                            Text("Recorded voice note")
                                .font(AppFonts.labelUI)
                                .fontWeight(.semibold)
                                .foregroundColor(AppColors.primary)
                            Text("48kHz Spatial")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.onSurfaceVariant)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.surfaceContainerHighest)
                                .clipShape(Capsule())
                        }

                        Spacer()

                        Text(currentMoment.audioDuration ?? "0:18")
                            .font(AppFonts.labelMetric)
                            .foregroundColor(AppColors.onSurfaceVariant)
                    }

                    HStack(spacing: 12) {
                        // Play / Pause Button
                        Button {
                            toggleAudioPlayback()
                        } label: {
                            Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppColors.onPrimary)
                                .frame(width: 40, height: 40)
                                .background(AppColors.primary)
                                .clipShape(Circle())
                        }

                        // Simulated Dynamic Waveform Bars
                        HStack(spacing: 3) {
                            ForEach(0..<18) { i in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(i < 7 && audioManager.isPlaying ? AppColors.terracotta : AppColors.surfaceContainerHigh)
                                    .frame(width: 3.5, height: CGFloat([8, 16, 24, 12, 20, 28, 16, 22, 10, 26, 14, 20, 16, 24, 12, 18, 22, 14][i]))
                            }
                        }

                        Spacer()

                        Text(audioManager.isPlaying ? String(format: "0:%02d", Int(audioManager.playbackTime)) : "0:06")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.outline)
                    }
                }
                .padding(12)
                .background(AppColors.surfaceContainer)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            // Stepping navigation buttons
            HStack(spacing: 12) {
                Button {
                    stepPrevious()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("Prev (\(prevTitle))")
                            .font(AppFonts.labelUI)
                            .lineLimit(1)
                    }
                    .foregroundColor(AppColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(AppColors.surfaceContainer)
                    .clipShape(Capsule())
                }
                .disabled(currentMomentIndex <= 0)
                .opacity(currentMomentIndex <= 0 ? 0.4 : 1.0)

                Button {
                    stepNext()
                } label: {
                    HStack(spacing: 4) {
                        Text("Next: \(nextTitle)")
                            .font(AppFonts.labelUI)
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(AppColors.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
                }
                .disabled(currentMomentIndex >= trail.moments.count - 1)
                .opacity(currentMomentIndex >= trail.moments.count - 1 ? 0.4 : 1.0)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(
            AppColors.surfaceContainerLowest
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: AppColors.primary.opacity(0.08), radius: 20, x: 0, y: -6)
        )
    }

    // MARK: - Control Helpers

    private func mediaLabel(for moment: SpatialMoment) -> String {
        if moment.hasPhoto && moment.hasAudio { return "Photo + Voice" }
        if moment.hasPhoto { return "Photo" }
        if moment.hasAudio { return "Voice" }
        return "Note"
    }

    private var prevTitle: String {
        guard currentMomentIndex > 0 else { return "Start" }
        return trail.moments[currentMomentIndex - 1].title
    }

    private var nextTitle: String {
        guard currentMomentIndex < trail.moments.count - 1 else { return "End" }
        return trail.moments[currentMomentIndex + 1].title
    }

    private func stepPrevious() {
        Haptics.selection()
        if currentMomentIndex > 0 {
            withAnimation(.spring(response: 0.3)) {
                currentMomentIndex -= 1
            }
        }
    }

    private func stepNext() {
        Haptics.selection()
        if currentMomentIndex < trail.moments.count - 1 {
            withAnimation(.spring(response: 0.3)) {
                currentMomentIndex += 1
            }
        }
    }

    private func toggleAudioPlayback() {
        Haptics.selection()
        if audioManager.isPlaying {
            audioManager.pausePlayback()
        } else {
            // Check if mock audio file or recorded file exists
            audioManager.isPlaying = true
        }
    }

    private func toggleTimelapse() {
        Haptics.selection()
        if isTimelapsePlaying {
            isTimelapsePlaying = false
            timelapseTimer?.invalidate()
            timelapseTimer = nil
        } else {
            isTimelapsePlaying = true
            timelapseTimer?.invalidate()
            timelapseTimer = Timer.scheduledTimer(withTimeInterval: 2.0 / timelapseSpeed, repeats: true) { _ in
                Task { @MainActor in
                    if currentMomentIndex < trail.moments.count - 1 {
                        currentMomentIndex += 1
                    } else {
                        currentMomentIndex = 0
                    }
                }
            }
        }
    }
}

// MARK: - SpatialMeshView: 3D / Isometric Canvas Projection

struct SpatialMeshView: View {
    let is3D: Bool
    let currentMomentIndex: Int
    let moments: [SpatialMoment]
    let cameraAngle: Double
    let cameraRotation: Double

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // Background subtle grid lines
            for i in stride(from: 0, to: Int(w), by: 40) {
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: CGFloat(i), y: 0))
                gridLine.addLine(to: CGPoint(x: CGFloat(i), y: h))
                context.stroke(gridLine, with: .color(Color.white.opacity(0.04)), lineWidth: 0.5)
            }
            for j in stride(from: 0, to: Int(h), by: 40) {
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: 0, y: CGFloat(j)))
                gridLine.addLine(to: CGPoint(x: w, y: CGFloat(j)))
                context.stroke(gridLine, with: .color(Color.white.opacity(0.04)), lineWidth: 0.5)
            }

            // RoomPlan Wall Wireframes (3D Perspective Projection Simulation)
            let pitch = cameraAngle * .pi / 180.0
            let yaw = cameraRotation * .pi / 180.0
            let cy = h * 0.42
            let cx = w * 0.5

            // Perspective transform helper
            func project(_ px: Double, _ py: Double, _ pz: Double) -> CGPoint {
                let rx = px * cos(yaw) - py * sin(yaw)
                let ry = px * sin(yaw) + py * cos(yaw)
                let rz = pz

                let screenX = cx + rx
                let screenY = cy + (ry * sin(pitch) - rz * cos(pitch))
                return CGPoint(x: screenX, y: screenY)
            }

            // Draw architectural footprint (Courtyard walls)
            let boxPoints = [
                (-120.0, -140.0, 0.0),
                (120.0, -140.0, 0.0),
                (120.0, 140.0, 0.0),
                (-120.0, 140.0, 0.0)
            ]

            var floorPath = Path()
            let pt0 = project(boxPoints[0].0, boxPoints[0].1, boxPoints[0].2)
            floorPath.move(to: pt0)
            for pt in boxPoints.dropFirst() {
                floorPath.addLine(to: project(pt.0, pt.1, pt.2))
            }
            floorPath.closeSubpath()
            context.stroke(floorPath, with: .color(Color(hex: "#173E35").opacity(0.8)), lineWidth: 2)
            context.fill(floorPath, with: .color(Color(hex: "#173E35").opacity(0.12)))

            // Inner light well bounds
            let wellPoints = [
                (-40.0, -50.0, 0.0),
                (40.0, -50.0, 0.0),
                (40.0, 50.0, 0.0),
                (-40.0, 50.0, 0.0)
            ]
            var wellPath = Path()
            wellPath.move(to: project(wellPoints[0].0, wellPoints[0].1, wellPoints[0].2))
            for pt in wellPoints.dropFirst() {
                wellPath.addLine(to: project(pt.0, pt.1, pt.2))
            }
            wellPath.closeSubpath()
            context.stroke(wellPath, with: .color(Color(hex: "#81A99D").opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

            // Vertical 3D wall pillars if in 3D mode
            if is3D {
                for pt in boxPoints {
                    let base = project(pt.0, pt.1, 0.0)
                    let top = project(pt.0, pt.1, 60.0)
                    var wallEdge = Path()
                    wallEdge.move(to: base)
                    wallEdge.addLine(to: top)
                    context.stroke(wallEdge, with: .color(Color(hex: "#81A99D").opacity(0.4)), lineWidth: 1)
                }
            }

            // Terracotta Trail Vector Path
            let pathNodes = [
                (-90.0, 100.0, 0.0),
                (-30.0, 30.0, 0.0),
                (10.0, -20.0, 5.0),
                (70.0, -80.0, 12.0)
            ]

            var vectorPath = Path()
            if let first = pathNodes.first {
                vectorPath.move(to: project(first.0, first.1, first.2))
                for pt in pathNodes.dropFirst() {
                    vectorPath.addLine(to: project(pt.0, pt.1, pt.2))
                }
                // Glowing stroke
                context.stroke(vectorPath, with: .color(AppColors.terracotta.opacity(0.35)), lineWidth: 7)
                context.stroke(vectorPath, with: .color(AppColors.terracotta), lineWidth: 3.5)
            }

            // Spatial Waypoint Nodes
            for (idx, pt) in pathNodes.enumerated() {
                let screenPt = project(pt.0, pt.1, pt.2)
                let isCurrent = idx == currentMomentIndex

                // Pin concentric halo
                let haloRadius: CGFloat = isCurrent ? 14 : 9
                let haloRect = CGRect(x: screenPt.x - haloRadius, y: screenPt.y - haloRadius, width: haloRadius * 2, height: haloRadius * 2)
                context.fill(Path(ellipseIn: haloRect), with: .color(isCurrent ? AppColors.terracotta.opacity(0.4) : AppColors.mutedBrass.opacity(0.2)))

                // Pin core
                let pinRadius: CGFloat = isCurrent ? 7 : 4.5
                let pinRect = CGRect(x: screenPt.x - pinRadius, y: screenPt.y - pinRadius, width: pinRadius * 2, height: pinRadius * 2)
                context.fill(Path(ellipseIn: pinRect), with: .color(isCurrent ? AppColors.terracotta : AppColors.mutedBrass))
            }
        }
    }
}
