//
//  ScannerView.swift
//  Trails
//
//  Active Capture & Journey Recording for Trails v0.2.1.
//  Implements a trail-first spatial journey architecture:
//  - Primary view is the live spatial trail & RoomPlan scan (split or full-floorplan)
//  - Tracks continuous 6DOF LiDAR footsteps & room perimeter in real-time
//  - Checkpoint stops along the trail can be documented with Video, Photo, Voice, or Notes
//  - Tapping Video/Photo opens a dedicated full-screen capture interface
//  - Upon finishing or dismissing media capture, smoothly returns to the Trail View
//  - Checkpoints are anchored as numbered waypoints directly on the walking route
//

import SwiftUI
import RoomPlan
import AVKit
import CoreLocation

struct ScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dataStore = TrailsDataStore.shared

    // Core Capture Subsystems
    @StateObject private var scannerEngine = RoomScannerEngine()
    @StateObject private var cameraEngine = CameraCaptureEngine()
    @StateObject private var locationManager = TrailsLocationManager()
    @StateObject private var audioManager = AudioManager.shared

    // Active Trail Record
    @State private var currentTrailId: String = UUID().uuidString
    @State private var trailTitle: String = ""
    @State private var elapsedSeconds: Int = 0
    @State private var trailTimer: Timer?
    @State private var recordedMoments: [SpatialMoment] = []

    // View & Capture States
    @State private var isMapOnlyView: Bool = false
    @State private var showingFullScreenCaptureMode: CameraCaptureEngine.CameraMode? = nil
    @State private var showingVoiceCaptureSheet: Bool = false
    @State private var showingAddNoteSheet: Bool = false
    @State private var showingMomentsTray: Bool = false
    @State private var showingFinishReview: Bool = false
    @State private var showingEmptyAlert: Bool = false
    @State private var showingCancelConfirm: Bool = false
    @State private var selectedCheckpointPreview: SpatialMoment? = nil

    // Quick Note inputs
    @State private var noteTitle: String = ""
    @State private var noteBody: String = ""

    // In-line Voice Recording (keeping camera / view active)
    @State private var isInLineVoiceRecording: Bool = false

    // Starting Point Reference Frame / Vantage State
    @State private var startFramePhotoFileName: String? = nil
    @State private var startFrameHeadingDegrees: Double? = nil
    @State private var startFrameVantageDescription: String = ""
    @State private var isStartingFramePano: Bool = false

    // Automatic Start Moment Timer
    @State private var startMomentTimer: Timer? = nil

    // Toast feedback
    @State private var toastMessage: String? = nil

    // Instant In-Session Photo Shutter
    @State private var isShutterFlashActive: Bool = false
    @State private var isProcessingPhotoCapture: Bool = false

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
            // MARK: - 1. Active Spatial Trail Canvas
            Color(hex: "#0A0E14")
                .ignoresSafeArea()

            if isMapOnlyView {
                // Fullscreen 2D Architectural Blueprint Trail Map
                RoomLayoutView(
                    capturedRoom: scannerEngine.capturedRoom,
                    footsteps: scannerEngine.footsteps,
                    moments: recordedMoments
                )
                .ignoresSafeArea()
            } else {
                // Split View: LiDAR Viewport on Top, Architectural Trail Map on Bottom
                VStack(spacing: 0) {
                    // Upper Pane: Live LiDAR Spatial Camera
                    ZStack(alignment: .bottomLeading) {
                        if scannerEngine.isSupported {
                            RoomCameraView(engine: scannerEngine)
                                .ignoresSafeArea()
                        } else {
                            ZStack {
                                Color.black
                                VStack(spacing: 8) {
                                    Image(systemName: "cube.transparent")
                                        .font(.system(size: 36))
                                        .foregroundColor(AppColors.mutedBrass)
                                    Text("LiDAR Spatial Scanning")
                                        .font(AppFonts.headlineSmall)
                                        .foregroundColor(.white)
                                    Text("Walk through the room to map perimeter and trail")
                                        .font(AppFonts.caption)
                                        .foregroundColor(Color.white.opacity(0.65))
                                }
                            }
                        }

                        // Bottom gradient scrim for upper pane
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.4)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 60)
                    }
                    .frame(height: UIScreen.main.bounds.height * 0.50)

                    // Lower Pane: 2D Architectural Blueprint Floor Plan & Route
                    ZStack(alignment: .topTrailing) {
                        RoomLayoutView(
                            capturedRoom: scannerEngine.capturedRoom,
                            footsteps: scannerEngine.footsteps,
                            moments: recordedMoments
                        )

                        // Subtle boundary border
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 1)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .ignoresSafeArea()
            }

            // MARK: - 2. HUD & Overlays
            VStack(spacing: 0) {
                // Top Navigation & Journey Status Bar
                topJourneyBar

                Spacer()

                // Checkpoint Waypoint Ribbon & Capture Dock
                bottomConsole
            }

            // MARK: - 3. Transient Toast
            if let toast = toastMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppColors.mutedBrass)
                        Text(toast)
                            .font(AppFonts.labelUI)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Capsule())
                    .padding(.bottom, 220)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut(duration: 0.2), value: toastMessage)
            }

            // Instant Camera Shutter Flash Overlay - subtle vignette pulse instead of blinding full-screen white
            if isShutterFlashActive {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            initializeTrailSession()
        }
        .onDisappear {
            teardownTrailSession()
        }
        // Dedicated Full-Screen Camera Interface (Video / Photo)
        .fullScreenCover(
            isPresented: Binding(
                get: { showingFullScreenCaptureMode != nil },
                set: { if !$0 { showingFullScreenCaptureMode = nil } }
            ),
            onDismiss: {
                // Safely resume RoomPlan only after the camera modal has completely exited the view hierarchy and released camera hardware
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    scannerEngine.resumeScanning()
                }
            }
        ) {
            if let mode = showingFullScreenCaptureMode {
                FullScreenCameraCaptureView(
                    cameraEngine: cameraEngine,
                    mode: mode,
                    waypointIndex: recordedMoments.count + 1,
                    trailId: currentTrailId,
                    onSavedVideo: { fileURL, duration, thumbURL in
                        handleSavedVideoWaypoint(fileURL: fileURL, duration: duration, thumbURL: thumbURL)
                    },
                    onSavedPhoto: { image, fileURL, thumbURL in
                        handleSavedPhotoWaypoint(image: image, fileURL: fileURL, thumbURL: thumbURL)
                    },
                    onCancel: {}
                )
            }
        }
        // Voice Note Checkpoint Sheet
        .sheet(isPresented: $showingVoiceCaptureSheet) {
            VoiceNoteCheckpointSheet(
                trailId: currentTrailId,
                waypointIndex: recordedMoments.count + 1,
                audioManager: audioManager,
                onSave: { audioURL, duration in
                    handleSavedVoiceWaypoint(audioURL: audioURL, duration: duration)
                    showingVoiceCaptureSheet = false
                    scannerEngine.resumeScanning()
                },
                onCancel: {
                    showingVoiceCaptureSheet = false
                    scannerEngine.resumeScanning()
                }
            )
            .presentationDetents([.fraction(0.48)])
        }
        // Written Note Sheet
        .sheet(isPresented: $showingAddNoteSheet) {
            AddNoteQuickSheet(
                title: $noteTitle,
                bodyText: $noteBody,
                onSave: { t, b in
                    saveTextMoment(title: t, text: b)
                    showingAddNoteSheet = false
                    scannerEngine.resumeScanning()
                },
                onCancel: {
                    showingAddNoteSheet = false
                    scannerEngine.resumeScanning()
                }
            )
            .presentationDetents([.fraction(0.48)])
        }
        // In-Capture Moments Tray Sheet
        .sheet(isPresented: $showingMomentsTray) {
            CapturedMomentsTrayView(
                trailId: currentTrailId,
                moments: $recordedMoments,
                onUpdateMoment: { updated in
                    if let idx = recordedMoments.firstIndex(where: { $0.id == updated.id }) {
                        recordedMoments[idx] = updated
                        persistIncrementalDraft()
                    }
                },
                onDeleteMoment: { id in
                    recordedMoments.removeAll { $0.id == id }
                    for i in 0..<recordedMoments.count {
                        recordedMoments[i].index = i + 1
                    }
                    persistIncrementalDraft()
                },
                onDismiss: {
                    showingMomentsTray = false
                }
            )
        }
        // Checkpoint Preview Sheet
        .sheet(item: $selectedCheckpointPreview) { moment in
            MomentPreviewSheet(trailId: currentTrailId, moment: moment)
        }
        // Finish & Review Summary Sheet
        .sheet(isPresented: $showingFinishReview) {
            FinishTrailReviewSheet(
                trailId: currentTrailId,
                initialTitle: trailTitle,
                elapsedSeconds: elapsedSeconds,
                walkedMeters: walkedMeters,
                moments: recordedMoments,
                hasIndoorScan: scannerEngine.capturedRoom != nil,
                onSave: { finalTitle, personalNotes, coverMomentId in
                    finalizeAndSaveTrail(customTitle: finalTitle, personalNotes: personalNotes, coverMomentId: coverMomentId)
                },
                onKeepRecording: {
                    scannerEngine.resumeScanning()
                }
            )
        }
        // Empty Session Alert
        .alert("Nothing Captured", isPresented: $showingEmptyAlert) {
            Button("Continue Trail", role: .cancel) {}
            Button("Discard Trail", role: .destructive) {
                discardActiveDraft()
                dismiss()
            }
        } message: {
            Text("No checkpoint moments, spatial paths, or room scans were recorded for this trail.")
        }
        // Cancel/Discard Confirmation
        .confirmationDialog("Leave active trail?", isPresented: $showingCancelConfirm, titleVisibility: .visible) {
            Button("Keep Recording", role: .cancel) {}
            Button("Discard & Exit", role: .destructive) {
                discardActiveDraft()
                dismiss()
            }
        } message: {
            Text("Any unfinalized moments and walking path will be discarded.")
        }
    }

    // MARK: - Top Journey Bar

    private var topJourneyBar: some View {
        HStack(spacing: 12) {
            // Close / Cancel Button
            Button {
                Haptics.light()
                if recordedMoments.isEmpty && walkedMeters <= 1 {
                    discardActiveDraft()
                    dismiss()
                } else {
                    showingCancelConfirm = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }

            Spacer()

            // Live Telemetry Status Pill
            HStack(spacing: 8) {
                Circle()
                    .fill(AppColors.forestGreen)
                    .frame(width: 8, height: 8)
                    .scaleEffect(1.2)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: scannerEngine.isScanning)

                Text(formattedTime)
                    .font(AppFonts.labelSpatial)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("·")
                    .foregroundColor(Color.white.opacity(0.4))

                Text("\(walkedMeters)m")
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(AppColors.mutedBrass)

                Text("·")
                    .foregroundColor(Color.white.opacity(0.4))

                Text("\(recordedMoments.count) Stops")
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.65))
            .clipShape(Capsule())

            Spacer()

            // Finish Trail CTA Button
            Button {
                Haptics.success()
                handleFinishTrail()
            } label: {
                HStack(spacing: 6) {
                    Text("Finish")
                        .font(AppFonts.labelUI)
                        .fontWeight(.semibold)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(AppColors.onPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(AppColors.primary)
                .clipShape(Capsule())
                .shadow(color: AppColors.primary.opacity(0.3), radius: 6, x: 0, y: 3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 48)
    }

    // MARK: - Bottom Console (Checkpoints Ribbon + Capture Actions)

    private var bottomConsole: some View {
        VStack(spacing: 12) {
            // View Mode Toggle [ Split | Full Blueprint ]
            HStack {
                Spacer()

                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isMapOnlyView.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isMapOnlyView ? "rectangle.split.2x1.fill" : "map.fill")
                            .font(.system(size: 12))
                        Text(isMapOnlyView ? "Show Camera" : "Full Blueprint")
                            .font(AppFonts.labelSpatial)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)

            // 1. Checkpoint Sequence Ribbon Along Path
            if isInLineVoiceRecording {
                inLineVoiceRecordingBar
            } else {
                checkpointRibbon
            }

            // 2. Waypoint Capture Action Dock
            waypointCaptureDock
        }
        .padding(.bottom, 24)
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.75), Color.black.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - In-Line Voice Recording Bar (Keeps camera viewport visible)

    private var inLineVoiceRecordingBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppColors.terracotta)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(AppColors.terracotta.opacity(0.5), lineWidth: 3)
                        .scaleEffect(1.6)
                )

            Text("RECORDING OBSERVATION")
                .font(AppFonts.labelSpatial)
                .foregroundColor(AppColors.terracotta)
                .tracking(1.2)

            Spacer()

            let m = Int(audioManager.recordingDuration) / 60
            let s = Int(audioManager.recordingDuration) % 60
            Text(String(format: "%02d:%02d", m, s))
                .font(AppFonts.labelMetric)
                .foregroundColor(.white)

            Button {
                toggleInLineVoiceRecording()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Done")
                }
                .font(AppFonts.labelUI)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(AppColors.terracotta)
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.85))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AppColors.terracotta.opacity(0.4), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    // MARK: - Checkpoint Sequence Ribbon

    private var checkpointRibbon: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if recordedMoments.isEmpty {
                    // Guidance pill
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.terracotta)
                        Text("Walk to a spot and tap Record Video or Photo to anchor a checkpoint")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(Color.white.opacity(0.75))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
                } else {
                    ForEach(recordedMoments) { moment in
                        Button {
                            Haptics.selection()
                            selectedCheckpointPreview = moment
                        } label: {
                            HStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(AppColors.terracotta)
                                        .frame(width: 20, height: 20)
                                    Text("\(moment.index)")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundColor(.white)
                                }

                                Text(moment.title)
                                    .font(AppFonts.labelSpatial)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .lineLimit(1)

                                Image(systemName: iconForMediaType(moment.mediaType))
                                    .font(.system(size: 10))
                                    .foregroundColor(AppColors.mutedBrass)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                        }
                    }

                    // Current position pill
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AppColors.forestGreen)
                            .frame(width: 6, height: 6)
                        Text("Current Stop · +\(walkedMeters)m")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(Color.white.opacity(0.7))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Waypoint Capture Dock

    private var waypointCaptureDock: some View {
        HStack(spacing: 8) {
            // 1. Moments Tray / Thumbnail
            Button {
                Haptics.light()
                showingMomentsTray = true
            } label: {
                ZStack {
                    if let lastMoment = recordedMoments.last {
                        momentThumbnailView(for: lastMoment)
                    } else {
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .overlay(
                                Image(systemName: "photo.stack")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color.white.opacity(0.8))
                            )
                    }

                    if !recordedMoments.isEmpty {
                        VStack {
                            HStack {
                                Spacer()
                                Text("\(recordedMoments.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(AppColors.terracotta)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                        }
                        .offset(x: 3, y: -3)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1.5))
            }
            .buttonStyle(ScaleButtonStyle())

            Spacer(minLength: 2)

            // 2. QUICK SNAP: Instant 0ms Shutter on Active Trail
            Button {
                triggerInstantPhotoCapture()
            } label: {
                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 46, height: 46)
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: 42, height: 42)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("Quick Snap")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.9))
                }
            }
            .buttonStyle(ScaleButtonStyle())

            Spacer(minLength: 2)

            // 3. ZOOM CAMERA: Optical Telephoto & Full 48MP Smart HDR
            Button {
                Haptics.medium()
                scannerEngine.pauseScanning()
                showingFullScreenCaptureMode = .photo
            } label: {
                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .fill(AppColors.mutedBrass.opacity(0.25))
                            .frame(width: 46, height: 46)
                        Circle()
                            .stroke(AppColors.mutedBrass, lineWidth: 2)
                            .frame(width: 42, height: 42)
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppColors.mutedBrass)
                    }
                    Text("Zoom Cam")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(AppColors.mutedBrass)
                }
            }
            .buttonStyle(ScaleButtonStyle())

            Spacer(minLength: 2)

            // 4. RECORD VIDEO: 4K UHD Spatial Video
            Button {
                Haptics.medium()
                scannerEngine.pauseScanning()
                showingFullScreenCaptureMode = .video
            } label: {
                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .fill(AppColors.terracotta)
                            .frame(width: 46, height: 46)
                        Circle()
                            .stroke(Color.white.opacity(0.55), lineWidth: 2)
                            .frame(width: 42, height: 42)
                        Image(systemName: "video.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("Video")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.9))
                }
            }
            .buttonStyle(ScaleButtonStyle())

            Spacer(minLength: 2)

            // 5. VOICE NOTE - Live In-situ recording without obscuring camera view
            Button {
                toggleInLineVoiceRecording()
            } label: {
                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .fill(isInLineVoiceRecording ? AppColors.terracotta : Color.black.opacity(0.6))
                            .frame(width: 44, height: 44)
                        Image(systemName: isInLineVoiceRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 16))
                            .foregroundColor(isInLineVoiceRecording ? .white : AppColors.mutedBrass)
                    }
                    .overlay(Circle().stroke(isInLineVoiceRecording ? AppColors.terracotta : Color.white.opacity(0.2), lineWidth: 1.2))
                    Text(isInLineVoiceRecording ? "Stop" : "Voice")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(isInLineVoiceRecording ? AppColors.terracotta : Color.white.opacity(0.8))
                }
            }
            .buttonStyle(ScaleButtonStyle())

            Spacer(minLength: 2)

            // 6. WRITTEN NOTE
            Button {
                Haptics.light()
                scannerEngine.pauseScanning()
                noteTitle = ""
                noteBody = ""
                showingAddNoteSheet = true
            } label: {
                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 44, height: 44)
                        Image(systemName: "note.text.badge.plus")
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                    }
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1.2))
                    Text("Note")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.8))
                }
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Color.black.opacity(0.65)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .padding(.horizontal, 10)
    }

    // MARK: - Capture Handlers & Anchoring

    private func handleSavedVideoWaypoint(fileURL: URL, duration: TimeInterval, thumbURL: URL) {
        let id = UUID().uuidString
        let durMinutes = Int(duration) / 60
        let durSeconds = Int(duration) % 60
        let durString = String(format: "%d:%02d", durMinutes, durSeconds)
        let pos = scannerEngine.lastRecordedPosition ?? SIMD3<Float>(0, 0, 0)
        let heading = scannerEngine.currentYawDegrees != 0 ? scannerEngine.currentYawDegrees : locationManager.currentHeading
        let idx = recordedMoments.count + 1

        let moment = SpatialMoment(
            id: id,
            index: idx,
            title: "Stop \(idx) · Video",
            subtitle: "Spatial Video · \(durString)",
            narrative: "Video waypoint checkpoint anchored at \(walkedMeters)m along path.",
            architecturalNote: "6DOF Location: X=\(String(format: "%.2f", pos.x))m, Z=\(String(format: "%.2f", pos.z))m",
            distanceAlongPathMeters: walkedMeters,
            videoDuration: durString,
            hasVideo: true,
            mediaType: "video",
            videoFileName: fileURL.lastPathComponent,
            videoThumbnailAssetName: thumbURL.lastPathComponent,
            positionX: Double(pos.x),
            positionY: Double(pos.z),
            positionZ: Double(pos.y),
            headingDegrees: heading,
            placementStatus: "placed",
            createdAt: Date()
        )

        recordedMoments.append(moment)
        persistIncrementalDraft()
        // Note: Do not call scannerEngine.resumeScanning() here - onDismiss handles it after modal exits
        triggerToast("Checkpoint \(idx) Video Anchored")
    }

    private func triggerInstantPhotoCapture() {
        guard !isProcessingPhotoCapture else { return }
        Haptics.medium()

        withAnimation(.linear(duration: 0.05)) {
            isShutterFlashActive = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeOut(duration: 0.18)) {
                isShutterFlashActive = false
            }
        }

        // Capture instant high-res frame from active AR stream without pausing the live session
        if let image = scannerEngine.captureCurrentARFrameImage() {
            isProcessingPhotoCapture = true
            let id = UUID().uuidString
            let photoName = "photo_\(id).jpg"
            let thumbName = "thumb_\(id).jpg"
            let destURL = TrailPackageStore.shared.mediaDirectory(for: currentTrailId).appendingPathComponent(photoName)
            let thumbURL = TrailPackageStore.shared.mediaDirectory(for: currentTrailId).appendingPathComponent(thumbName)

            Task.detached(priority: .userInitiated) { [destURL, thumbURL, image] in
                if let data = image.jpegData(compressionQuality: 0.85) {
                    try? data.write(to: destURL, options: .atomic)
                    if let thumb = CameraCaptureEngine.generateDownsampledThumbnail(from: data, maxPixelSize: 400),
                       let thumbData = thumb.jpegData(compressionQuality: 0.8) {
                        try? thumbData.write(to: thumbURL, options: .atomic)
                    }
                }

                await MainActor.run {
                    self.isProcessingPhotoCapture = false
                    self.handleSavedPhotoWaypoint(image: image, fileURL: destURL, thumbURL: thumbURL)
                }
            }
        } else {
            // Fallback to modal camera if no live AR frame is cached
            scannerEngine.pauseScanning()
            showingFullScreenCaptureMode = .photo
        }
    }

    private func handleSavedPhotoWaypoint(image: UIImage, fileURL: URL, thumbURL: URL) {
        let id = UUID().uuidString
        let pos = scannerEngine.lastRecordedPosition ?? SIMD3<Float>(0, 0, 0)
        let heading = scannerEngine.currentYawDegrees != 0 ? scannerEngine.currentYawDegrees : locationManager.currentHeading
        let idx = recordedMoments.count + 1

        let moment = SpatialMoment(
            id: id,
            index: idx,
            title: "Stop \(idx) · Photo",
            subtitle: Date().formatted(date: .omitted, time: .shortened),
            narrative: "Photo waypoint checkpoint anchored at \(walkedMeters)m along path.",
            architecturalNote: "6DOF Location: X=\(String(format: "%.2f", pos.x))m, Z=\(String(format: "%.2f", pos.z))m",
            distanceAlongPathMeters: walkedMeters,
            hasPhoto: true,
            mediaType: "photo",
            photoFileName: fileURL.lastPathComponent,
            positionX: Double(pos.x),
            positionY: Double(pos.z),
            positionZ: Double(pos.y),
            headingDegrees: heading,
            placementStatus: "placed",
            createdAt: Date()
        )

        recordedMoments.append(moment)
        persistIncrementalDraft()
        // Note: Do not call scannerEngine.resumeScanning() here - if from modal, onDismiss handles it; if instant, not paused.
        triggerToast("Checkpoint \(idx) Photo Anchored")
    }

    private func handleSavedVoiceWaypoint(audioURL: URL, duration: TimeInterval) {
        let id = UUID().uuidString
        let durMinutes = Int(duration) / 60
        let durSeconds = Int(duration) % 60
        let durString = String(format: "%d:%02d", durMinutes, durSeconds)
        let pos = scannerEngine.lastRecordedPosition ?? SIMD3<Float>(0, 0, 0)
        let heading = scannerEngine.currentYawDegrees != 0 ? scannerEngine.currentYawDegrees : locationManager.currentHeading
        let idx = recordedMoments.count + 1

        let moment = SpatialMoment(
            id: id,
            index: idx,
            title: "Stop \(idx) · Voice",
            subtitle: "Voice Note · \(durString)",
            narrative: "Audio waypoint checkpoint anchored at \(walkedMeters)m along path.",
            architecturalNote: "6DOF Location: X=\(String(format: "%.2f", pos.x))m, Z=\(String(format: "%.2f", pos.z))m",
            distanceAlongPathMeters: walkedMeters,
            audioDuration: durString,
            hasAudio: true,
            mediaType: "voice",
            audioFileName: audioURL.lastPathComponent,
            positionX: Double(pos.x),
            positionY: Double(pos.z),
            positionZ: Double(pos.y),
            headingDegrees: heading,
            placementStatus: "placed",
            createdAt: Date()
        )

        recordedMoments.append(moment)
        persistIncrementalDraft()
        triggerToast("Checkpoint \(idx) Voice Anchored")
    }

    private func saveTextMoment(title: String, text: String) {
        let id = UUID().uuidString
        let idx = recordedMoments.count + 1
        let safeTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? "Stop \(idx) · Field Note" : title
        let pos = scannerEngine.lastRecordedPosition ?? SIMD3<Float>(0, 0, 0)
        let heading = scannerEngine.currentYawDegrees != 0 ? scannerEngine.currentYawDegrees : locationManager.currentHeading

        let moment = SpatialMoment(
            id: id,
            index: idx,
            title: safeTitle,
            subtitle: Date().formatted(date: .omitted, time: .shortened),
            narrative: text,
            architecturalNote: "6DOF Location: X=\(String(format: "%.2f", pos.x))m, Z=\(String(format: "%.2f", pos.z))m",
            distanceAlongPathMeters: walkedMeters,
            mediaType: "note",
            positionX: Double(pos.x),
            positionY: Double(pos.z),
            positionZ: Double(pos.y),
            headingDegrees: heading,
            placementStatus: "placed",
            createdAt: Date()
        )

        recordedMoments.append(moment)
        persistIncrementalDraft()
        triggerToast("Checkpoint \(idx) Note Anchored")
    }

    // MARK: - Lifecycle & Persistence

    // MARK: - Lifecycle & Background Reference Starting Frame Capture

    private func captureStartingReferenceFrameIfNeeded() {
        guard startFramePhotoFileName == nil else { return }
        let capturedImage = scannerEngine.captureCurrentARFrameImage() ?? createFallbackStartingImage()

        let heading = scannerEngine.currentYawDegrees != 0 ? scannerEngine.currentYawDegrees : (locationManager.currentHeading ?? 0)
        let fileName = TrailPackageStore.shared.saveStartFrameImage(capturedImage, for: currentTrailId)
        startFramePhotoFileName = fileName
        startFrameHeadingDegrees = heading
        isStartingFramePano = false

        persistIncrementalDraft()
    }

    private func createFallbackStartingImage() -> UIImage {
        let size = CGSize(width: 800, height: 600)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        defer { UIGraphicsEndImageContext() }
        let ctx = UIGraphicsGetCurrentContext()!
        ctx.setFillColor(UIColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 1.0).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }

    private func initializeTrailSession() {
        currentTrailId = UUID().uuidString
        trailTitle = "Trail · \(Date().formatted(date: .abbreviated, time: .shortened))"
        recordedMoments.removeAll()
        startFramePhotoFileName = nil
        startFrameHeadingDegrees = nil
        startFrameVantageDescription = ""
        isStartingFramePano = false
        elapsedSeconds = 0

        // Start RoomPlan / 6DOF tracking
        scannerEngine.resetAndStartScanning()
        locationManager.requestAccessIfNeeded()

        // Automatically capture start reference frame quietly in background
        startMomentTimer?.invalidate()
        startMomentTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            if scannerEngine.captureCurrentARFrameImage() != nil {
                captureStartingReferenceFrameIfNeeded()
                startMomentTimer?.invalidate()
                startMomentTimer = nil
            }
        }

        // Timer
        trailTimer?.invalidate()
        trailTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedSeconds += 1
            if startFramePhotoFileName == nil && elapsedSeconds >= 2 {
                captureStartingReferenceFrameIfNeeded()
            }
        }

        persistIncrementalDraft()
    }

    private func persistIncrementalDraft() {
        let author = dataStore.localProfile.displayName.isEmpty ? "Explorer" : dataStore.localProfile.displayName
        let loc = locationManager.currentLocation

        let draft = TrailDetail(
            id: currentTrailId,
            title: trailTitle,
            subtitle: "\(walkedMeters)m recorded path · \(recordedMoments.count) moments",
            placeId: "personal-trail",
            placeName: "My Trail",
            locality: "Local Trail",
            wing: "Spatial Journey",
            authorName: author,
            authorRole: "Spatial Journal",
            distanceMeters: walkedMeters,
            floorCode: "LVL 00",
            floorTitle: "Ground Floor",
            meshDensity: scannerEngine.capturedRoom != nil ? "\(scannerEngine.capturedRoom?.walls.count ?? 0) walls detected" : "LiDAR Route",
            samplingFrequency: "24.6 kHz",
            nodeCount: max(1, scannerEngine.footsteps.count),
            personalNotes: "",
            moments: recordedMoments,
            visibility: .privateDraft,
            isDraft: true,
            coverImageName: recordedMoments.first(where: { $0.hasPhoto })?.photoFileName,
            latitude: loc?.coordinate.latitude,
            longitude: loc?.coordinate.longitude,
            startFramePhotoName: startFramePhotoFileName,
            startHeadingDegrees: startFrameHeadingDegrees,
            startVantageDescription: startFrameVantageDescription,
            isStartingFramePano: isStartingFramePano,
            createdAt: Date().addingTimeInterval(-Double(elapsedSeconds)),
            updatedAt: Date()
        )
        dataStore.saveDraft(trail: draft, footsteps: scannerEngine.footsteps)
    }

    private func handleFinishTrail() {
        if recordedMoments.isEmpty && walkedMeters <= 1 && scannerEngine.capturedRoom == nil {
            showingEmptyAlert = true
            return
        }
        scannerEngine.pauseScanning()
        showingFinishReview = true
    }

    private func finalizeAndSaveTrail(customTitle: String? = nil, personalNotes: String? = nil, coverMomentId: String? = nil) {
        let author = dataStore.localProfile.displayName.isEmpty ? "Explorer" : dataStore.localProfile.displayName
        let loc = locationManager.currentLocation

        if startFramePhotoFileName == nil {
            captureStartingReferenceFrameIfNeeded()
        }

        let chosenCover: String? = {
            if let id = coverMomentId, let m = recordedMoments.first(where: { $0.id == id }) {
                return m.photoFileName ?? m.videoThumbnailAssetName
            }
            return startFramePhotoFileName ?? recordedMoments.first(where: { $0.hasPhoto })?.photoFileName ?? recordedMoments.first(where: { $0.hasVideo })?.videoThumbnailAssetName
        }()

        let finalTitle = (customTitle?.isEmpty == false) ? customTitle! : trailTitle
        let finalNotes = (personalNotes?.isEmpty == false) ? personalNotes! : "Saved privately on this iPhone."
        let chosenStartPhoto = startFramePhotoFileName ?? recordedMoments.first(where: { $0.hasPhoto })?.photoFileName
        let chosenHeading = startFrameHeadingDegrees ?? recordedMoments.first?.headingDegrees ?? scannerEngine.currentYawDegrees
        let chosenDesc = !startFrameVantageDescription.isEmpty ? startFrameVantageDescription : "Starting origin vantage"

        let finalTrail = TrailDetail(
            id: currentTrailId,
            title: finalTitle,
            subtitle: "\(walkedMeters)m recorded path · \(recordedMoments.count) moments",
            placeId: "personal-trail",
            placeName: "My Trail",
            locality: "Local Trail",
            wing: "Ground Floor",
            authorName: author,
            authorRole: "Spatial Journal",
            distanceMeters: walkedMeters,
            floorCode: "LVL 00",
            floorTitle: "Ground Floor",
            meshDensity: scannerEngine.capturedRoom != nil ? "\(scannerEngine.capturedRoom?.walls.count ?? 0) walls detected" : "LiDAR Route",
            samplingFrequency: "24.6 kHz",
            nodeCount: max(1, scannerEngine.footsteps.count),
            personalNotes: finalNotes,
            moments: recordedMoments,
            visibility: .privateDraft,
            isDraft: false,
            coverImageName: chosenCover,
            latitude: loc?.coordinate.latitude,
            longitude: loc?.coordinate.longitude,
            startFramePhotoName: chosenStartPhoto,
            startHeadingDegrees: chosenHeading,
            startVantageDescription: chosenDesc,
            isStartingFramePano: isStartingFramePano,
            createdAt: Date().addingTimeInterval(-Double(elapsedSeconds)),
            updatedAt: Date()
        )

        dataStore.saveFinalTrail(trail: finalTrail, footsteps: scannerEngine.footsteps)

        // PRD v0.3.1 §6 & §7: Export and persist ARWorldMap & ReferenceFrame
        scannerEngine.exportWorldMap { worldMapData in
            if let data = worldMapData {
                TrailPackageStore.shared.saveWorldMapData(data, for: finalTrail.id)
                let refFrame = ReferenceFrame(
                    id: UUID().uuidString,
                    sourceSessionId: finalTrail.id,
                    units: "meters",
                    axisConvention: "rightHanded_YUp_ZBack",
                    worldAlignmentConfiguration: "gravityAndHeading",
                    createdAt: Date(),
                    positioningMethod: "arWorldMap",
                    alignmentAssetReferences: ["spatial/worldmap.arworldmap"],
                    startFramePhotoName: chosenStartPhoto,
                    originHeadingDegrees: chosenHeading,
                    startVantageDescription: chosenDesc
                )
                TrailPackageStore.shared.saveReferenceFrame(refFrame, for: finalTrail.id)
            }
        }

        teardownTrailSession()
        dataStore.reloadFromDisk()
        dismiss()
    }

    private func discardActiveDraft() {
        teardownTrailSession()
        dataStore.deleteTrail(id: currentTrailId)
    }

    private func teardownTrailSession() {
        startMomentTimer?.invalidate()
        startMomentTimer = nil
        trailTimer?.invalidate()
        trailTimer = nil
        scannerEngine.stopScanning()
        cameraEngine.stop()
        if audioManager.isRecording {
            _ = audioManager.stopRecording()
        }
    }

    private func triggerToast(_ msg: String) {
        toastMessage = msg
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation {
                if toastMessage == msg {
                    toastMessage = nil
                }
            }
        }
    }

    @ViewBuilder
    private func momentThumbnailView(for moment: SpatialMoment) -> some View {
        if moment.hasPhoto, let photoURL = moment.resolvedPhotoURL(trailId: currentTrailId),
           let uiImage = UIImage(contentsOfFile: photoURL.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else if moment.hasVideo, let thumbURL = moment.resolvedVideoThumbnailURL(trailId: currentTrailId),
                  let uiImage = UIImage(contentsOfFile: thumbURL.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            Circle()
                .fill(AppColors.surfaceContainerHigh)
                .overlay(
                    Image(systemName: iconForMediaType(moment.mediaType))
                        .font(.system(size: 16))
                        .foregroundColor(AppColors.primary)
                )
        }
    }

    private func iconForMediaType(_ type: String) -> String {
        switch type {
        case "video": return "video.fill"
        case "photo": return "camera.fill"
        case "voice": return "mic.fill"
        default: return "note.text"
        }
    }
}

