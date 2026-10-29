//
//  RoomScannerEngine.swift
//  Trails
//
//  Coordinates Apple RoomPlan indoor geometry capture and 6DOF path recording.
//  Includes built-in spatial simulation support for non-LiDAR testing and demos.
//

import RoomPlan
import ARKit
import Combine
import SwiftUI

@MainActor
class RoomScannerEngine: NSObject, ObservableObject, RoomCaptureSessionDelegate, ARSessionDelegate {
    @Published var isScanning = false
    @Published var isSimulated = false
    @Published var capturedRoom: CapturedRoom?
    @Published var footsteps: [SIMD3<Float>] = []
    @Published var recordedMoments: [SpatialMoment] = []

    // Hardware support check
    @Published var isSupported: Bool = RoomCaptureSession.isSupported

    private weak var captureView: RoomCaptureView?
    private var simulationTimer: Timer?
    private var simulationStep: Int = 0

    // For path plotting distance threshold (to avoid redundant points)
    @Published var lastRecordedPosition: SIMD3<Float>?
    @Published var currentYawDegrees: Double = 0 // Spatial orientation / compass yaw in world frame (0..360)
    @Published var currentForwardVector: SIMD2<Float> = SIMD2<Float>(0, -1)
    private let distanceThreshold: Float = 0.2 // meters

    // PRD v0.3.1 Relocalisation & Alignment State Tracking
    @Published var trackingState: ARCamera.TrackingState = .notAvailable
    @Published var isRelocalized: Bool = false
    @Published var relocalizationStatusText: String = "Initializing"

    override init() {
        super.init()
    }

    func attach(to view: RoomCaptureView) {
        self.captureView = view
        view.captureSession.delegate = self
        view.captureSession.arSession.delegate = self
    }

    func resetAndStartScanning() {
        footsteps.removeAll()
        recordedMoments.removeAll()
        lastRecordedPosition = nil
        startScanning()
    }

    func startScanning() {
        if isSupported {
            let config = RoomCaptureSession.Configuration()
            captureView?.captureSession.run(configuration: config)
            isSimulated = false
            isScanning = true
        } else {
            // Auto-start simulation on non-LiDAR/simulator so developer/user isn't stuck
            startSimulation()
        }
    }

    func pauseScanning() {
        simulationTimer?.invalidate()
        simulationTimer = nil
        if isSupported {
            captureView?.captureSession.stop()
        }
        isScanning = false
    }

