//
//  ScannerView.swift
//  Trails
//
//  Screen 4: Active Capture & Tracking (PRD v0.2.0 §7.3, §8.1-8.3 & docs/stitch/v0.2.0/leave_a_moment_active_capture).
//  Combines camera feed with live 2D minimap, real-time footstep vectors,
//  multi-media spatial moment tagging (Photo, Video, Voice, Note), and curatorial prompts.
//

import SwiftUI
import RoomPlan

struct ScannerView: View {
    @StateObject private var scannerEngine = RoomScannerEngine()
    @Environment(\.dismiss) private var dismiss

    // Capture sheet & modal states
    @State private var activeMomentMode: MomentMode? = nil
    @State private var showingReviewSheet = false
    @State private var showingCancelConfirm = false
    @State private var showCuratorialPrompt = true
    @State private var toastMessage: String? = nil
    @State private var toastCoordinates: String? = nil

    // Field inputs
    @State private var momentLabel = ""
    @State private var momentNote = ""
    @State private var selectedPhotoAsset: String = "SandstoneArchway"
    @State private var voiceDurationLabel = "0:12"

    // Timers
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?

    enum MomentMode: Identifiable {
        case photo
        case video
        case voice
        case note

        var id: Int { hashValue }
    }

    private var walkedMeters: Int {
        max(1, Int(Float(scannerEngine.footsteps.count) * 0.2))
    }

