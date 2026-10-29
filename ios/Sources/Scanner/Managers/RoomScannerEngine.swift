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
    private let distanceThreshold: Float = 0.2 // meters

    override init() {
        super.init()
    }

    func attach(to view: RoomCaptureView) {
        self.captureView = view
        view.captureSession.delegate = self
        view.captureSession.arSession.delegate = self
    }

    func startScanning() {
        if isSupported {
            let config = RoomCaptureSession.Configuration()
            captureView?.captureSession.run(configuration: config)
            isSimulated = false
            isScanning = true
            footsteps.removeAll()
            recordedMoments.removeAll()
            lastRecordedPosition = nil
        } else {
            // Auto-start simulation on non-LiDAR/simulator so developer/user isn't stuck
            startSimulation()
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
        audioFileName: String? = nil
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
            hasAudio: hasAudio,
            hasPhoto: hasPhoto,
            mediaType: mediaType,
            photoAssetName: photoAssetName,
            audioFileName: audioFileName,
            positionX: Double(pos.x),
            positionY: Double(pos.z)
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

    // MARK: - ARSessionDelegate

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let position = frame.camera.transform.columns.3
        let currentPos = SIMD3<Float>(position.x, position.y, position.z)

        Task { @MainActor in
            guard self.isScanning, !self.isSimulated else { return }

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