    func resumeScanning() {
        guard !isScanning else { return }
        if isSupported {
            let config = RoomCaptureSession.Configuration()
            captureView?.captureSession.run(configuration: config)
            isScanning = true
        } else {
            isScanning = true
            simulationTimer?.invalidate()
            simulationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, self.isScanning else { return }
                    self.advanceSimulation()
                }
            }
        }
    }

    func startSimulation() {
        stopScanning()
        isSimulated = true
        isScanning = true
        footsteps.removeAll()
        recordedMoments.removeAll()
        simulationStep = 0
        lastRecordedPosition = SIMD3<Float>(0, 0, 0)
        footsteps.append(SIMD3<Float>(0, 0, 0))

        simulationTimer?.invalidate()
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isScanning else { return }
                self.advanceSimulation()
            }
        }
    }

    private func advanceSimulation() {
        simulationStep += 1
        let t = Float(simulationStep) * 0.12
        // Natural figure-8 / courtyard loop in meters
        let x = 2.4 * sin(t)
        let z = 1.6 * sin(2 * t)
        let pos = SIMD3<Float>(x, 0, z)

        if let last = lastRecordedPosition {
            let delta = pos - last
            if simd_length(delta) > 0.001 {
                let yawRad = atan2(-delta.x, -delta.z)
                var yawDeg = Double(yawRad * 180.0 / .pi)
                if yawDeg < 0 { yawDeg += 360.0 }
                currentYawDegrees = yawDeg
                currentForwardVector = SIMD2<Float>(-delta.x, -delta.z)
            }
        }

        footsteps.append(pos)
        lastRecordedPosition = pos
    }

    func stopScanning() {
        simulationTimer?.invalidate()
        simulationTimer = nil
        if isSupported {
            captureView?.captureSession.stop()
        }
        isScanning = false
    }

    func addMoment(
        label: String,
        note: String = "",
        mediaType: String = "note",
        hasPhoto: Bool = false,
        photoAssetName: String? = nil,
        hasAudio: Bool = false,
        audioDuration: String? = nil,
        audioFileName: String? = nil,
        hasVideo: Bool = false,
        videoDuration: String? = nil,
        videoFileName: String? = nil,
        videoThumbnailAssetName: String? = nil,
        headingDegrees: Double? = nil
    ) {
        let index = recordedMoments.count + 1
        let pos = lastRecordedPosition ?? SIMD3<Float>(0, 0, 0)
        let walkedMeters = max(1, Int(Float(footsteps.count) * distanceThreshold))
        let moment = SpatialMoment(
            id: UUID().uuidString,
            index: index,
            title: label,
            subtitle: note.isEmpty ? "Moment \(index)" : note,
            narrative: note.isEmpty ? "Recorded checkpoint at (\(String(format: "%.1f", pos.x))m, \(String(format: "%.1f", pos.z))m)." : note,
            architecturalNote: "Local survey coordinate: X=\(String(format: "%.2f", pos.x)), Z=\(String(format: "%.2f", pos.z))",
            distanceAlongPathMeters: walkedMeters,
            audioDuration: audioDuration,
            videoDuration: videoDuration,
            hasAudio: hasAudio,
            hasPhoto: hasPhoto,
            hasVideo: hasVideo,
            mediaType: mediaType,
            photoAssetName: photoAssetName,
            audioFileName: audioFileName,
            videoFileName: videoFileName,
            videoThumbnailAssetName: videoThumbnailAssetName,
            positionX: Double(pos.x),
            positionY: Double(pos.z),
            positionZ: Double(pos.y),
            headingDegrees: headingDegrees ?? (currentYawDegrees != 0 ? currentYawDegrees : nil)
        )
        recordedMoments.append(moment)
    }

    // MARK: - RoomCaptureSessionDelegate

    nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        Task { @MainActor in
            self.capturedRoom = room
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        // Handle end of scan if necessary
    }

    func exportWorldMap(completion: @escaping (Data?) -> Void) {
        guard let arSession = captureView?.captureSession.arSession else {
            completion(nil)
            return
        }
        arSession.getCurrentWorldMap { worldMap, error in
            guard let map = worldMap, error == nil else {
                completion(nil)
                return
            }
            let data = try? NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
            completion(data)
        }
    }

    func startRetraceRelocalization(worldMapData: Data) {
        guard let arSession = captureView?.captureSession.arSession else { return }
        guard let worldMap = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: worldMapData) else {
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.initialWorldMap = worldMap
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
        isRelocalized = false
        relocalizationStatusText = "Relocalizing against reference map..."
    }

    // MARK: - ARSessionDelegate

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        Task { @MainActor in
            self.trackingState = camera.trackingState
            switch camera.trackingState {
            case .normal:
                self.isRelocalized = true
                self.relocalizationStatusText = "Aligned"
            case .limited(let reason):
                self.isRelocalized = false
                switch reason {
                case .relocalizing:
                    self.relocalizationStatusText = "Searching for reference area..."
                case .excessiveMotion:
                    self.relocalizationStatusText = "Slow down — excessive motion"
                case .insufficientFeatures:
                    self.relocalizationStatusText = "Low visual detail"
                case .initializing:
                    self.relocalizationStatusText = "Initializing sensors"
                @unknown default:
                    self.relocalizationStatusText = "Tracking limited"
                }
            case .notAvailable:
                self.isRelocalized = false
                self.relocalizationStatusText = "Tracking unavailable"
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let transform = frame.camera.transform
        let position = transform.columns.3
        let currentPos = SIMD3<Float>(position.x, position.y, position.z)

        // Calculate world yaw and forward vector from camera transform
        let forward = -transform.columns.2
        let yawRad = atan2(-forward.x, -forward.z)
        var yawDeg = Double(yawRad * 180.0 / .pi)
        if yawDeg < 0 { yawDeg += 360.0 }
        let forward2D = SIMD2<Float>(-forward.x, -forward.z)

        Task { @MainActor in
            guard self.isScanning, !self.isSimulated else { return }

            self.currentYawDegrees = yawDeg
            self.currentForwardVector = forward2D

            if let lastPos = self.lastRecordedPosition {
                let distance = simd_distance(lastPos, currentPos)
                if distance >= self.distanceThreshold {
                    self.footsteps.append(currentPos)
                    self.lastRecordedPosition = currentPos
                }
            } else {
                self.footsteps.append(currentPos)
                self.lastRecordedPosition = currentPos
            }
        }
    }
}