    private var formattedTime: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        ZStack {
            // Main Viewport Stack
            VStack(spacing: 0) {
                // Top: Camera Feed / Simulated Perspective Viewport
                ZStack {
                    if scannerEngine.isSupported {
                        RoomCameraView(engine: scannerEngine)
                    } else {
                        SimulatedViewportView(footstepsCount: scannerEngine.footsteps.count)
                    }

                    // Top Navigation Chrome Overlay
                    topNavigationOverlay
                }
                .frame(height: UIScreen.main.bounds.height * 0.36)
                .ignoresSafeArea(edges: .top)

                // Middle: Architectural Minimap (Top-down 2D layout)
                ZStack(alignment: .topLeading) {
                    RoomLayoutView(
                        capturedRoom: scannerEngine.capturedRoom,
                        footsteps: scannerEngine.footsteps,
                        moments: scannerEngine.recordedMoments
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Spatial status flag
                    HStack(spacing: 6) {
                        Circle()
                            .fill(scannerEngine.isSimulated ? AppColors.mutedBrass : AppColors.terracotta)
                            .frame(width: 6, height: 6)
                        Text(scannerEngine.isSimulated ? "SIMULATED VECTOR" : "LIDAR ROOMPLAN")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppColors.surfaceContainerLowest.opacity(0.92))
                    .clipShape(Capsule())
                    .padding(12)
                }

                // Bottom: Tactile "Leave a Moment" Capture Sheet
                tactileCaptureSheet
            }
            .background(AppColors.canvas.ignoresSafeArea())

            // Transient Toast Overlay
            if let toast = toastMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppColors.mutedBrass)
                        Text(toast)
                            .font(AppFonts.labelUI)
                            .foregroundColor(AppColors.pureWhite)
                        Spacer()
                        if let coords = toastCoordinates {
                            Text(coords)
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.pureWhite.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(AppColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 240)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut(duration: 0.22), value: toastMessage)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            startCaptureSession()
        }
        .onDisappear {
            stopCaptureSession()
        }
        // Sub-sheets for Photo, Video, Voice, and Note
        .sheet(item: $activeMomentMode) { mode in
            switch mode {
            case .photo:
                PhotoMomentSheet(
                    selectedAsset: $selectedPhotoAsset,
                    caption: $momentNote,
                    onSave: { assetName, caption in
                        savePhotoMoment(assetName: assetName, note: caption)
                        activeMomentMode = nil
                    },
                    onCancel: {
                        activeMomentMode = nil
                    }
                )
                .presentationDetents([.fraction(0.55), .large])

            case .video:
                VideoMomentSheet(
                    onSave: { dur, caption in
                        saveVideoMoment(duration: dur, note: caption)
                        activeMomentMode = nil
                    },
                    onCancel: {
                        activeMomentMode = nil
                    }
                )
                .presentationDetents([.fraction(0.62), .large])

            case .voice:
                VoiceMomentSheet(
                    onSave: { durationLabel, note in
                        saveVoiceMoment(duration: durationLabel, note: note)
                        activeMomentMode = nil
                    },
                    onCancel: {
                        activeMomentMode = nil
                    }
                )
                .presentationDetents([.fraction(0.48)])

            case .note:
                NoteMomentSheet(
                    label: $momentLabel,
                    note: $momentNote,
                    onSave: { lbl, nt in
                        saveNoteMoment(label: lbl, note: nt)
                        activeMomentMode = nil
                    },
                    onCancel: {
                        activeMomentMode = nil
                    }
                )
                .presentationDetents([.fraction(0.45)])
            }
        }
        .sheet(isPresented: $showingReviewSheet, onDismiss: {
            dismiss()
        }) {
            ReviewPublishTrailView()
        }
        .confirmationDialog(
            "Discard this recording?",
            isPresented: $showingCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard & Exit to My Trails", role: .destructive) {
                stopCaptureSession()
                dismiss()
            }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("Your recorded footsteps and checkpoints will not be preserved.")
        }
    }

    // MARK: - Top Navigation Overlay

    private var topNavigationOverlay: some View {
        VStack {
            HStack {
                // Close / Cancel Button
                Button {
                    Haptics.light()
                    handleClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .accessibilityLabel("Close recording")
                .accessibilityIdentifier("scanner.close")

                Spacer()

                // Active Trail Recording Pill (Matching Stitch HUD)
                HStack(spacing: 8) {
                    Circle()
                        .fill(AppColors.terracotta)
                        .frame(width: 8, height: 8)

                    Text("RECORDING TRAIL")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(.white)

                    Text("· \(walkedMeters) m")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(Color.white.opacity(0.75))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.55))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))

                Spacer()

                // Safe Finish Trail CTA
                Button {
                    Haptics.success()
                    finishScan()
                } label: {
                    HStack(spacing: 6) {
                        Text("Finish trail")
                            .font(AppFonts.labelUI)
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(AppColors.onPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
                    .shadow(color: AppColors.primary.opacity(0.35), radius: 6, x: 0, y: 3)
                }
                .accessibilityIdentifier("scanner.finish")
            }
            .padding(.horizontal, 16)
            .padding(.top, 48)

            Spacer()
        }
    }

    // MARK: - Tactile Bottom Capture Sheet (docs/stitch/v0.2.0/leave_a_moment_active_capture)

    private var tactileCaptureSheet: some View {
        VStack(spacing: 10) {
            // Drag Handle Bar
            Capsule()
                .fill(AppColors.onSurfaceVariant.opacity(0.25))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            // Sheet Header Narrative
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Leave a moment")
                            .font(AppFonts.headlineLarge)
                            .foregroundColor(AppColors.primary)

                        Text("Anchor 0\(scannerEngine.recordedMoments.count + 1)")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.terracotta)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(AppColors.surfaceContainerHigh)
                            .clipShape(Capsule())
                    }

                    Text("Something you noticed. Something worth keeping.")
                        .font(AppFonts.bodySmall)
                        .foregroundColor(AppColors.onSurfaceVariant)
                }

                Spacer()
            }
            .padding(.horizontal, 20)

            // Curatorial Provocation Prompt Card (Dismissible)
            if showCuratorialPrompt {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AppColors.mutedBrass)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("CURATORIAL PROMPT")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.mutedBrass)

                        Text("“What would you show someone who wasn’t here?”")
                            .font(.custom("Newsreader", size: 14))
                            .italic()
                            .foregroundColor(AppColors.primary)
                    }

                    Spacer()

                    Button {
                        Haptics.light()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCuratorialPrompt = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppColors.onSurfaceVariant)
                            .padding(4)
                    }
                }
                .padding(10)
                .background(AppColors.surfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            // Tactile Capture Action Bar (Photo, Video, Voice, Note)
            HStack(spacing: 8) {
                // 1. Photo Capture Button
                momentActionButton(
                    icon: "camera.fill",
                    title: "Photo",
                    subtitle: "FRAME",
                    iconColor: AppColors.onPrimary,
                    bgColor: AppColors.primary
                ) {
                    Haptics.light()
                    momentNote = ""
                    activeMomentMode = .photo
                }

                // 2. Video Capture Button (v0.2.0 Video Support)
                momentActionButton(
                    icon: "video.fill",
                    title: "Video",
                    subtitle: "SPATIAL",
                    iconColor: AppColors.pureWhite,
                    bgColor: AppColors.terracotta
                ) {
                    Haptics.light()
                    momentNote = ""
                    activeMomentMode = .video
                }

                // 3. Voice Capture Button
                momentActionButton(
                    icon: "mic.fill",
                    title: "Voice",
                    subtitle: "AUDIO",
                    iconColor: AppColors.primary,
                    bgColor: AppColors.mutedBrass
                ) {
                    Haptics.light()
                    momentNote = ""
                    activeMomentMode = .voice
                }

                // 4. Note Capture Button
                momentActionButton(
                    icon: "note.text",
                    title: "Note",
                    subtitle: "ESSAY",
                    iconColor: AppColors.primary,
                    bgColor: AppColors.surfaceContainerHighest
                ) {
                    Haptics.light()
                    momentLabel = ""
                    momentNote = ""
                    activeMomentMode = .note
                }
            }
            .padding(.horizontal, 16)

            // Dynamic Status Drawer
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(AppColors.forestGreen)
                        .frame(width: 6, height: 6)
                    Text("Saved locally to current path")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.onSurfaceVariant)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "sensor.fill")
                        .font(.system(size: 11))
                    Text(scannerEngine.isSimulated ? "Simulation Sync" : "LiDAR Synced")
                        .font(AppFonts.labelSpatial)
                }
                .foregroundColor(AppColors.onSurfaceVariant)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .background(
            AppColors.surfaceContainerLowest
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: AppColors.primary.opacity(0.08), radius: 24, x: 0, y: -8)
        )
    }

    private func momentActionButton(
        icon: String,
        title: String,
        subtitle: String,
        iconColor: Color,
        bgColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Circle()
                    .fill(bgColor)
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 17))
                            .foregroundColor(iconColor)
                    )

                Text(title)
                    .font(AppFonts.headlineSmall)
                    .foregroundColor(AppColors.primary)

                Text(subtitle)
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(AppColors.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(AppColors.surfaceContainer)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Save Moment Helpers

    private func savePhotoMoment(assetName: String, note: String) {
        let label = note.isEmpty ? "Visual Frame \(scannerEngine.recordedMoments.count + 1)" : note
        scannerEngine.addMoment(
            label: label,
            note: note,
            mediaType: "photo",
            hasPhoto: true,
            photoAssetName: assetName
        )
        triggerToast(message: "Photo frame anchored in place")
    }

    private func saveVideoMoment(duration: String, note: String) {
        let label = note.isEmpty ? "Spatial Video \(scannerEngine.recordedMoments.count + 1)" : note
        scannerEngine.addMoment(
            label: label,
            note: note.isEmpty ? "1.5x Spatial Video clip recorded at 60fps." : note,
            mediaType: "video",
            hasPhoto: true,
            photoAssetName: "DhunHaveliEvening",
            hasVideo: true,
            videoDuration: duration,
            videoThumbnailAssetName: "DhunHaveliEvening"
        )
        triggerToast(message: "Video clip anchored in place")
    }

    private func saveVoiceMoment(duration: String, note: String) {
        let label = note.isEmpty ? "Spoken Observation \(scannerEngine.recordedMoments.count + 1)" : note
        scannerEngine.addMoment(
            label: label,
            note: note.isEmpty ? "Spoken audio observation recorded in-situ." : note,
            mediaType: "voice",
            hasAudio: true,
            audioDuration: duration
        )
        triggerToast(message: "Voice note anchored to vector")
    }

    private func saveNoteMoment(label: String, note: String) {
        let safeLabel = label.isEmpty ? "Observation \(scannerEngine.recordedMoments.count + 1)" : label
        scannerEngine.addMoment(
            label: safeLabel,
            note: note,
            mediaType: "note"
        )
        triggerToast(message: "Draft impression anchored in place")
    }

    private func triggerToast(message: String) {
        Haptics.success()
        let pos = scannerEngine.lastRecordedPosition ?? SIMD3<Float>(0, 0, 0)
        toastCoordinates = String(format: "x: %.1f · z: %.1f", pos.x, pos.z)
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation {
                toastMessage = nil
                toastCoordinates = nil
            }
        }
    }

    // MARK: - Control Logic

    private func handleClose() {
        if scannerEngine.footsteps.count > 3 || !scannerEngine.recordedMoments.isEmpty {
            showingCancelConfirm = true
        } else {
            stopCaptureSession()
            dismiss()
        }
    }

    private func startCaptureSession() {
        scannerEngine.startScanning()
        elapsedSeconds = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedSeconds += 1
        }
    }

    private func stopCaptureSession() {
        timer?.invalidate()
        timer = nil
        scannerEngine.stopScanning()
    }

    private func finishScan() {
        stopCaptureSession()

        let author = TrailsDataStore.shared.localProfile.displayName
        let activePlace = TrailsDataStore.shared.places.first(where: { $0.id == "dhun-haveli" })
        let trail = TrailDetail(
            id: UUID().uuidString,
            title: "Haveli Walk \(Date().formatted(.dateTime.hour().minute()))",
            subtitle: "\(walkedMeters)m recorded path",
            placeId: activePlace?.id ?? "dhun-haveli",
            placeName: activePlace?.name ?? "Dhun Haveli",
            locality: activePlace?.locality ?? "Jaipur, Rajasthan",
            wing: "Ground Floor",
            authorName: author.isEmpty ? "Hiro" : author,
            authorRole: "Spatial Explorer",
            distanceMeters: walkedMeters,
            floorCode: "LVL 00",
            floorTitle: "Ground Floor",
            meshDensity: "\(scannerEngine.capturedRoom?.walls.count ?? 4) walls detected",
            samplingFrequency: "24.6 kHz",
            nodeCount: max(1, scannerEngine.footsteps.count),
            personalNotes: "Saved privately on this iPhone. Trails does not upload this capture.",
            moments: scannerEngine.recordedMoments,
            visibility: .privateDraft,
            isDraft: true,
            coverImageName: "DhunHaveliEvening"
        )

        TrailsDataStore.shared.saveDraft(trail: trail, footsteps: scannerEngine.footsteps)
        showingReviewSheet = true
    }
}