// MARK: - Voice Note Checkpoint Sheet

struct VoiceNoteCheckpointSheet: View {
    @Environment(\.dismiss) private var dismiss
    let trailId: String
    let waypointIndex: Int
    @ObservedObject var audioManager: AudioManager
    let onSave: (URL, TimeInterval) -> Void
    let onCancel: () -> Void

    @State private var recordedURL: URL? = nil
    @State private var recordedDuration: TimeInterval = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 6) {
                    Text("WAYPOINT \(waypointIndex) · VOICE NOTE")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.terracotta)
                        .tracking(1.5)

                    Text(audioManager.isRecording ? "Recording in-situ observation..." : "Tap microphone to record note")
                        .font(AppFonts.headlineSmall)
                        .foregroundColor(AppColors.primary)
                }
                .padding(.top, 16)

                // Animated Mic / Waveform Circle
                ZStack {
                    Circle()
                        .fill(AppColors.mutedBrass.opacity(audioManager.isRecording ? 0.25 : 0.1))
                        .frame(width: audioManager.isRecording ? 130 : 90, height: audioManager.isRecording ? 130 : 90)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: audioManager.isRecording)

                    Button {
                        Haptics.medium()
                        if audioManager.isRecording {
                            if let result = audioManager.stopRecording() {
                                onSave(result.url, result.duration)
                            }
                        } else {
                            let id = UUID().uuidString
                            let name = "voice_\(id).m4a"
                            let dest = TrailPackageStore.shared.mediaDirectory(for: trailId).appendingPathComponent(name)
                            _ = audioManager.startRecording(destinationURL: dest)
                        }
                    } label: {
                        Circle()
                            .fill(audioManager.isRecording ? AppColors.terracotta : AppColors.primary)
                            .frame(width: 72, height: 72)
                            .overlay(
                                Image(systemName: audioManager.isRecording ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 26))
                                    .foregroundColor(.white)
                            )
                    }
                }

                Text(audioManager.isRecording ? "Tap red button to finish & anchor" : "Tap to start speaking")
                    .font(AppFonts.bodySmall)
                    .foregroundColor(AppColors.onSurfaceVariant)

                Spacer()
            }
            .padding(20)
            .background(AppColors.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if audioManager.isRecording {
                            _ = audioManager.stopRecording()
                        }
                        onCancel()
                    }
                    .foregroundColor(AppColors.primary)
                }
            }
        }
    }
}

// MARK: - Add Note Quick Sheet

struct AddNoteQuickSheet: View {
    @Binding var title: String
    @Binding var bodyText: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WAYPOINT NOTE TITLE")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.outline)
                    TextField("e.g. Echo in the archway", text: $title)
                        .font(AppFonts.bodyMedium)
                        .padding(12)
                        .background(AppColors.surfaceContainerLow)
                        .cornerRadius(10)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("OBSERVATION / REFLECTION")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.outline)
                    TextEditor(text: $bodyText)
                        .font(AppFonts.bodyMedium)
                        .frame(height: 100)
                        .padding(8)
                        .background(AppColors.surfaceContainerLow)
                        .cornerRadius(10)
                }

                Spacer()

                Button {
                    onSave(title, bodyText)
                } label: {
                    Text("Anchor Note to Trail")
                        .font(AppFonts.labelUI)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(bodyText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.5) : AppColors.primary)
                        .clipShape(Capsule())
                }
                .disabled(bodyText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
            .background(AppColors.canvas.ignoresSafeArea())
            .navigationTitle("Add Field Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: onCancel)
                        .foregroundColor(AppColors.primary)
                }
            }
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
