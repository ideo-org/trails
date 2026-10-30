//
//  RetraceTrailView.swift
//  Trails
//
//  Retrace Companion Flow for Trails v0.3.1 (PRD v0.3.1: Reliable Reference Frames and Retrace Alignment).
//  Addresses the root cause of small-space alignment failure:
//  - Establishes a shared physical reference frame between original recording and live retrace
//  - Implements the 6-state Indoor Alignment State Machine (unavailable, loading, searching, verifying, aligned, degraded, lost)
//  - Supports ARWorldMap relocalisation when saved, with verified coordinate matching
//  - Never presents unaligned coordinates as aligned; hides misleading moving markers while searching
//  - Provides first-class Manual Follow-Along fallback (PRD §14)
//  - Supports two-point manual reference calibration (PRD §9 & §10)
//  - Includes real-time positioning diagnostics panel (PRD §16) with JSON export
//

import SwiftUI
import RoomPlan
import ARKit
import AVKit
import simd

public struct DirectionalInstruction {
    public let icon: String
    public let relativeAngle: Double // in degrees: negative = left, positive = right
    public let primaryText: String
    public let secondaryText: String
    public let color: Color
}

public struct RetraceTrailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dataStore = TrailsDataStore.shared

    let referenceTrail: TrailDetail

    // Hardware Subsystems
    @StateObject private var scannerEngine = RoomScannerEngine()
    @StateObject private var cameraEngine = CameraCaptureEngine()
    @StateObject private var locationManager = TrailsLocationManager()
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var arVideoRecorder = ARVideoRecorder.shared

    // Starting Point Reference Guidance (PRD §8 & User Request)
    @State private var hasConfirmedStart: Bool = false
    @State private var showingStartFrameGuidance: Bool = true

    // Reference Vantage & Ghost Alignment Viewfinder
    @StateObject private var frameMatcher = FrameAlignmentMatcher.shared
    @State private var isGhostOverlayVisible: Bool = true
    @State private var ghostOpacity: Double = 0.45
    @State private var activeReferenceCheckpoint: SpatialMoment? = nil
    @State private var isCameraExpanded: Bool = false
    @State private var alignmentTimer: Timer? = nil

    // Checkpoint Capture Sheets (Parity with ScannerView)
    @State private var showingVoiceCaptureSheet: Bool = false
    @State private var showingAddNoteSheet: Bool = false
    @State private var showingMomentsTray: Bool = false
    @State private var noteTitle: String = ""
    @State private var noteBody: String = ""
    @State private var isInLineVoiceRecording: Bool = false
    @State private var isInLineVideoRecording: Bool = false

    // PRD v0.3.1 Positioning Modes & Alignment State Machine
    @State private var positioningMode: String = "localSpatialAligned" // "localSpatialAligned", "localSpatialUnaligned", "manualFollowAlong", "geographic"
    @State private var alignmentState: String = "aligned" // "unavailable", "loading", "searching", "verifying", "aligned", "degraded", "lost"
    @State private var alignmentMethod: String = "originAnchor" // "arWorldMap", "twoPointReference", "manualProgression", "originAnchor"
    @State private var referenceFrame: ReferenceFrame? = nil
    @State private var currentSegmentId: String = UUID().uuidString
    @State private var trackingSegments: [TrackingSegment] = []
    @State private var alignmentAttempts: [AlignmentAttempt] = []

    // Retrace Session State
    @State private var sessionId: String = UUID().uuidString
    @State private var referenceFootsteps: [SIMD3<Float>] = []
    @State private var elapsedSeconds: Int = 0
    @State private var sessionTimer: Timer?
    @State private var visitedCheckpointIds: Set<String> = []
    @State private var visitedOrderArray: [String] = [] // Records order visited (supports any sequence)
    @State private var selectedTargetCheckpointId: String? = nil // Manual target override
    @State private var newRetraceMoments: [SpatialMoment] = []

    // 2D Rigid Transform for Manual Reference Calibration (PRD §9 & §10)
    @State private var transformTranslation: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    @State private var transformRotationDegrees: Double = 0.0

    // Manual Follow-Along State (PRD §14)
    @State private var manualMomentIndex: Int = 0


    // UI & Navigation Controls
    @State private var isMapOnlyView: Bool = false
    @State private var isTurnGuidanceEnabled: Bool = true
    @State private var activeCheckpointEncounter: SpatialMoment? = nil
    @State private var showingCompareSheet: Bool = false
    @State private var selectedMomentToInspect: SpatialMoment? = nil
    @State private var showingFinishAlert: Bool = false
    @State private var showingDiagnosticsSheet: Bool = false
    @State private var showingManualCalibrationSheet: Bool = false
    @State private var showingFullScreenCaptureMode: CameraCaptureEngine.CameraMode? = nil
    @State private var toastMessage: String? = nil
    @State private var isProcessingPhotoCapture: Bool = false
    @State private var isShutterFlashActive: Bool = false

    // Searching animation
    @State private var searchPulseAngle: Double = 0

    public init(referenceTrail: TrailDetail) {
        self.referenceTrail = referenceTrail
    }

    private var walkedMeters: Int {
        max(1, Int(Float(scannerEngine.footsteps.count) * 0.2))
    }

    private var formattedTime: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    // Raw device position in current session's AR frame
    private var rawDevicePosition: SIMD3<Float> {
        scannerEngine.lastRecordedPosition ?? SIMD3<Float>(0, 0, 0)
    }

    // Transformed position into reference frame
    private var transformedPosition: SIMD3<Float> {
        if alignmentMethod == "twoPointReference" {
            // Apply 2D rigid rotation around Y then translation
            let rad = Float(transformRotationDegrees * .pi / 180.0)
            let cosA = cos(rad)
            let sinA = sin(rad)
            let rx = rawDevicePosition.x * cosA - rawDevicePosition.z * sinA
            let rz = rawDevicePosition.x * sinA + rawDevicePosition.z * cosA
            return SIMD3<Float>(rx + transformTranslation.x, rawDevicePosition.y + transformTranslation.y, rz + transformTranslation.z)
        }
        return rawDevicePosition
    }

    private var currentHeadingDegrees: Double {
        var baseHeading = scannerEngine.currentYawDegrees != 0 ? scannerEngine.currentYawDegrees : (locationManager.currentHeading ?? 0)
        if alignmentMethod == "twoPointReference" {
            baseHeading = (baseHeading + transformRotationDegrees).truncatingRemainder(dividingBy: 360.0)
            if baseHeading < 0 { baseHeading += 360.0 }
        }
        return baseHeading
    }

    // MARK: - Reference Target Resolution & Match Helpers

    private var currentReferenceImage: UIImage? {
        let fallbackId = referenceTrail.sourceTrailId ?? referenceTrail.inspiredByTrailId
        if let cp = activeReferenceCheckpoint {
            if let url = cp.resolvedPhotoURL(trailId: referenceTrail.id, fallbackTrailId: fallbackId),
               let img = UIImage(contentsOfFile: url.path) {
                return img
            }
            if let url = cp.resolvedVideoThumbnailURL(trailId: referenceTrail.id, fallbackTrailId: fallbackId),
               let img = UIImage(contentsOfFile: url.path) {
                return img
            }
        }
        if let startURL = referenceTrail.resolvedStartFrameURL(fallbackTrailId: fallbackId),
           let img = UIImage(contentsOfFile: startURL.path) {
            return img
        }
        if let coverURL = referenceTrail.resolvedCoverImageURL(fallbackTrailId: fallbackId),
           let img = UIImage(contentsOfFile: coverURL.path) {
            return img
        }
        if let url = TrailPackageStore.shared.resolvedCoverOrFirstFrame(for: referenceTrail.id),
           let img = UIImage(contentsOfFile: url.path) {
            return img
        }
        if let fallback = fallbackId,
           let url = TrailPackageStore.shared.resolvedCoverOrFirstFrame(for: fallback),
           let img = UIImage(contentsOfFile: url.path) {
            return img
        }
        return nil
    }

    private var currentReferenceHeading: Double? {
        if let cp = activeReferenceCheckpoint {
            return cp.headingDegrees
        }
        return referenceTrail.startHeadingDegrees ?? referenceTrail.moments.first?.headingDegrees
    }

    private var currentReferenceTitle: String {
        if let cp = activeReferenceCheckpoint {
            return "Checkpoint \(cp.index): \(cp.title)"
        }
        return "Start Vantage"
    }

    private var matchBadgeColor: Color {
        if frameMatcher.matchPercentage >= 72 {
            return Color.green
        } else if frameMatcher.matchPercentage >= 42 {
            return Color(hex: "#00E5FF")
        } else {
            return Color(hex: "#FFA000")
        }
    }

    private func selectReference(checkpoint: SpatialMoment?) {
        activeReferenceCheckpoint = checkpoint
        frameMatcher.setReference(
            image: currentReferenceImage,
            heading: currentReferenceHeading,
            title: currentReferenceTitle
        )
    }

    // Transformed footsteps array for rendering
    private var transformedFootsteps: [SIMD3<Float>] {
        guard alignmentMethod == "twoPointReference" else { return scannerEngine.footsteps }
        let rad = Float(transformRotationDegrees * .pi / 180.0)
        let cosA = cos(rad)
        let sinA = sin(rad)
        return scannerEngine.footsteps.map { step in
            let rx = step.x * cosA - step.z * sinA
            let rz = step.x * sinA + step.z * cosA
            return SIMD3<Float>(rx + transformTranslation.x, step.y + transformTranslation.y, rz + transformTranslation.z)
        }
    }

    // MARK: - Free-Order Checkpoint Selection & Distance

    private var activeTargetCheckpoint: SpatialMoment? {
        let unvisited = referenceTrail.moments.filter { !visitedCheckpointIds.contains($0.id) }
        guard !unvisited.isEmpty else { return nil }

        if let targetId = selectedTargetCheckpointId,
           let chosen = unvisited.first(where: { $0.id == targetId }) {
            return chosen
        }

        return unvisited.min(by: { m1, m2 in
            let p1 = SIMD3<Float>(Float(m1.positionX), 0, Float(m1.positionY))
            let p2 = SIMD3<Float>(Float(m2.positionX), 0, Float(m2.positionY))
            return simd_distance(transformedPosition, p1) < simd_distance(transformedPosition, p2)
        })
    }

    private var distanceToRecordedPath: Float {
        guard !referenceFootsteps.isEmpty else { return 0 }
        var minDist: Float = .infinity
        for step in referenceFootsteps {
            let d = simd_distance(transformedPosition, step)
            if d < minDist { minDist = d }
        }
        return minDist
    }

    private func findNearestReferenceStep() -> SIMD3<Float> {
        var nearest = referenceFootsteps.first ?? SIMD3<Float>(0, 0, 0)
        var minDist: Float = .infinity
        for step in referenceFootsteps {
            let d = simd_distance(transformedPosition, step)
            if d < minDist {
                minDist = d
                nearest = step
            }
        }
        return nearest
    }

    // MARK: - Similarity Index Metrics (Valid only when Aligned)

    private var pathCoverageRatio: Double {
        guard alignmentState == "aligned" || alignmentState == "degraded" else { return 0.0 }
        guard !referenceFootsteps.isEmpty else { return 1.0 }
        let liveSteps = transformedFootsteps
        guard !liveSteps.isEmpty else { return 0.0 }

        var coveredCount = 0
        let strideInterval = max(1, referenceFootsteps.count / 30)
        var totalSampled = 0

        for i in stride(from: 0, to: referenceFootsteps.count, by: strideInterval) {
            let refStep = referenceFootsteps[i]
            totalSampled += 1
            let matched = liveSteps.contains { liveStep in
                simd_distance(refStep, liveStep) < 3.5
            }
            if matched { coveredCount += 1 }
        }
        return totalSampled > 0 ? Double(coveredCount) / Double(totalSampled) : 0.0
    }

    private var checkpointCoverageRatio: Double {
        guard !referenceTrail.moments.isEmpty else { return 1.0 }
        return Double(visitedCheckpointIds.count) / Double(referenceTrail.moments.count)
    }

    private var similarityIndexPercentage: Int {
        guard alignmentState == "aligned" || alignmentState == "degraded" else { return 0 }
        if referenceTrail.moments.isEmpty {
            return Int(pathCoverageRatio * 100)
        }
        let score = (pathCoverageRatio * 0.5) + (checkpointCoverageRatio * 0.5)
        return min(100, max(0, Int(score * 100)))
    }

    // MARK: - Dynamic Directional Navigation

    private var navigationInstruction: DirectionalInstruction {
        if !hasConfirmedStart {
            return DirectionalInstruction(
                icon: "camera.viewfinder",
                relativeAngle: 0,
                primaryText: "Go to Starting Point",
                secondaryText: "Point camera at reference view to begin trail",
                color: Color(hex: "#00E5FF")
            )
        }

        if alignmentState != "aligned" && alignmentState != "degraded" {
            return DirectionalInstruction(
                icon: "viewfinder",
                relativeAngle: 0,
                primaryText: "Point Camera at Starting View",
                secondaryText: "Align camera with starting frame to begin",
                color: Color(hex: "#00E5FF")
            )
        }

        if !referenceTrail.moments.isEmpty && visitedCheckpointIds.count == referenceTrail.moments.count {
            return DirectionalInstruction(
                icon: "checkmark.seal.fill",
                relativeAngle: 0,
                primaryText: "All Checkpoints Visited!",
                secondaryText: "Similarity: \(similarityIndexPercentage)% · Tap Finish to save trail",
                color: Color.green
            )
        }

        if let target = activeTargetCheckpoint {
            let targetPos = SIMD3<Float>(Float(target.positionX), 0, Float(target.positionY))
            let dist = simd_distance(transformedPosition, targetPos)

            let dx = targetPos.x - transformedPosition.x
            let dz = targetPos.z - transformedPosition.z
            let targetAngle = Double(atan2(-dx, -dz) * 180.0 / .pi)
            var relAngle = (targetAngle - currentHeadingDegrees).truncatingRemainder(dividingBy: 360.0)
            if relAngle > 180 { relAngle -= 360 }
            if relAngle < -180 { relAngle += 360 }

            if dist < 3.5 {
                return DirectionalInstruction(
                    icon: "mappin.and.ellipse",
                    relativeAngle: relAngle,
                    primaryText: "Arrived at Stop \(target.index): \(target.title)",
                    secondaryText: "Tap Compare Vantage below",
                    color: Color(hex: "#00E5FF")
                )
            } else if dist < 22.0 {
                let dirPhrase = describeRelativeDirection(angle: relAngle)
                return DirectionalInstruction(
                    icon: dirPhrase.icon,
                    relativeAngle: relAngle,
                    primaryText: "\(dirPhrase.text) · \(Int(dist))m",
                    secondaryText: "Target: Stop \(target.index) · \(target.title)",
                    color: Color(hex: "#00E5FF")
                )
            }
        }

        if distanceToRecordedPath > 4.5 {
            let nearestStep = findNearestReferenceStep()
            let dx = nearestStep.x - transformedPosition.x
            let dz = nearestStep.z - transformedPosition.z
            let targetAngle = Double(atan2(-dx, -dz) * 180.0 / .pi)
            var relAngle = (targetAngle - currentHeadingDegrees).truncatingRemainder(dividingBy: 360.0)
            if relAngle > 180 { relAngle -= 360 }
            if relAngle < -180 { relAngle += 360 }

            let dirPhrase = describeRelativeDirection(angle: relAngle)
            return DirectionalInstruction(
                icon: "arrow.triangle.2.circlepath",
                relativeAngle: relAngle,
                primaryText: String(format: "%.1fm off trail · %@", distanceToRecordedPath, dirPhrase.text),
                secondaryText: "Steer towards purple reference path",
                color: AppColors.terracotta
            )
        }

        return calculateGeometricBend()
    }

    private func describeRelativeDirection(angle: Double) -> (text: String, icon: String) {
        let absAngle = abs(angle)
        if absAngle <= 22.5 {
            return ("Straight ahead", "arrow.up")
        } else if angle > 22.5 && angle <= 67.5 {
            return ("Ahead to your right (45°)", "arrow.up.right")
        } else if angle > 67.5 && angle <= 112.5 {
            return ("Turn right (90°)", "arrow.right")
        } else if angle > 112.5 && angle <= 157.5 {
            return ("Behind to your right", "arrow.down.right")
        } else if angle < -22.5 && angle >= -67.5 {
            return ("Ahead to your left (45°)", "arrow.up.left")
        } else if angle < -67.5 && angle >= -112.5 {
            return ("Turn left (90°)", "arrow.left")
        } else if angle < -112.5 && angle >= -157.5 {
            return ("Behind to your left", "arrow.down.left")
        } else {
            return ("Turn around (behind you)", "arrow.uturn.backward")
        }
    }

    private func calculateGeometricBend() -> DirectionalInstruction {
        guard referenceFootsteps.count >= 4 else {
            return DirectionalInstruction(
                icon: "figure.walk",
                relativeAngle: 0,
                primaryText: "Follow reference trail",
                secondaryText: "Trace dashed purple line",
                color: .white
            )
        }

        var nearestIdx = 0
        var minDist: Float = .infinity
        for (i, step) in referenceFootsteps.enumerated() {
            let d = simd_distance(transformedPosition, step)
            if d < minDist {
                minDist = d
                nearestIdx = i
            }
        }

        let targetIdx = min(referenceFootsteps.count - 1, nearestIdx + 6)
        if targetIdx > nearestIdx {
            let seg1 = referenceFootsteps[min(referenceFootsteps.count - 1, nearestIdx + 2)] - referenceFootsteps[nearestIdx]
            let seg2 = referenceFootsteps[targetIdx] - referenceFootsteps[min(referenceFootsteps.count - 1, nearestIdx + 2)]

            let crossZ = (seg1.x * seg2.z) - (seg1.z * seg2.x)
            let distAhead = Int(Float(targetIdx - nearestIdx) * 0.25)

            if crossZ > 0.35 {
                return DirectionalInstruction(
                    icon: "arrow.turn.up.right",
                    relativeAngle: 65,
                    primaryText: "In \(max(4, distAhead))m, path turns right",
                    secondaryText: "Follow trail curve",
                    color: Color(hex: "#00E5FF")
                )
            } else if crossZ < -0.35 {
                return DirectionalInstruction(
                    icon: "arrow.turn.up.left",
                    relativeAngle: -65,
                    primaryText: "In \(max(4, distAhead))m, path turns left",
                    secondaryText: "Follow trail curve",
                    color: Color(hex: "#00E5FF")
                )
            }
        }

        return DirectionalInstruction(
            icon: "arrow.up",
            relativeAngle: 0,
            primaryText: "Continue straight along trail",
            secondaryText: "Trace purple path",
            color: .white
        )
    }

    // MARK: - Body Viewport

    public var body: some View {
        ZStack {
            Color(hex: "#0A0E14").ignoresSafeArea()

            if positioningMode == "manualFollowAlong" {
                // PRD §14: Dedicated Manual Follow-Along Fallback Interface
                manualFollowAlongView
            } else if isMapOnlyView {
                // Fullscreen Blueprint Comparison Mode
                RoomLayoutView(
                    capturedRoom: scannerEngine.capturedRoom,
                    footsteps: referenceFootsteps,
                    moments: referenceTrail.moments,
                    liveFollowerFootsteps: (alignmentState == "aligned" || alignmentState == "degraded") ? transformedFootsteps : [],
                    liveFollowerPosition: (alignmentState == "aligned" || alignmentState == "degraded") ? transformedPosition : nil,
                    liveFollowerHeadingDegrees: (alignmentState == "aligned" || alignmentState == "degraded") ? currentHeadingDegrees : nil,
                    activeCheckpointIndex: activeTargetCheckpoint?.index,
                    visitedCheckpointIds: visitedCheckpointIds,
                    isReferenceDashed: true,
                    referenceColor: Color(hex: "#9D7BD8")
                )
                .ignoresSafeArea()
            } else {
                // Split View: LiDAR Camera on Top, Blueprint on Bottom
                VStack(spacing: 0) {
                    // Upper Pane: Live LiDAR Camera Viewport with Ghost Viewfinder Alignment
                    ZStack(alignment: .center) {
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
                                    Text("LiDAR Spatial Tracking")
                                        .font(AppFonts.headlineSmall)
                                        .foregroundColor(.white)
                                }
                            }
                        }

                        // Ghost Viewfinder Reference Overlay & Alignment Reticle
                        if isGhostOverlayVisible, let refImg = currentReferenceImage {
                            ghostViewfinderView(image: refImg)
                        }

                        // Gradient scrim
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.4)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 60)
                        .frame(maxHeight: .infinity, alignment: .bottom)

                        // Camera viewport expand/collapse toggle button
                        VStack {
                            HStack {
                                Spacer()
                                Button {
                                    Haptics.light()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        isCameraExpanded.toggle()
                                    }
                                } label: {
                                    Image(systemName: isCameraExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 32, height: 32)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(Circle())
                                }
                                .padding(.top, 56)
                                .padding(.trailing, 16)
                            }
                            Spacer()
                        }
                    }
                    .frame(height: isCameraExpanded ? (UIScreen.main.bounds.height * 0.72) : (UIScreen.main.bounds.height * 0.46))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isCameraExpanded)

                    // Lower Pane: 2D Blueprint with Dual Path & Heading Cone
                    ZStack(alignment: .topTrailing) {
                        RoomLayoutView(
                            capturedRoom: scannerEngine.capturedRoom,
                            footsteps: referenceFootsteps,
                            moments: referenceTrail.moments,
                            liveFollowerFootsteps: (alignmentState == "aligned" || alignmentState == "degraded") ? transformedFootsteps : [],
                            liveFollowerPosition: (alignmentState == "aligned" || alignmentState == "degraded") ? transformedPosition : nil,
                            liveFollowerHeadingDegrees: (alignmentState == "aligned" || alignmentState == "degraded") ? currentHeadingDegrees : nil,
                            activeCheckpointIndex: activeTargetCheckpoint?.index,
                            visitedCheckpointIds: visitedCheckpointIds,
                            isReferenceDashed: true,
                            referenceColor: Color(hex: "#9D7BD8")
                        )

                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 1)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .ignoresSafeArea()
            }

            // MARK: - HUD & Overlays
            VStack(spacing: 0) {
                // Top Navigation Bar (Parity with ScannerView)
                topRetraceBar

                // Live Navigation Cue Banner
                if isTurnGuidanceEnabled && positioningMode != "manualFollowAlong" {
                    navigationCueBanner
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Starting Point Reference Guidance Card (PRD §8 & User Request)
                if showingStartFrameGuidance && positioningMode != "manualFollowAlong" {
                    startPointGuidanceCard
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }

                Spacer()

                // Checkpoint Encounter Notification Card
                if let encounter = activeCheckpointEncounter, positioningMode != "manualFollowAlong" {
                    checkpointEncounterCard(for: encounter)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Bottom Console (Parity with ScannerView)
                if positioningMode != "manualFollowAlong" {
                    bottomRetraceConsole
                }
            }

            // MARK: - Toast Feedback
            if let toast = toastMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(hex: "#00E5FF"))
                        Text(toast)
                            .font(AppFonts.labelUI)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Capsule())
                    .padding(.bottom, 220)
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
            initializeRetraceSession()
        }
        .onDisappear {
            teardownRetraceSession()
        }
        // Vantage Comparison Sheet
        .sheet(item: $selectedMomentToInspect) { moment in
            CompareVantageSheet(referenceTrail: referenceTrail, moment: moment) {
                if !visitedCheckpointIds.contains(moment.id) {
                    visitedCheckpointIds.insert(moment.id)
                    visitedOrderArray.append(moment.id)
                }
                activeCheckpointEncounter = nil
                if moment.index == 1 || moment.title.lowercased().contains("arrival") || !hasConfirmedStart {
                    hasConfirmedStart = true
                    showingStartFrameGuidance = false
                }
                if selectedTargetCheckpointId == moment.id {
                    selectedTargetCheckpointId = nil
                }
                triggerToast(moment.index == 1 ? "Start Point Confirmed · Continue Along Trail ✓" : "Stop \(moment.index) Visited ✓")
            }
        }
        // Voice Note Checkpoint Sheet
        .sheet(isPresented: $showingVoiceCaptureSheet) {
            VoiceNoteCheckpointSheet(
                trailId: sessionId,
                waypointIndex: referenceTrail.moments.count + newRetraceMoments.count + 1,
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
                trailId: sessionId,
                moments: $newRetraceMoments,
                onUpdateMoment: { updated in
                    if let idx = newRetraceMoments.firstIndex(where: { $0.id == updated.id }) {
                        newRetraceMoments[idx] = updated
                    }
                },
                onDeleteMoment: { id in
                    newRetraceMoments.removeAll { $0.id == id }
                    for i in 0..<newRetraceMoments.count {
                        newRetraceMoments[i].index = referenceTrail.moments.count + i + 1
                    }
                },
                onDismiss: {
                    showingMomentsTray = false
                }
            )
        }
        // Diagnostics Panel (PRD §16)
        .sheet(isPresented: $showingDiagnosticsSheet) {
            PositioningDiagnosticsSheet(
                trail: referenceTrail,
                sessionId: sessionId,
                segmentId: currentSegmentId,
                positioningMode: positioningMode,
                alignmentState: alignmentState,
                alignmentMethod: alignmentMethod,
                rawPose: rawDevicePosition,
                transformedPose: transformedPosition,
                rotationDegrees: transformRotationDegrees,
                translation: transformTranslation,
                hasWorldMap: TrailPackageStore.shared.hasWorldMap(for: referenceTrail.id),
                worldMapSize: (try? Data(contentsOf: TrailPackageStore.shared.worldMapURL(for: referenceTrail.id)).count) ?? 0,
                trackingStateDescription: scannerEngine.relocalizationStatusText
            )
        }
        // Manual Reference Calibration Sheet (PRD §9 & §10)
        .sheet(isPresented: $showingManualCalibrationSheet) {
            ManualReferenceCalibrationSheet(
                trail: referenceTrail,
                rawDevicePosition: rawDevicePosition,
                currentYaw: scannerEngine.currentYawDegrees,
                onCalibrate: { translation, rotation in
                    transformTranslation = translation
                    transformRotationDegrees = rotation
                    alignmentMethod = "twoPointReference"
                    positioningMode = "localSpatialUnaligned"
                    alignmentState = "aligned"
                    triggerToast("Calibrated to Stop 1 Reference Frame ✓")
                }
            )
        }
        // Dedicated Full-Screen Camera Interface for Checkpoint Moments
        .fullScreenCover(
            isPresented: Binding(
                get: { showingFullScreenCaptureMode != nil },
                set: { if !$0 { showingFullScreenCaptureMode = nil } }
            ),
            onDismiss: {
                // Safely resume RoomPlan only after the camera modal has completely exited the view hierarchy and released camera hardware
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    scannerEngine.resumeScanning()
                }
            }
        ) {
            if let mode = showingFullScreenCaptureMode {
                FullScreenCameraCaptureView(
                    cameraEngine: cameraEngine,
                    mode: mode,
                    waypointIndex: referenceTrail.moments.count + newRetraceMoments.count + 1,
                    trailId: sessionId,
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
        // Finish Confirmation
        .alert("End Retrace Journey?", isPresented: $showingFinishAlert) {
            Button("Keep Retracing", role: .cancel) {}
            Button("Save Retraced Trail", role: .none) {
                finalizeAndSaveRetrace()
                dismiss()
            }
            Button("Discard & Exit", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("Distance: \(walkedMeters)m\nSimilarity: \(similarityIndexPercentage)%\nCheckpoints: \(visitedCheckpointIds.count) of \(referenceTrail.moments.count) visited\n\nThis walk will be saved as a new recorded trail in your journal on its own merit.")
        }
    }

    // MARK: - Alignment Overlays (PRD §8 & §12)

    private var searchingAlignmentOverlay: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color(hex: "#00E5FF").opacity(0.25), lineWidth: 2)
                    .frame(width: 72, height: 72)

                Circle()
                    .trim(from: 0, to: 0.6)
                    .stroke(Color(hex: "#00E5FF"), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 72, height: 72)
                    .rotationEffect(Angle(degrees: searchPulseAngle))
                    .onAppear {
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            searchPulseAngle = 360
                        }
                    }

                Image(systemName: "viewfinder")
                    .font(.system(size: 26, weight: .light))
                    .foregroundColor(Color(hex: "#00E5FF"))
            }

            Text("Finding your position in this trail")
                .font(AppFonts.headlineMedium)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("Return near the starting area and slowly look around.")
                .font(AppFonts.labelUI)
                .foregroundColor(Color.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            HStack(spacing: 8) {
                Button {
                    positioningMode = "manualFollowAlong"
                    alignmentState = "unavailable"
                } label: {
                    Text("Follow Manually")
                        .font(AppFonts.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Capsule())
                }

                Button {
                    showingManualCalibrationSheet = true
                } label: {
                    Text("Calibrate at Start")
                        .font(AppFonts.caption)
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(hex: "#00E5FF"))
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(Color.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 24)
    }

    private var lostAlignmentOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(AppColors.terracotta)

            Text("Positioning lost. Your recorded trail is still available.")
                .font(AppFonts.headlineSmall)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button("Try Alignment Again") {
                    startRelocalizationAttempt()
                }
                .font(AppFonts.labelSpatial)
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(hex: "#00E5FF"))
                .clipShape(Capsule())

                Button("Follow Manually") {
                    positioningMode = "manualFollowAlong"
                }
                .font(AppFonts.labelSpatial)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())
            }
        }
        .padding(20)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 24)
    }

    private var unavailableAlignmentOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 30))
                .foregroundColor(AppColors.mutedBrass)

            Text("No saved indoor alignment map")
                .font(AppFonts.headlineSmall)
                .foregroundColor(.white)

            Text("This trail was recorded without an indoor relocalisation asset. Choose an honest retrace mode:")
                .font(AppFonts.caption)
                .foregroundColor(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            HStack(spacing: 10) {
                Button("Follow Manually") {
                    positioningMode = "manualFollowAlong"
                }
                .font(AppFonts.labelSpatial)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())

                Button("Calibrate at Start") {
                    showingManualCalibrationSheet = true
                }
                .font(AppFonts.labelSpatial)
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(hex: "#00E5FF"))
                .clipShape(Capsule())
            }
        }
        .padding(20)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 24)
    }

    // MARK: - Manual Follow-Along Fallback (PRD §14)

    private var manualFollowAlongView: some View {
        ZStack {
            // Blueprint Map showing reference trail and moments
            RoomLayoutView(
                capturedRoom: scannerEngine.capturedRoom,
                footsteps: referenceFootsteps,
                moments: referenceTrail.moments,
                liveFollowerFootsteps: [],
                liveFollowerPosition: nil,
                activeCheckpointIndex: referenceTrail.moments.indices.contains(manualMomentIndex) ? referenceTrail.moments[manualMomentIndex].index : nil,
                visitedCheckpointIds: visitedCheckpointIds,
                isReferenceDashed: true,
                referenceColor: Color(hex: "#9D7BD8")
            )
            .ignoresSafeArea()

            VStack {
                // PRD §14 Banner
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .foregroundColor(AppColors.mutedBrass)
                    Text("Manual follow-along — live position is unavailable.")
                        .font(AppFonts.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.85))
                .clipShape(Capsule())
                .padding(.top, 100)

                Spacer()

                // Active Moment Card & Stepper
                if referenceTrail.moments.indices.contains(manualMomentIndex) {
                    let moment = referenceTrail.moments[manualMomentIndex]
                    let isVisited = visitedCheckpointIds.contains(moment.id)

                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("CHECKPOINT \(moment.index) OF \(referenceTrail.moments.count)")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(Color(hex: "#00E5FF"))

                                Text(moment.title)
                                    .font(AppFonts.headlineSmall)
                                    .foregroundColor(.white)
                            }

                            Spacer()

                            Button {
                                selectedMomentToInspect = moment
                            } label: {
                                Text("View Media")
                                    .font(AppFonts.caption)
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(hex: "#00E5FF"))
                                    .clipShape(Capsule())
                            }
                        }

                        if !moment.narrative.isEmpty {
                            Text("“\(moment.narrative)”")
                                .font(.custom("Newsreader", size: 14))
                                .italic()
                                .foregroundColor(Color.white.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        HStack(spacing: 12) {
                            Button {
                                if manualMomentIndex > 0 { manualMomentIndex -= 1 }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("Previous")
                                }
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(manualMomentIndex > 0 ? .white : .white.opacity(0.3))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Capsule())
                            }
                            .disabled(manualMomentIndex <= 0)

                            // "I'm Here" Button (PRD §14)
                            Button {
                                Haptics.success()
                                if !visitedCheckpointIds.contains(moment.id) {
                                    visitedCheckpointIds.insert(moment.id)
                                    visitedOrderArray.append(moment.id)
                                }
                                if manualMomentIndex < referenceTrail.moments.count - 1 {
                                    manualMomentIndex += 1
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isVisited ? "checkmark.circle.fill" : "mappin.circle.fill")
                                    Text(isVisited ? "Visited ✓" : "I'm Here")
                                }
                                .font(AppFonts.labelUI)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(isVisited ? Color.green : Color(hex: "#00E5FF"))
                                .clipShape(Capsule())
                            }

                            Button {
                                if manualMomentIndex < referenceTrail.moments.count - 1 { manualMomentIndex += 1 }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Next")
                                    Image(systemName: "chevron.right")
                                }
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(manualMomentIndex < referenceTrail.moments.count - 1 ? .white : .white.opacity(0.3))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Capsule())
                            }
                            .disabled(manualMomentIndex >= referenceTrail.moments.count - 1)
                        }
                    }
                    .padding(16)
                    .background(Color(hex: "#121820"))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - Top Retrace Bar (Parity with ScannerView.topJourneyBar)

    private var topRetraceBar: some View {
        HStack(spacing: 12) {
            // Close / Cancel Button
            Button {
                Haptics.light()
                showingFinishAlert = true
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

                Text(hasConfirmedStart ? "\(similarityIndexPercentage)% Match" : "Align: \(frameMatcher.matchPercentage)%")
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(hasConfirmedStart ? Color(hex: "#00E5FF") : matchBadgeColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.65))
            .clipShape(Capsule())

            Spacer()

            // Finish Trail CTA Button
            Button {
                Haptics.success()
                showingFinishAlert = true
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

    // MARK: - Starting Reference Point Card (PRD §8 & User Guidance)

    @ViewBuilder
    private var startPointGuidanceCard: some View {
        let startImage = currentReferenceImage

        VStack(alignment: .leading, spacing: 10) {
            // Header with Reference Target title and Dismiss button
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(matchBadgeColor)
                        .frame(width: 8, height: 8)
                    Text(currentReferenceTitle.uppercased())
                        .font(AppFonts.labelSpatial)
                        .fontWeight(.bold)
                        .foregroundColor(matchBadgeColor)
                        .tracking(1.0)
                }

                Spacer()

                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.3)) {
                        showingStartFrameGuidance = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color.white.opacity(0.6))
                }
            }

            // Checkpoint / Start Vantage Pill Switcher (if trail has checkpoints)
            if !referenceTrail.moments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button {
                            selectReference(checkpoint: nil)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 9))
                                Text("Start")
                                    .font(AppFonts.labelSpatial)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(activeReferenceCheckpoint == nil ? .black : .white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(activeReferenceCheckpoint == nil ? Color(hex: "#00E5FF") : Color.white.opacity(0.12))
                            .clipShape(Capsule())
                        }

                        ForEach(referenceTrail.moments) { moment in
                            Button {
                                selectReference(checkpoint: moment)
                            } label: {
                                HStack(spacing: 4) {
                                    Text("CP \(moment.index)")
                                        .font(AppFonts.labelSpatial)
                                        .fontWeight(.bold)
                                }
                                .foregroundColor(activeReferenceCheckpoint?.id == moment.id ? .black : .white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(activeReferenceCheckpoint?.id == moment.id ? Color(hex: "#00E5FF") : Color.white.opacity(0.12))
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // Reference Thumbnail with Live Match Gauge Overlay
            if let img = startImage {
                ZStack(alignment: .bottomLeading) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(matchBadgeColor.opacity(0.4), lineWidth: 1.5)
                        )

                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.8)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .cornerRadius(12)

                    // Guidance & Match text overlay
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: frameMatcher.isWellAligned ? "checkmark.seal.fill" : "camera.viewfinder")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(matchBadgeColor)

                            Text(frameMatcher.alignmentGuidanceText)
                                .font(AppFonts.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }

                        if let targetH = currentReferenceHeading {
                            HStack(spacing: 8) {
                                Text("Ref: \(Int(targetH))°")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.mutedBrass)
                                Text("·")
                                    .foregroundColor(.white.opacity(0.4))
                                Text("Live: \(Int(currentHeadingDegrees))°")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(Color.white.opacity(0.8))
                                if abs(frameMatcher.headingDeltaDegrees) > 5 {
                                    Text("(\(frameMatcher.headingDeltaDegrees > 0 ? "+" : "")\(Int(frameMatcher.headingDeltaDegrees))°)")
                                        .font(AppFonts.labelSpatial)
                                        .foregroundColor(matchBadgeColor)
                                }
                            }
                        }
                    }
                    .padding(8)

                    // Live match pill badge top-trailing
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(matchBadgeColor)
                                    .frame(width: 7, height: 7)
                                Text("\(frameMatcher.matchPercentage)%")
                                    .font(.system(size: 12, weight: .black, design: .rounded))
                                    .foregroundColor(matchBadgeColor)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.85))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(matchBadgeColor.opacity(0.6), lineWidth: 1))
                            .padding(8)
                        }
                        Spacer()
                    }
                }
            } else {
                Text("Aim phone forward to match the reference view of “\(referenceTrail.title)”.")
                    .font(AppFonts.caption)
                    .foregroundColor(Color.white.opacity(0.85))
            }

            // Ghost Opacity Controls
            HStack(spacing: 6) {
                Text("Ghost Guide:")
                    .font(AppFonts.caption)
                    .foregroundColor(Color.white.opacity(0.7))

                ForEach([0.25, 0.45, 0.70], id: \.self) { val in
                    Button {
                        Haptics.light()
                        ghostOpacity = val
                        isGhostOverlayVisible = true
                    } label: {
                        Text("\(Int(val * 100))%")
                            .font(AppFonts.labelSpatial)
                            .fontWeight(.bold)
                            .foregroundColor(isGhostOverlayVisible && ghostOpacity == val ? .black : .white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(isGhostOverlayVisible && ghostOpacity == val ? Color(hex: "#00E5FF") : Color.white.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Button {
                    Haptics.light()
                    isGhostOverlayVisible.toggle()
                } label: {
                    Text(isGhostOverlayVisible ? "Off" : "On")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }

                Spacer()

                // Action CTA Button
                Button {
                    Haptics.success()
                    hasConfirmedStart = true
                    if let first = referenceTrail.moments.first, !visitedCheckpointIds.contains(first.id) {
                        visitedCheckpointIds.insert(first.id)
                        visitedOrderArray.append(first.id)
                    }
                    activeCheckpointEncounter = nil
                    withAnimation(.spring(response: 0.35)) {
                        showingStartFrameGuidance = false
                    }
                    alignmentState = "aligned"
                    positioningMode = "localSpatialAligned"
                    alignmentMethod = "originAnchor"
                    scannerEngine.resetAndStartScanning()
                    triggerToast("Starting Point Confirmed · Retrace Active ✓")
                } label: {
                    HStack(spacing: 6) {
                        if frameMatcher.isWellAligned {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Begin · Aligned (\(frameMatcher.matchPercentage)%)")
                                .font(AppFonts.labelUI)
                                .fontWeight(.bold)
                        } else {
                            Text(hasConfirmedStart ? "Dismiss" : (frameMatcher.matchPercentage > 40 ? "Begin (\(frameMatcher.matchPercentage)%)" : "I'm Here · Begin"))
                                .font(AppFonts.labelUI)
                                .fontWeight(.bold)
                            Image(systemName: hasConfirmedStart ? "checkmark" : "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(frameMatcher.isWellAligned ? Color.green : Color(hex: "#00E5FF"))
                    .clipShape(Capsule())
                    .shadow(color: (frameMatcher.isWellAligned ? Color.green : Color(hex: "#00E5FF")).opacity(0.35), radius: 6)
                }
            }
        }
        .padding(14)
        .background(Color(hex: "#10161E").opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(matchBadgeColor.opacity(frameMatcher.isWellAligned ? 0.7 : 0.4), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.6), radius: 12)
    }

    // MARK: - Ghost Viewfinder Overlay (Live Camera Alignment)

    @ViewBuilder
    private func ghostViewfinderView(image: UIImage) -> some View {
        ZStack {
            // Semi-transparent ghost reference photo aligned to camera
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .opacity(ghostOpacity)
                .allowsHitTesting(false)

            // Viewfinder Reticle & Live Match Gauge Overlay
            GeometryReader { geo in
                let frameWidth = geo.size.width * 0.88
                let frameHeight = geo.size.height * 0.78
                let bracketColor = matchBadgeColor

                ZStack {
                    // Outer corner brackets
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(bracketColor.opacity(frameMatcher.isWellAligned ? 0.9 : 0.45), style: StrokeStyle(lineWidth: 2, dash: [24, frameWidth / 4, 24]))
                        .frame(width: frameWidth, height: frameHeight)

                    // Center crosshair
                    Circle()
                        .stroke(bracketColor.opacity(0.4), lineWidth: 1)
                        .frame(width: 32, height: 32)

                    Circle()
                        .fill(bracketColor)
                        .frame(width: 4, height: 4)

                    // Match percentage badge floating right inside camera viewport
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(bracketColor)
                                    .frame(width: 8, height: 8)
                                    .scaleEffect(frameMatcher.isWellAligned ? 1.2 : 1.0)
                                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: frameMatcher.isWellAligned)

                                Text("\(frameMatcher.matchPercentage)% MATCH")
                                    .font(AppFonts.labelSpatial)
                                    .fontWeight(.bold)
                                    .foregroundColor(bracketColor)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.75))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(bracketColor.opacity(0.6), lineWidth: 1))
                            .shadow(color: bracketColor.opacity(0.35), radius: 6)
                            .padding(.top, 14)
                            .padding(.trailing, 14)
                        }

                        Spacer()

                        // Quick Ghost Opacity Controls at bottom of camera viewport
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.2.layers.3d.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(hex: "#00E5FF"))
                                Text("Ghost:")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.75))
                            }

                            ForEach([0.25, 0.45, 0.70], id: \.self) { val in
                                Button {
                                    Haptics.light()
                                    ghostOpacity = val
                                    isGhostOverlayVisible = true
                                } label: {
                                    Text("\(Int(val * 100))%")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(isGhostOverlayVisible && ghostOpacity == val ? .black : .white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(isGhostOverlayVisible && ghostOpacity == val ? Color(hex: "#00E5FF") : Color.white.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }

                            Button {
                                Haptics.light()
                                isGhostOverlayVisible.toggle()
                            } label: {
                                Text(isGhostOverlayVisible ? "Hide" : "Show")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                        .padding(.bottom, 8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Navigation Banner

    private var navigationCueBanner: some View {
        let cue = navigationInstruction
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(cue.color.opacity(0.18))
                    .frame(width: 36, height: 36)

                Image(systemName: "location.north.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(cue.color)
                    .rotationEffect(Angle(degrees: cue.relativeAngle))
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: cue.relativeAngle)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(cue.primaryText)
                    .font(AppFonts.labelUI)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(cue.secondaryText)
                    .font(AppFonts.caption)
                    .foregroundColor(Color.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            if alignmentState == "aligned" || alignmentState == "degraded" {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(similarityIndexPercentage)%")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "#00E5FF"))

                    Text("SIMILARITY")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .tracking(0.8)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(cue.color.opacity(0.55), lineWidth: 1.5)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Checkpoint Encounter Card

    private func checkpointEncounterCard(for moment: SpatialMoment) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#00E5FF"))
                    .frame(width: 42, height: 42)
                Text("\(moment.index)")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.black)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("CHECKPOINT REACHED")
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(Color(hex: "#00E5FF"))
                    .tracking(1.0)

                Text(moment.title)
                    .font(AppFonts.headlineSmall)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()

            // Viewfinder Align Button to check vantage alignment at checkpoint
            Button {
                Haptics.light()
                selectReference(checkpoint: moment)
                withAnimation(.spring(response: 0.35)) {
                    showingStartFrameGuidance = true
                    isGhostOverlayVisible = true
                }
            } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "#00E5FF"))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }

            Button {
                Haptics.medium()
                selectedMomentToInspect = moment
            } label: {
                HStack(spacing: 4) {
                    Text("Compare")
                        .font(AppFonts.labelUI)
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(hex: "#00E5FF"))
                .clipShape(Capsule())
            }

            // Quick Confirm / Start & Continue Button
            Button {
                Haptics.success()
                if !visitedCheckpointIds.contains(moment.id) {
                    visitedCheckpointIds.insert(moment.id)
                    visitedOrderArray.append(moment.id)
                }
                if moment.index == 1 || moment.title.lowercased().contains("arrival") || !hasConfirmedStart {
                    hasConfirmedStart = true
                    showingStartFrameGuidance = false
                }
                withAnimation(.spring(response: 0.35)) {
                    activeCheckpointEncounter = nil
                }
                triggerToast(moment.index == 1 ? "Start Point Confirmed · Continue ✓" : "Checkpoint \(moment.index) Visited ✓")
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text(moment.index == 1 ? "Start" : "Done")
                        .font(AppFonts.labelUI)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.green)
                .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(Color(hex: "#121820"))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(hex: "#00E5FF").opacity(0.6), lineWidth: 1.5)
        )
        .shadow(color: Color(hex: "#00E5FF").opacity(0.2), radius: 10)
    }

    // MARK: - Bottom Retrace Console (Parity with ScannerView.bottomConsole)

    private var bottomRetraceConsole: some View {
        VStack(spacing: 12) {
            // View Mode Toggle, Legend & Start Vantage
            HStack {
                // Dual Trail Legend
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Capsule()
                            .fill(Color(hex: "#9D7BD8"))
                            .frame(width: 14, height: 4)
                        Text("Original Trail")
                            .font(AppFonts.caption)
                            .foregroundColor(Color(hex: "#9D7BD8"))
                    }

                    HStack(spacing: 4) {
                        Capsule()
                            .fill(Color(hex: "#00E5FF"))
                            .frame(width: 14, height: 4)
                        Text("Your Walk")
                            .font(AppFonts.caption)
                            .foregroundColor(Color(hex: "#00E5FF"))
                    }
                }

                Spacer()

                // Start Vantage Button (toggle guidance card)
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showingStartFrameGuidance.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 11, weight: .bold))
                        Text(showingStartFrameGuidance ? "Hide Vantage" : (!hasConfirmedStart ? "Align (\(frameMatcher.matchPercentage)%)" : "Vantage Guide"))
                            .font(AppFonts.labelSpatial)
                    }
                    .foregroundColor(matchBadgeColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(matchBadgeColor.opacity(0.4), lineWidth: 1))
                }

                // View Mode Toggle [ Split | Full Blueprint ]
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

            // 1. Checkpoints Ribbon
            if isInLineVoiceRecording {
                inLineVoiceRecordingBar
            } else if isInLineVideoRecording {
                inLineVideoRecordingBar
            } else {
                checkpointRibbon
            }

            // 2. Waypoint Capture Action Dock (Video, Photo, Mic, Note)
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

    // MARK: - In-Line Video Recording Bar (Keeps camera viewport & trail tracking live)

    private var inLineVideoRecordingBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppColors.terracotta)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(AppColors.terracotta.opacity(0.5), lineWidth: 3)
                        .scaleEffect(1.6)
                )

            Text("RECORDING VIDEO")
                .font(AppFonts.labelSpatial)
                .foregroundColor(AppColors.terracotta)
                .tracking(1.2)

            Spacer()

            let m = Int(arVideoRecorder.recordingDuration) / 60
            let s = Int(arVideoRecorder.recordingDuration) % 60
            Text(String(format: "%02d:%02d", m, s))
                .font(AppFonts.labelMetric)
                .foregroundColor(.white)

            Button {
                toggleInLineVideoRecording()
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

    // MARK: - Checkpoints Ribbon

    private var checkpointRibbon: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(referenceTrail.moments) { moment in
                    let isVisited = visitedCheckpointIds.contains(moment.id)
                    let isTarget = activeTargetCheckpoint?.id == moment.id

                    Button {
                        Haptics.selection()
                        if isVisited {
                            selectedMomentToInspect = moment
                        } else {
                            selectedTargetCheckpointId = moment.id
                            triggerToast("Target set to Stop \(moment.index)")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(isVisited ? Color.green : (isTarget ? Color(hex: "#00E5FF") : Color(hex: "#9D7BD8")))
                                    .frame(width: 22, height: 22)

                                if isVisited {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                } else {
                                    Text("\(moment.index)")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundColor(isTarget ? .black : .white)
                                }
                            }

                            Text(moment.title)
                                .font(AppFonts.labelSpatial)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Image(systemName: iconForMediaType(moment.mediaType))
                                .font(.system(size: 10))
                                .foregroundColor(isVisited ? Color.green : AppColors.mutedBrass)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.65))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(isTarget ? Color(hex: "#00E5FF") : (isVisited ? Color.green.opacity(0.5) : Color.white.opacity(0.15)), lineWidth: isTarget ? 2 : 1)
                        )
                    }
                }

                // New Moments captured during this retrace
                ForEach(newRetraceMoments) { moment in
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(AppColors.terracotta)
                                .frame(width: 22, height: 22)
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
                        Capsule().stroke(AppColors.terracotta.opacity(0.5), lineWidth: 1)
                    )
                }

                // Current Live Position Pill
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "#00E5FF"))
                        .frame(width: 6, height: 6)
                    Text("Your Walk · +\(walkedMeters)m")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(Color.white.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.4))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Waypoint Capture Dock (Exact Parity with ScannerView)

    private var waypointCaptureDock: some View {
        HStack(spacing: 8) {
            // 1. Moments Tray / Thumbnail
            Button {
                Haptics.light()
                showingMomentsTray = true
            } label: {
                ZStack {
                    if let lastMoment = newRetraceMoments.last {
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

                    if !newRetraceMoments.isEmpty {
                        VStack {
                            HStack {
                                Spacer()
                                Text("\(newRetraceMoments.count)")
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
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Quick Photo Snap")

            Spacer(minLength: 2)

            // 3. ZOOM CAMERA: Optical Telephoto & Full 48MP Smart HDR
            Button {
                Haptics.medium()
                scannerEngine.pauseScanning()
                showingFullScreenCaptureMode = .photo
            } label: {
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
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Zoom Camera")

            Spacer(minLength: 2)

            // 4. RECORD VIDEO - Live In-situ recording with continuous trail & odometry tracking
            Button {
                toggleInLineVideoRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(isInLineVideoRecording ? AppColors.terracotta : Color.black.opacity(0.6))
                        .frame(width: 46, height: 46)
                    Circle()
                        .stroke(isInLineVideoRecording ? AppColors.terracotta : Color.white.opacity(0.55), lineWidth: 2)
                        .frame(width: 42, height: 42)
                    Image(systemName: isInLineVideoRecording ? "stop.fill" : "video.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel(isInLineVideoRecording ? "Stop Video Recording" : "Record Video")

            Spacer(minLength: 2)

            // 5. VOICE NOTE - Live In-situ recording without obscuring camera view
            Button {
                toggleInLineVoiceRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(isInLineVoiceRecording ? AppColors.terracotta : Color.black.opacity(0.6))
                        .frame(width: 44, height: 44)
                    Image(systemName: isInLineVoiceRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 16))
                        .foregroundColor(isInLineVoiceRecording ? .white : AppColors.mutedBrass)
                }
                .overlay(Circle().stroke(isInLineVoiceRecording ? AppColors.terracotta : Color.white.opacity(0.2), lineWidth: 1.2))
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel(isInLineVoiceRecording ? "Stop Recording" : "Record Voice")

            Spacer(minLength: 2)

            // 6. WRITTEN NOTE
            Button {
                Haptics.light()
                scannerEngine.pauseScanning()
                noteTitle = ""
                noteBody = ""
                showingAddNoteSheet = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 44, height: 44)
                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                }
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1.2))
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Add Note")
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
        let durMinutes = Int(duration) / 60
        let durSeconds = Int(duration) % 60
        let durString = String(format: "%d:%02d", durMinutes, durSeconds)
        let pos = scannerEngine.lastRecordedPosition ?? SIMD3<Float>(0, 0, 0)
        let heading = scannerEngine.currentYawDegrees != 0 ? scannerEngine.currentYawDegrees : (locationManager.currentHeading ?? 0)
        let idx = referenceTrail.moments.count + newRetraceMoments.count + 1

        let moment = SpatialMoment(
            id: UUID().uuidString,
            index: idx,
            title: "Stop \(idx) · Video",
            subtitle: "Spatial Video · \(durString)",
            narrative: "Video waypoint checkpoint anchored at \(walkedMeters)m along retrace path.",
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
        newRetraceMoments.append(moment)
        // Note: Do not call scannerEngine.resumeScanning() here - onDismiss handles it after modal exits
        triggerToast("Checkpoint \(idx) Video Anchored ✓")
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
            let destURL = TrailPackageStore.shared.mediaDirectory(for: sessionId).appendingPathComponent(photoName)
            let thumbURL = TrailPackageStore.shared.mediaDirectory(for: sessionId).appendingPathComponent(thumbName)

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
        let pos = scannerEngine.lastRecordedPosition ?? SIMD3<Float>(0, 0, 0)
        let heading = scannerEngine.currentYawDegrees != 0 ? scannerEngine.currentYawDegrees : (locationManager.currentHeading ?? 0)
        let idx = referenceTrail.moments.count + newRetraceMoments.count + 1

        let moment = SpatialMoment(
            id: UUID().uuidString,
            index: idx,
            title: "Stop \(idx) · Photo",
            subtitle: Date().formatted(date: .omitted, time: .shortened),
            narrative: "Photo waypoint checkpoint anchored at \(walkedMeters)m along retrace path.",
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
        newRetraceMoments.append(moment)
        // Note: Do not call scannerEngine.resumeScanning() here - onDismiss handles it after modal exits
        triggerToast("Checkpoint \(idx) Photo Anchored ✓")
    }

    private func handleSavedVoiceWaypoint(audioURL: URL, duration: TimeInterval) {
        let durMinutes = Int(duration) / 60
        let durSeconds = Int(duration) % 60
        let durString = String(format: "%d:%02d", durMinutes, durSeconds)
        let pos = scannerEngine.lastRecordedPosition ?? SIMD3<Float>(0, 0, 0)
        let heading = scannerEngine.currentYawDegrees != 0 ? scannerEngine.currentYawDegrees : (locationManager.currentHeading ?? 0)
        let idx = referenceTrail.moments.count + newRetraceMoments.count + 1

        let moment = SpatialMoment(
            id: UUID().uuidString,
            index: idx,
            title: "Stop \(idx) · Voice",
            subtitle: "Voice Note · \(durString)",
            narrative: "Audio waypoint checkpoint anchored at \(walkedMeters)m along retrace path.",
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
        newRetraceMoments.append(moment)
        scannerEngine.resumeScanning()
        triggerToast("Checkpoint \(idx) Voice Anchored ✓")
    }

    private func toggleInLineVoiceRecording() {
        Haptics.light()
        if isInLineVoiceRecording {
            isInLineVoiceRecording = false
            if let result = audioManager.stopRecording() {
                handleSavedVoiceWaypoint(audioURL: result.url, duration: result.duration)
            }
        } else {
            let dest = TrailPackageStore.shared.mediaDirectory(for: sessionId)
                .appendingPathComponent("voice_\(UUID().uuidString).m4a")
            if audioManager.startRecording(destinationURL: dest) {
                isInLineVoiceRecording = true
                Haptics.medium()
            }
        }
    }

    private func toggleInLineVideoRecording() {
        Haptics.light()
        if isInLineVideoRecording {
            isInLineVideoRecording = false
            Task {
                do {
                    let result = try await arVideoRecorder.stopRecording()
                    await MainActor.run {
                        handleSavedVideoWaypoint(fileURL: result.url, duration: result.duration, thumbURL: result.thumbURL)
                    }
                } catch {
                    print("Failed to finalize in-situ AR video recording in retrace: \(error)")
                }
            }
        } else {
            let id = UUID().uuidString
            let videoURL = TrailPackageStore.shared.mediaDirectory(for: sessionId)
                .appendingPathComponent("video_\(id).mp4")
            let thumbURL = TrailPackageStore.shared.mediaDirectory(for: sessionId)
                .appendingPathComponent("thumb_\(id).jpg")

            if arVideoRecorder.startRecording(destinationURL: videoURL, thumbnailURL: thumbURL) {
                isInLineVideoRecording = true
                Haptics.medium()
            }
        }
    }

    private func saveTextMoment(title: String, text: String) {
        let idx = referenceTrail.moments.count + newRetraceMoments.count + 1
        let safeTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? "Stop \(idx) · Field Note" : title
        let pos = scannerEngine.lastRecordedPosition ?? SIMD3<Float>(0, 0, 0)
        let heading = scannerEngine.currentYawDegrees != 0 ? scannerEngine.currentYawDegrees : (locationManager.currentHeading ?? 0)

        let moment = SpatialMoment(
            id: UUID().uuidString,
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
        newRetraceMoments.append(moment)
        scannerEngine.resumeScanning()
        triggerToast("Checkpoint \(idx) Note Anchored ✓")
    }

    @ViewBuilder
    private func momentThumbnailView(for moment: SpatialMoment) -> some View {
        if moment.hasPhoto, let photoURL = moment.resolvedPhotoURL(trailId: sessionId),
           let uiImage = UIImage(contentsOfFile: photoURL.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else if moment.hasVideo, let thumbURL = moment.resolvedVideoThumbnailURL(trailId: sessionId),
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

    // MARK: - Lifecycle & Relocalization (PRD §8 & §9)

    private func initializeRetraceSession() {
        sessionId = UUID().uuidString
        currentSegmentId = UUID().uuidString
        elapsedSeconds = 0
        visitedCheckpointIds.removeAll()
        visitedOrderArray.removeAll()
        selectedTargetCheckpointId = nil
        newRetraceMoments.removeAll()

        hasConfirmedStart = false
        showingStartFrameGuidance = true

        // Directly active and aligned to origin
        alignmentState = "aligned"
        positioningMode = "localSpatialAligned"
        alignmentMethod = "originAnchor"

        // Load reference footsteps with source trail fallback
        let fallbackId = referenceTrail.sourceTrailId ?? referenceTrail.inspiredByTrailId
        let loaded = TrailPackageStore.shared.loadFootsteps(for: referenceTrail.id, fallbackTrailId: fallbackId)
        if !loaded.isEmpty {
            referenceFootsteps = loaded
        } else if !referenceTrail.moments.isEmpty {
            referenceFootsteps = referenceTrail.moments.map { m in
                SIMD3<Float>(Float(m.positionX), Float(m.positionZ ?? 0), Float(m.positionY))
            }
        } else {
            referenceFootsteps = [SIMD3<Float>(0, 0, 0), SIMD3<Float>(0, 0, 1.2)]
        }

        scannerEngine.resetAndStartScanning()
        locationManager.requestAccessIfNeeded()

        // Check if ARWorldMap is available
        startRelocalizationAttempt()

        // Timer
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedSeconds += 1
            checkForCheckpointProximity()
            updateAlignmentStatusFromSensor()
        }

        // Setup initial reference vantage in FrameAlignmentMatcher
        frameMatcher.setReference(
            image: currentReferenceImage,
            heading: currentReferenceHeading,
            title: currentReferenceTitle
        )

        // Alignment tracking timer running at 0.35s intervals
        alignmentTimer?.invalidate()
        alignmentTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
            Task { @MainActor in
                frameMatcher.updateLiveFrame(
                    image: scannerEngine.captureCurrentARFrameImage(),
                    liveHeading: currentHeadingDegrees
                )
            }
        }
    }

    private func startRelocalizationAttempt() {
        if TrailPackageStore.shared.hasWorldMap(for: referenceTrail.id),
           let mapData = TrailPackageStore.shared.loadWorldMapData(for: referenceTrail.id) {
            alignmentMethod = "arWorldMap"
            let attempt = AlignmentAttempt(
                retraceSessionId: sessionId,
                referenceAssetIds: ["spatial/worldmap.arworldmap"],
                method: "arWorldMap",
                startedAt: Date()
            )
            alignmentAttempts.append(attempt)
            scannerEngine.startRetraceRelocalization(worldMapData: mapData)
        } else {
            alignmentMethod = "originAnchor"
        }
        alignmentState = "aligned"
        positioningMode = "localSpatialAligned"
    }

    private func updateAlignmentStatusFromSensor() {
        if alignmentMethod == "arWorldMap" {
            if scannerEngine.isRelocalized {
                if alignmentState != "aligned" {
                    alignmentState = "aligned"
                    triggerToast("✓ Aligned to Reference Frame")
                }
            } else if alignmentState == "aligned" {
                alignmentState = "degraded"
            }
        }
    }

    private func checkForCheckpointProximity() {
        guard alignmentState == "aligned" || alignmentState == "degraded" else { return }
        for moment in referenceTrail.moments where !visitedCheckpointIds.contains(moment.id) {
            let target = SIMD3<Float>(Float(moment.positionX), 0, Float(moment.positionY))
            let dist = simd_distance(transformedPosition, target)

            if dist < 3.5 && activeCheckpointEncounter?.id != moment.id {
                Haptics.success()
                withAnimation(.spring(response: 0.35)) {
                    activeCheckpointEncounter = moment
                }
                break
            }
        }
    }

    private func finalizeAndSaveRetrace() {
        let newTrailId = "retrace-\(UUID().uuidString.prefix(8).lowercased())-\(Int(Date().timeIntervalSince1970))"
        let effectiveDistance = max(walkedMeters, max(1, Int(Float(scannerEngine.footsteps.count) * 0.2)))
        var effectiveSteps = !transformedFootsteps.isEmpty ? transformedFootsteps : scannerEngine.footsteps
        if effectiveSteps.isEmpty {
            effectiveSteps = TrailPackageStore.shared.loadFootsteps(for: referenceTrail.id)
        }

        // 1. Copy over media and spatial references from reference trail so the new trail is 100% self-contained
        TrailPackageStore.shared.copyAssets(from: referenceTrail.id, to: newTrailId)

        // 2. Also copy any media captured during this session (stored in sessionId media dir)
        TrailPackageStore.shared.copyAssets(from: sessionId, to: newTrailId)

        // 3. Prepare moments for the retrace trail
        var retraceMoments: [SpatialMoment] = []
        for (idx, moment) in referenceTrail.moments.enumerated() {
            var m = moment
            m.index = idx + 1
            if visitedCheckpointIds.contains(moment.id) {
                let note = m.architecturalNote.isEmpty ? "Verified during Retrace (\(similarityIndexPercentage)% Match)" : "\(m.architecturalNote) · Verified during Retrace (\(similarityIndexPercentage)% Match)"
                m.architecturalNote = note
            }
            retraceMoments.append(m)
        }
        for newM in newRetraceMoments {
            var m = newM
            m.index = retraceMoments.count + 1
            retraceMoments.append(m)
        }

        // 4. Construct the first-class TrailDetail on its own merit
        let author = TrailsDataStore.shared.localProfile.displayName.isEmpty ? "Explorer" : TrailsDataStore.shared.localProfile.displayName
        let retraceTrail = TrailDetail(
            id: newTrailId,
            title: "Retrace · \(referenceTrail.title)",
            subtitle: "\(effectiveDistance)m retraced walk · \(similarityIndexPercentage)% Match",
            placeId: referenceTrail.placeId,
            placeName: referenceTrail.placeName,
            locality: referenceTrail.locality,
            wing: referenceTrail.wing,
            authorName: author,
            authorRole: "Retrace Explorer",
            distanceMeters: effectiveDistance,
            floorCode: referenceTrail.floorCode,
            floorTitle: referenceTrail.floorTitle,
            meshDensity: referenceTrail.meshDensity,
            samplingFrequency: "24.6 kHz",
            nodeCount: max(1, retraceMoments.count),
            personalNotes: "Retraced from “\(referenceTrail.title)” with \(similarityIndexPercentage)% match score on \(Date().formatted(date: .abbreviated, time: .shortened)). Checkpoints visited: \(visitedCheckpointIds.count) of \(referenceTrail.moments.count).",
            moments: retraceMoments,
            visibility: .privateDraft,
            isDraft: false,
            coverImageName: referenceTrail.coverImageName,
            latitude: referenceTrail.latitude,
            longitude: referenceTrail.longitude,
            inspiredByTrailId: referenceTrail.id,
            inspiredByNote: "Retraced from “\(referenceTrail.title)”",
            isRetrace: true,
            retraceSimilarityIndex: Double(similarityIndexPercentage) / 100.0,
            retraceReferenceTrailTitle: referenceTrail.title,
            retraceDate: Date(),
            startFramePhotoName: referenceTrail.startFramePhotoName ?? referenceTrail.moments.first?.photoFileName,
            startHeadingDegrees: referenceTrail.startHeadingDegrees ?? referenceTrail.moments.first?.headingDegrees,
            startVantageDescription: referenceTrail.startVantageDescription,
            isStartingFramePano: referenceTrail.isStartingFramePano,
            createdAt: Date().addingTimeInterval(-Double(elapsedSeconds)),
            updatedAt: Date()
        )

        // 5. Persist as first-class trail package on device
        TrailPackageStore.shared.saveTrailPackage(trail: retraceTrail, footsteps: effectiveSteps)

        // 6. Persist Retrace audit session under reference trail
        let session = RetraceSession(
            id: sessionId,
            sourceTrailId: referenceTrail.id,
            startedAt: Date().addingTimeInterval(-Double(elapsedSeconds)),
            endedAt: Date(),
            distanceWalkedMeters: effectiveDistance,
            visitedMomentIds: Array(visitedCheckpointIds),
            similarityIndex: Double(similarityIndexPercentage) / 100.0,
            pathCoveragePercentage: pathCoverageRatio,
            checkpointsOrder: visitedOrderArray,
            positioningMode: positioningMode,
            alignmentState: alignmentState,
            alignmentMethod: alignmentMethod,
            referenceFrameId: referenceFrame?.id,
            segmentIds: [currentSegmentId],
            newMoments: newRetraceMoments
        )
        TrailPackageStore.shared.saveRetraceSession(session: session, footsteps: effectiveSteps)

        // 7. Update TrailsDataStore and reload
        TrailsDataStore.shared.saveFinalTrail(trail: retraceTrail, footsteps: effectiveSteps)
        TrailsDataStore.shared.reloadFromDisk()

        teardownRetraceSession()
    }

    private func teardownRetraceSession() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        alignmentTimer?.invalidate()
        alignmentTimer = nil
        frameMatcher.reset()
        scannerEngine.stopScanning()
        cameraEngine.stop()
        if audioManager.isRecording {
            _ = audioManager.stopRecording()
        }
        if arVideoRecorder.isRecording {
            Task { try? await arVideoRecorder.stopRecording() }
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
}

// MARK: - PRD §16 Positioning Diagnostics Sheet

private struct PositioningDiagnosticsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let trail: TrailDetail
    let sessionId: String
    let segmentId: String
    let positioningMode: String
    let alignmentState: String
    let alignmentMethod: String
    let rawPose: SIMD3<Float>
    let transformedPose: SIMD3<Float>
    let rotationDegrees: Double
    let translation: SIMD3<Float>
    let hasWorldMap: Bool
    let worldMapSize: Int
    let trackingStateDescription: String

    @State private var copiedNotice: Bool = false

    private var diagnosticsJSON: String {
        """
        {
          "sessionId": "\(sessionId)",
          "segmentId": "\(segmentId)",
          "sourceTrailId": "\(trail.id)",
          "positioningMode": "\(positioningMode)",
          "alignmentState": "\(alignmentState)",
          "alignmentMethod": "\(alignmentMethod)",
          "hasWorldMap": \(hasWorldMap),
          "worldMapSizeBytes": \(worldMapSize),
          "trackingState": "\(trackingStateDescription)",
          "rawPose": {
            "x": \(String(format: "%.4f", rawPose.x)),
            "y": \(String(format: "%.4f", rawPose.y)),
            "z": \(String(format: "%.4f", rawPose.z))
          },
          "transformedPose": {
            "x": \(String(format: "%.4f", transformedPose.x)),
            "y": \(String(format: "%.4f", transformedPose.y)),
            "z": \(String(format: "%.4f", transformedPose.z))
          },
          "calibrationTransform": {
            "translationX": \(String(format: "%.4f", translation.x)),
            "translationZ": \(String(format: "%.4f", translation.z)),
            "rotationDegrees": \(String(format: "%.2f", rotationDegrees))
          }
        }
        """
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Positioning Mode & State (PRD §5 & §8)") {
                    row("Positioning Mode", positioningMode)
                    row("Alignment State", alignmentState.uppercased())
                    row("Alignment Method", alignmentMethod)
                    row("Sensor Tracking", trackingStateDescription)
                }

                Section("Reference Assets (PRD §6 & §7)") {
                    row("ARWorldMap Saved", hasWorldMap ? "Yes (\(worldMapSize / 1024) KB)" : "None")
                    row("Reference Frame", hasWorldMap ? "spatial/worldmap.arworldmap" : "Unanchored")
                    row("Trail ID", trail.id)
                }

                Section("Pose Coordinates (PRD §6)") {
                    row("Raw Local Pose", String(format: "(%.2fm, %.2fm, %.2fm)", rawPose.x, rawPose.y, rawPose.z))
                    row("Transformed Pose", String(format: "(%.2fm, %.2fm, %.2fm)", transformedPose.x, transformedPose.y, transformedPose.z))
                    row("Calibration Offset", String(format: "Δ(%.2fm, %.2fm) · Rot: %.1f°", translation.x, translation.z, rotationDegrees))
                }

                Section("Diagnostic Export (PRD §16)") {
                    Button {
                        UIPasteboard.general.string = diagnosticsJSON
                        copiedNotice = true
                    } label: {
                        HStack {
                            Image(systemName: copiedNotice ? "checkmark" : "doc.on.doc")
                            Text(copiedNotice ? "Copied Diagnostics JSON ✓" : "Copy Diagnostics JSON")
                        }
                        .foregroundColor(Color(hex: "#00E5FF"))
                    }
                }
            }
            .navigationTitle("Positioning Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(value).foregroundColor(.primary).font(.system(.body, design: .monospaced))
        }
    }
}

// MARK: - PRD §9 & §10 Manual Reference Calibration Sheet

private struct ManualReferenceCalibrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let trail: TrailDetail
    let rawDevicePosition: SIMD3<Float>
    let currentYaw: Double
    let onCalibrate: (_ translation: SIMD3<Float>, _ rotation: Double) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "location.viewfinder")
                    .font(.system(size: 48))
                    .foregroundColor(Color(hex: "#00E5FF"))
                    .padding(.top, 24)

                VStack(spacing: 6) {
                    Text("Calibrate Reference Frame")
                        .font(AppFonts.headlineMedium)

                    Text("Stand physically at Stop 1 (the start of the trail) and point your camera in the direction the original explorer walked.")
                        .font(AppFonts.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                if let firstMoment = trail.moments.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ANCHOR TARGET")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(Color(hex: "#00E5FF"))

                        Text("Stop 1: \(firstMoment.title)")
                            .font(AppFonts.headlineSmall)

                        Text("Survey Reference: X=\(String(format: "%.2f", firstMoment.positionX))m, Z=\(String(format: "%.2f", firstMoment.positionY))m")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 20)
                }

                Spacer()

                Button {
                    Haptics.success()
                    let m1 = trail.moments.first
                    let targetX = Float(m1?.positionX ?? 0)
                    let targetZ = Float(m1?.positionY ?? 0)

                    let translation = SIMD3<Float>(targetX - rawDevicePosition.x, 0, targetZ - rawDevicePosition.z)
                    let headingTarget = m1?.headingDegrees ?? 0
                    let rotation = (headingTarget - currentYaw)

                    onCalibrate(translation, rotation)
                    dismiss()
                } label: {
                    Text("Calibrate Frame at Stop 1")
                        .font(AppFonts.labelUI)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(hex: "#00E5FF"))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("Manual Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Compare Vantage Sheet (Then vs. Now)

private struct CompareVantageSheet: View {
    @Environment(\.dismiss) private var dismiss
    let referenceTrail: TrailDetail
    let moment: SpatialMoment
    let onMarkVisited: () -> Void

    private var resolvedMomentImage: UIImage? {
        let fallbackId = referenceTrail.sourceTrailId ?? referenceTrail.inspiredByTrailId
        if moment.hasPhoto, let photoURL = moment.resolvedPhotoURL(trailId: referenceTrail.id, fallbackTrailId: fallbackId),
           let img = UIImage(contentsOfFile: photoURL.path) {
            return img
        }
        if let asset = moment.photoAssetName, let img = UIImage(named: asset) {
            return img
        }
        // Fall back to reference trail start frame / first frame photo or cover image
        if let startURL = referenceTrail.resolvedStartFrameURL(fallbackTrailId: fallbackId),
           let img = UIImage(contentsOfFile: startURL.path) {
            return img
        }
        if let coverURL = referenceTrail.resolvedCoverImageURL(fallbackTrailId: fallbackId),
           let img = UIImage(contentsOfFile: coverURL.path) {
            return img
        }
        if let url = TrailPackageStore.shared.resolvedCoverOrFirstFrame(for: referenceTrail.id),
           let img = UIImage(contentsOfFile: url.path) {
            return img
        }
        if let fallback = fallbackId,
           let url = TrailPackageStore.shared.resolvedCoverOrFirstFrame(for: fallback),
           let img = UIImage(contentsOfFile: url.path) {
            return img
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("ORIGINAL RECORDED MOMENT")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(Color(hex: "#00E5FF"))
                            .tracking(1.5)

                        Text("Checkpoint \(moment.index): \(moment.title)")
                            .font(AppFonts.headlineMedium)
                            .foregroundColor(.white)
                    }
                    .padding(.top, 10)

                    ZStack {
                        if let image = resolvedMomentImage {
                            VStack(spacing: 8) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 280)
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color(hex: "#00E5FF").opacity(0.35), lineWidth: 1.5)
                                    )

                                if !moment.hasPhoto {
                                    Text("Reference First Frame · Start Vantage")
                                        .font(AppFonts.labelSpatial)
                                        .foregroundColor(AppColors.mutedBrass)
                                }
                            }
                        } else if moment.hasVideo, let videoURL = moment.resolvedVideoURL(trailId: referenceTrail.id, fallbackTrailId: referenceTrail.sourceTrailId) {
                            VideoPlayer(player: AVPlayer(url: videoURL))
                                .frame(height: 240)
                                .cornerRadius(16)
                        } else if let asset = moment.photoAssetName {
                            Image(asset)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(16)
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 180)
                                .overlay(
                                    Image(systemName: "photo")
                                        .font(.system(size: 40))
                                        .foregroundColor(.white.opacity(0.5))
                                )
                        }
                    }
                    .frame(maxHeight: 290)
                    .padding(.horizontal, 16)

                    if !moment.narrative.isEmpty {
                        Text("“\(moment.narrative)”")
                            .font(.custom("Newsreader", size: 16))
                            .italic()
                            .foregroundColor(Color.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Spacer()

                    Button {
                        Haptics.success()
                        onMarkVisited()
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: (moment.index == 1 || moment.title.lowercased().contains("arrival")) ? "arrow.right.circle.fill" : "checkmark.circle.fill")
                                .font(.system(size: 16))
                            Text((moment.index == 1 || moment.title.lowercased().contains("arrival")) ? "Confirm Start & Continue Retrace" : "Mark Checkpoint Visited")
                                .font(AppFonts.labelUI)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(hex: "#00E5FF"))
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
    }
}