// MARK: - Video Moment Sheet (PRD v0.2.0 Video Moment Support)

private struct VideoMomentSheet: View {
    @State private var isRecording = false
    @State private var recordedSeconds = 0
    @State private var timer: Timer?
    @State private var caption: String = ""

    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    private var durationString: String {
        let m = recordedSeconds / 60
        let s = recordedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "video.fill")
                            .foregroundColor(AppColors.terracotta)
                        Text("Capture Spatial Video")
                            .font(AppFonts.headlineMedium)
                            .foregroundColor(AppColors.primary)
                    }
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .font(AppFonts.bodyMedium)
                        .foregroundColor(AppColors.onSurfaceVariant)
                }

                // Video Viewport / Recorder Card
                ZStack {
                    Image("DhunHaveliEvening")
                        .resizable()
                        .scaledToFill()
                        .frame(height: 160)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .cornerRadius(16)
                        .overlay(Color.black.opacity(isRecording ? 0.25 : 0.45))

                    VStack {
                        // Top specs badge
                        HStack {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(isRecording ? AppColors.terracotta : AppColors.mutedBrass)
                                    .frame(width: 7, height: 7)
                                Text(isRecording ? "RECORDING · 60 FPS" : "1.5x SPATIAL VIDEO")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Capsule())

                            Spacer()

                            Text(durationString)
                                .font(AppFonts.labelMetric)
                                .foregroundColor(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.65))
                                .clipShape(Capsule())
                        }
                        .padding(12)

                        Spacer()

                        // Record / Stop Button
                        Button {
                            toggleRecording()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 58, height: 58)

                                if isRecording {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(AppColors.terracotta)
                                        .frame(width: 24, height: 24)
                                } else {
                                    Circle()
                                        .fill(AppColors.terracotta)
                                        .frame(width: 46, height: 46)
                                }
                            }
                            .shadow(color: Color.black.opacity(0.3), radius: 6)
                        }
                        .padding(.bottom, 12)
                    }
                }
                .frame(height: 160)

                VStack(alignment: .leading, spacing: 6) {
                    Text("SPATIAL OBSERVATION / NOTE")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.outline)

                    TextField("e.g. Iron pivot hinge rotation & dusk courtyard breeze", text: $caption)
                        .font(AppFonts.bodyMedium)
                        .padding(14)
                        .background(AppColors.surfaceContainerLow)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                }

                Spacer()

                Button {
                    let dur = recordedSeconds > 0 ? durationString : "0:24"
                    onSave(dur, caption)
                } label: {
                    Text("Save Video Moment")
                        .font(AppFonts.labelUI)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AppColors.primary)
                        .clipShape(Capsule())
                }
            }
            .padding(20)
            .background(AppColors.canvas.ignoresSafeArea())
        }
    }

    private func toggleRecording() {
        Haptics.selection()
        if isRecording {
            isRecording = false
            timer?.invalidate()
            timer = nil
        } else {
            isRecording = true
            recordedSeconds = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                recordedSeconds += 1
            }
        }
    }
}

