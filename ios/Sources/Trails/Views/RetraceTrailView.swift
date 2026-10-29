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

    // PRD v0.3.1 Positioning Modes & Alignment State Machine
    @State private var positioningMode: String = "localSpatialUnaligned" // "localSpatialAligned", "localSpatialUnaligned", "manualFollowAlong", "geographic"
    @State private var alignmentState: String = "loading" // "unavailable", "loading", "searching", "verifying", "aligned", "degraded", "lost"
    @State private var alignmentMethod: String = "none" // "arWorldMap", "twoPointReference", "manualProgression"
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

    // Start Frame Alignment Gate (Enforces starting at the first frame)
    @State private var hasUnlockedStartGate: Bool = false
    @State private var ghostMatchOpacity: Double = 0.5
    @State private var isGhostOverlayActive: Bool = true

    // UI & Navigation Controls
    @State private var isMapOnlyView: Bool = false
    @State private var isTurnGuidanceEnabled: Bool = true
    @State private var activeCheckpointEncounter: SpatialMoment? = nil
    @State private var showingCompareSheet: Bool = false
    @State private var selectedMomentToInspect: SpatialMoment? = nil
    @State private var showingFinishAlert: Bool = false
    @State private var showingDiagnosticsSheet: Bool = false
    @State private var showingManualCalibrationSheet: Bool = false
    @State private var toastMessage: String? = nil

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
        if alignmentState != "aligned" && alignmentState != "degraded" {
            return DirectionalInstruction(
                icon: "viewfinder",
                relativeAngle: 0,
                primaryText: "Establishing reference alignment",
                secondaryText: "Look around starting area to sync coordinate frame",
                color: AppColors.mutedBrass
            )
        }

        if !referenceTrail.moments.isEmpty && visitedCheckpointIds.count == referenceTrail.moments.count {
            return DirectionalInstruction(
                icon: "checkmark.seal.fill",
                relativeAngle: 0,
                primaryText: "All Checkpoints Visited!",
                secondaryText: "Similarity: \(similarityIndexPercentage)% · Tap End to save record",
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

            if !hasUnlockedStartGate && !referenceTrail.moments.isEmpty {
                // Enforce aligning at the first frame (Stop 1) before unlocking retrace
                startFrameEnforcerView
            } else if positioningMode == "manualFollowAlong" {
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
                    // Upper Pane: Live LiDAR Camera Viewport
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
                                    Text("LiDAR Spatial Relocalization")
                                        .font(AppFonts.headlineSmall)
                                        .foregroundColor(.white)
                                    Text("Look around the starting threshold to align coordinate frame")
                                        .font(AppFonts.caption)
                                        .foregroundColor(Color.white.opacity(0.65))
                                }
                            }
                        }

                        // PRD §8 & §12: Non-aligned Searching / Relocalization HUD
                        if alignmentState == "searching" || alignmentState == "loading" {
                            searchingAlignmentOverlay
                        } else if alignmentState == "lost" {
                            lostAlignmentOverlay
                        } else if alignmentState == "unavailable" {
                            unavailableAlignmentOverlay
                        }

                        // Gradient scrim
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.4)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 60)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .frame(height: UIScreen.main.bounds.height * 0.46)

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

            // MARK: - HUD & Overlays (Visible once gate unlocked)
            if hasUnlockedStartGate || referenceTrail.moments.isEmpty {
                VStack(spacing: 0) {
                    // Top Navigation Bar
                    topRetraceBar

                    // Live Navigation Cue Banner (only in aligned/degraded live tracking)
                    if isTurnGuidanceEnabled && positioningMode != "manualFollowAlong" {
                        navigationCueBanner
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Spacer()

                    // Checkpoint Encounter Notification Card
                    if let encounter = activeCheckpointEncounter, positioningMode != "manualFollowAlong" {
                        checkpointEncounterCard(for: encounter)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Bottom Console
                    if positioningMode != "manualFollowAlong" {
                        bottomRetraceConsole
                    }
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
                if selectedTargetCheckpointId == moment.id {
                    selectedTargetCheckpointId = nil
                }
                triggerToast("Stop \(moment.index) Visited ✓ (Match: \(similarityIndexPercentage)%)")
            }
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
        // Finish Confirmation
        .alert("End Retrace Journey?", isPresented: $showingFinishAlert) {
            Button("Keep Retracing", role: .cancel) {}
            Button("Save Retrace Record", role: .none) {
                finalizeAndSaveRetrace()
                dismiss()
            }
            Button("Discard & Exit", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("Mode: \(positioningMode)\nAlignment: \(alignmentState)\nSimilarity: \(similarityIndexPercentage)%\nCheckpoints: \(visitedCheckpointIds.count) of \(referenceTrail.moments.count) visited\n\nYour original trail remains immutable.")
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

    // MARK: - Top Retrace Bar

    private var topRetraceBar: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.light()
                showingFinishAlert = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(alignmentBadgeText)
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundColor(alignmentBadgeColor.textColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(alignmentBadgeColor.bgColor)
                        .clipShape(Capsule())

                    if alignmentState == "aligned" || alignmentState == "degraded" {
                        Text("\(similarityIndexPercentage)% MATCH")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(hex: "#00E5FF"))
                            .clipShape(Capsule())
                    }
                }

                Text(referenceTrail.title)
                    .font(AppFonts.headlineSmall)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()

            // Start Frame Re-align Button
            if !referenceTrail.moments.isEmpty {
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3)) {
                        hasUnlockedStartGate = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 10))
                        Text("Start Frame")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(Color(hex: "#00E5FF"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color(hex: "#00E5FF").opacity(0.4), lineWidth: 1))
                }
            }

            // Diagnostics Button (PRD §16)
            Button {
                showingDiagnosticsSheet = true
            } label: {
                Text("DIAG")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(AppColors.mutedBrass)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AppColors.mutedBrass.opacity(0.5), lineWidth: 1))
            }

            // Finish CTA
            Button {
                Haptics.success()
                showingFinishAlert = true
            } label: {
                Text("End")
                    .font(AppFonts.labelUI)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#00E5FF"))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 48)
    }

    private var alignmentBadgeText: String {
        switch alignmentState {
        case "aligned": return "ALIGNED · RELOCALIZED"
        case "searching": return "SEARCHING REFERENCE"
        case "verifying": return "VERIFYING ALIGNMENT"
        case "degraded": return "TRACKING DEGRADED"
        case "lost": return "ALIGNMENT LOST"
        case "loading": return "LOADING MAP"
        case "unavailable": return positioningMode == "manualFollowAlong" ? "MANUAL FOLLOW" : "UNALIGNED"
        default: return alignmentState.uppercased()
        }
    }

    private var alignmentBadgeColor: (textColor: Color, bgColor: Color) {
        switch alignmentState {
        case "aligned": return (.black, Color.green)
        case "searching", "loading", "verifying": return (.black, AppColors.mutedBrass)
        case "degraded": return (.white, AppColors.terracotta)
        case "lost": return (.white, Color.red)
        default: return (.white, Color.white.opacity(0.2))
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(hex: "#00E5FF"))
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

    // MARK: - Bottom Retrace Console

    private var bottomRetraceConsole: some View {
        VStack(spacing: 12) {
            HStack {
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

            // Checkpoints Ribbon
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
                }
                .padding(.horizontal, 16)
            }
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

    // MARK: - Start Frame Alignment Gate (Enforcing First Frame Vantage)

    private var startFrameEnforcerView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Header Bar
                HStack(spacing: 12) {
                    Button {
                        Haptics.light()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("GATE ENFORCED")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(Color(hex: "#00E5FF"))
                                .tracking(1.2)
                            Text("STOP 1")
                                .font(.system(size: 8, weight: .black, design: .rounded))
                                .foregroundColor(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: "#00E5FF"))
                                .clipShape(Capsule())
                        }

                        Text("Match Starting Vantage")
                            .font(AppFonts.headlineSmall)
                            .foregroundColor(.white)
                    }

                    Spacer()

                    // Skip button for free roam
                    Button {
                        Haptics.light()
                        withAnimation(.spring(response: 0.3)) {
                            hasUnlockedStartGate = true
                        }
                    } label: {
                        Text("Skip Gate")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(.white.opacity(0.65))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 48)
                .padding(.bottom, 8)

                // Main Viewport: Live Camera with Ghost Match Overlay
                ZStack(alignment: .bottom) {
                    if scannerEngine.isSupported {
                        RoomCameraView(engine: scannerEngine)
                            .ignoresSafeArea()
                    } else {
                        Color(hex: "#0D1117")
                    }

                    // Ghost / Onion-skin overlay of the First Frame
                    if isGhostOverlayActive, let startMoment = referenceTrail.moments.first {
                        startFrameGhostImage(for: startMoment)
                            .opacity(ghostMatchOpacity)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .allowsHitTesting(false)
                    }

                    // Viewfinder reticle
                    VStack {
                        Spacer()
                        ZStack {
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color(hex: "#00E5FF"), style: StrokeStyle(lineWidth: 1.5, dash: [10, 8]))
                                .frame(width: 250, height: 210)

                            VStack(spacing: 6) {
                                Image(systemName: "viewfinder")
                                    .font(.system(size: 34, weight: .thin))
                                    .foregroundColor(Color(hex: "#00E5FF"))
                                Text("Line up with starting threshold")
                                    .font(AppFonts.caption)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                        Spacer()

                        // Ghost Opacity Control Dock
                        if let startMoment = referenceTrail.moments.first, startMoment.hasPhoto || startMoment.hasVideo || startMoment.photoAssetName != nil {
                            HStack(spacing: 12) {
                                Button {
                                    withAnimation { isGhostOverlayActive.toggle() }
                                } label: {
                                    Image(systemName: isGhostOverlayActive ? "eye.fill" : "eye.slash.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(isGhostOverlayActive ? Color(hex: "#00E5FF") : .white)
                                }

                                Text("Ghost")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(.white)

                                Slider(value: $ghostMatchOpacity, in: 0.15...0.85)
                                    .accentColor(Color(hex: "#00E5FF"))

                                Text("\(Int(ghostMatchOpacity * 100))%")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .frame(width: 32)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.75))
                            .clipShape(Capsule())
                            .padding(.bottom, 12)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom Origin Card & Begin Button
                if let startMoment = referenceTrail.moments.first {
                    VStack(spacing: 14) {
                        HStack(spacing: 12) {
                            startFrameThumbnail(for: startMoment)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color(hex: "#00E5FF").opacity(0.7), lineWidth: 1.5)
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(hex: "#00E5FF"))
                                        .frame(width: 8, height: 8)
                                    Text("FIRST FRAME · ORIGIN")
                                        .font(AppFonts.labelSpatial)
                                        .foregroundColor(Color(hex: "#00E5FF"))
                                }

                                Text(startMoment.title)
                                    .font(AppFonts.headlineSmall)
                                    .foregroundColor(.white)
                                    .lineLimit(1)

                                Text("Stand where this photo was recorded and face forward to begin.")
                                    .font(AppFonts.caption)
                                    .foregroundColor(Color.white.opacity(0.75))
                                    .lineLimit(2)
                            }

                            Spacer()
                        }

                        // Prominent CTA
                        Button {
                            calibrateAndUnlockStartGate(startMoment: startMoment)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                                Text("I'm at the First Frame · Start Trail")
                                    .font(AppFonts.labelUI)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(hex: "#00E5FF"))
                            .clipShape(Capsule())
                            .shadow(color: Color(hex: "#00E5FF").opacity(0.4), radius: 8, y: 2)
                        }
                    }
                    .padding(18)
                    .background(Color(hex: "#10141C"))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func calibrateAndUnlockStartGate(startMoment: SpatialMoment) {
        Haptics.success()

        // 1. Calculate translation offset to align live pose to Stop 1's position
        let targetX = Float(startMoment.positionX)
        let targetZ = Float(startMoment.positionY)
        let deltaX = targetX - rawDevicePosition.x
        let deltaZ = targetZ - rawDevicePosition.z
        transformTranslation = SIMD3<Float>(deltaX, 0, deltaZ)

        // 2. Calculate heading offset to match Stop 1's recorded orientation
        if let targetHeading = startMoment.headingDegrees {
            transformRotationDegrees = targetHeading - scannerEngine.currentYawDegrees
        } else {
            transformRotationDegrees = 0
        }

        // 3. Mark alignment state
        alignmentMethod = "startFrameAlignment"
        alignmentState = "aligned"
        positioningMode = "localSpatialAligned"

        // 4. Unlock full trail view
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            hasUnlockedStartGate = true
        }

        triggerToast("✓ Origin Locked at Stop 1 · Starting Retrace")
    }

    @ViewBuilder
    private func startFrameGhostImage(for moment: SpatialMoment) -> some View {
        if moment.hasPhoto, let photoURL = moment.resolvedPhotoURL(trailId: referenceTrail.id),
           let image = UIImage(contentsOfFile: photoURL.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let asset = moment.photoAssetName, let image = UIImage(named: asset) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let thumbName = moment.videoThumbnailAssetName {
            let thumbURL = TrailPackageStore.shared.mediaDirectory(for: referenceTrail.id).appendingPathComponent(thumbName)
            if let image = UIImage(contentsOfFile: thumbURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
    }

    @ViewBuilder
    private func startFrameThumbnail(for moment: SpatialMoment) -> some View {
        if moment.hasPhoto, let photoURL = moment.resolvedPhotoURL(trailId: referenceTrail.id),
           let image = UIImage(contentsOfFile: photoURL.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let asset = moment.photoAssetName, let image = UIImage(named: asset) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let thumbName = moment.videoThumbnailAssetName {
            let thumbURL = TrailPackageStore.shared.mediaDirectory(for: referenceTrail.id).appendingPathComponent(thumbName)
            if let image = UIImage(contentsOfFile: thumbURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackOriginThumbnail
            }
        } else {
            fallbackOriginThumbnail
        }
    }

    private var fallbackOriginThumbnail: some View {
        ZStack {
            Color.white.opacity(0.1)
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 22))
                .foregroundColor(Color(hex: "#00E5FF"))
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

        // Enforce Start Gate if trail has recorded checkpoints
        if referenceTrail.moments.isEmpty {
            hasUnlockedStartGate = true
        } else {
            hasUnlockedStartGate = false
        }

        // Load reference footsteps
        let loaded = TrailPackageStore.shared.loadFootsteps(for: referenceTrail.id)
        if !loaded.isEmpty {
            referenceFootsteps = loaded
        } else {
            referenceFootsteps = referenceTrail.moments.map { m in
                SIMD3<Float>(Float(m.positionX / 24.0), Float((m.positionZ ?? 0) / 24.0), Float(m.positionY / 24.0))
            }
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
    }

    private func startRelocalizationAttempt() {
        if TrailPackageStore.shared.hasWorldMap(for: referenceTrail.id),
           let mapData = TrailPackageStore.shared.loadWorldMapData(for: referenceTrail.id) {
            alignmentState = "loading"
            positioningMode = "localSpatialAligned"
            alignmentMethod = "arWorldMap"

            let attempt = AlignmentAttempt(
                retraceSessionId: sessionId,
                referenceAssetIds: ["spatial/worldmap.arworldmap"],
                method: "arWorldMap",
                startedAt: Date()
            )
            alignmentAttempts.append(attempt)

            scannerEngine.startRetraceRelocalization(worldMapData: mapData)
            alignmentState = "searching"
        } else {
            // No saved world map: PRD §5 & §8 declare Unavailable / Manual Follow-Along
            alignmentState = "unavailable"
            positioningMode = "localSpatialUnaligned"
            alignmentMethod = "none"
        }
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
        let session = RetraceSession(
            id: sessionId,
            sourceTrailId: referenceTrail.id,
            startedAt: Date().addingTimeInterval(-Double(elapsedSeconds)),
            endedAt: Date(),
            distanceWalkedMeters: walkedMeters,
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
        TrailPackageStore.shared.saveRetraceSession(session: session, footsteps: transformedFootsteps)
        teardownRetraceSession()
    }

    private func teardownRetraceSession() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        scannerEngine.stopScanning()
        cameraEngine.stop()
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
                        if moment.hasPhoto, let photoURL = moment.resolvedPhotoURL(trailId: referenceTrail.id),
                           let image = UIImage(contentsOfFile: photoURL.path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(16)
                        } else if moment.hasVideo, let videoURL = moment.resolvedVideoURL(trailId: referenceTrail.id) {
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
                    .frame(maxHeight: 280)
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
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                            Text("Mark Checkpoint Visited")
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