// MARK: - Photo Moment Sheet

private struct PhotoMomentSheet: View {
    @Binding var selectedAsset: String
    @Binding var caption: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Capture Visual Frame")
                        .font(AppFonts.headlineMedium)
                        .foregroundColor(AppColors.primary)
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .font(AppFonts.bodyMedium)
                        .foregroundColor(AppColors.onSurfaceVariant)
                }

                // Photo Preview Carousel
                HStack(spacing: 12) {
                    photoOption(title: "Archway Lintel", assetName: "SandstoneArchway")
                    photoOption(title: "Haveli Courtyard", assetName: "DhunHaveliEvening")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("OBSERVATION / CAPTION")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.outline)

                    TextField("e.g. Hand-chiseled sandstone archway in evening light", text: $caption)
                        .font(AppFonts.bodyMedium)
                        .padding(14)
                        .background(AppColors.surfaceContainerLow)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                }

                Spacer()

                Button {
                    onSave(selectedAsset, caption)
                } label: {
                    Text("Save Photo Moment")
                        .font(AppFonts.labelUI)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AppColors.primary)
                        .clipShape(Capsule())
                }
            }
            .padding(20)
            .background(AppColors.canvas.ignoresSafeArea())
        }
    }

    private func photoOption(title: String, assetName: String) -> some View {
        Button {
            selectedAsset = assetName
        } label: {
            VStack(spacing: 6) {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selectedAsset == assetName ? AppColors.terracotta : Color.clear, lineWidth: 3)
                    )

                Text(title)
                    .font(AppFonts.caption)
                    .foregroundColor(selectedAsset == assetName ? AppColors.primary : AppColors.onSurfaceVariant)
                    .fontWeight(selectedAsset == assetName ? .semibold : .regular)
            }
        }
    }
}

// MARK: - Voice Moment Sheet

private struct VoiceMomentSheet: View {
    @State private var isRecording = false
    @State private var recordedSeconds = 0
    @State private var timer: Timer?
    @State private var note: String = ""

    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    private var durationString: String {
        let m = recordedSeconds / 60
        let s = recordedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Record Spoken Observation")
                    .font(AppFonts.headlineMedium)
                    .foregroundColor(AppColors.primary)
                Spacer()
                Button("Cancel", action: onCancel)
                    .font(AppFonts.bodyMedium)
                    .foregroundColor(AppColors.onSurfaceVariant)
            }

            // Mic Record Pulse
            VStack(spacing: 12) {
                Button {
                    toggleRecording()
                } label: {
                    ZStack {
                        Circle()
                            .fill(isRecording ? AppColors.terracotta.opacity(0.2) : AppColors.surfaceContainerHigh)
                            .frame(width: 80, height: 80)
                            .scaleEffect(isRecording ? 1.15 : 1.0)
                            .animation(isRecording ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: isRecording)

                        Circle()
                            .fill(isRecording ? AppColors.terracotta : AppColors.primary)
                            .frame(width: 60, height: 60)

                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                }

                Text(durationString)
                    .font(AppFonts.labelMetric)
                    .foregroundColor(isRecording ? AppColors.terracotta : AppColors.primary)

                Text(isRecording ? "Recording in 48kHz Spatial Audio..." : "Tap mic to begin speaking")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.onSurfaceVariant)
            }
            .padding(.vertical, 8)

            TextField("Observation topic (optional)", text: $note)
                .font(AppFonts.bodyMedium)
                .padding(14)
                .background(AppColors.surfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer()

            Button {
                let duration = recordedSeconds > 0 ? durationString : "0:14"
                onSave(duration, note)
            } label: {
                Text("Save Voice Moment")
                    .font(AppFonts.labelUI)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
            }
        }
        .padding(20)
        .background(AppColors.canvas.ignoresSafeArea())
    }

    private func toggleRecording() {
        Haptics.selection()
        if isRecording {
            isRecording = false
            timer?.invalidate()
            timer = nil
        } else {
            isRecording = true
            recordedSeconds = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                recordedSeconds += 1
            }
        }
    }
}

// MARK: - Note Moment Sheet

private struct NoteMomentSheet: View {
    @Binding var label: String
    @Binding var note: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Tag Moment Along Trail")
                    .font(AppFonts.headlineMedium)
                    .foregroundColor(AppColors.primary)
                Spacer()
                Button("Cancel", action: onCancel)
                    .font(AppFonts.bodyMedium)
                    .foregroundColor(AppColors.onSurfaceVariant)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("MOMENT LABEL")
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(AppColors.outline)

                TextField("e.g. Carved Stone Lintel", text: $label)
                    .font(AppFonts.bodyMedium)
                    .padding(14)
                    .background(AppColors.surfaceContainerLow)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("OBSERVATION / NOTE")
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(AppColors.outline)

                TextField("e.g. Morning breeze draws upward through archway", text: $note)
                    .font(AppFonts.bodyMedium)
                    .padding(14)
                    .background(AppColors.surfaceContainerLow)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Spacer()

            Button {
                onSave(label, note)
            } label: {
                Text("Save Moment")
                    .font(AppFonts.labelUI)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(label.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.5) : AppColors.primary)
                    .clipShape(Capsule())
            }
            .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(20)
        .background(AppColors.canvas.ignoresSafeArea())
    }
}

// MARK: - Simulated Spatial Viewport (For Simulator & Non-LiDAR Devices)

private struct SimulatedViewportView: View {
    let footstepsCount: Int

    var body: some View {
        ZStack {
            Color(hex: "#05070A")

            VStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundColor(AppColors.mutedBrass.opacity(0.8))

                VStack(spacing: 4) {
                    Text("SPATIAL CAPTURE INSTRUMENT")
                        .font(AppFonts.labelSpatial)
                        .tracking(1.8)
                        .foregroundColor(AppColors.mutedBrass)

                    Text("LiDAR & RoomPlan Active")
                        .font(AppFonts.headlineSmall)
                        .foregroundColor(.white)

                    Text("Walking path and floorplan are updating in real-time below.")
                        .font(AppFonts.bodySmall)
                        .foregroundColor(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
    }
}

// MARK: - Button Style Helper

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
