//
//  RoomScannerEngine.swift
//  Trails
//

import RoomPlan
import ARKit
import Combine
import SwiftUI

@MainActor
class RoomScannerEngine: NSObject, ObservableObject, RoomCaptureSessionDelegate, ARSessionDelegate {
    @Published var isScanning = false
    @Published var capturedRoom: CapturedRoom?
    @Published var footsteps: [SIMD3<Float>] = []
    @Published var recordedMoments: [SpatialMoment] = []
    
    // Support state
    @Published var isSupported: Bool = RoomCaptureSession.isSupported
    
    private weak var captureView: RoomCaptureView?
    private var isRelocalizing = false
    
    // For path plotting distance threshold (to avoid too many points)
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
        guard isSupported else { return }
        
        let config = RoomCaptureSession.Configuration()
        captureView?.captureSession.run(configuration: config)
        
        isScanning = true
        footsteps.removeAll()
        recordedMoments.removeAll()
        lastRecordedPosition = nil
    }
    
    func stopScanning() {
        captureView?.captureSession.stop()
        isScanning = false
    }

    func addMoment(label: String, note: String = "") {
        let index = recordedMoments.count + 1
        let pos = lastRecordedPosition ?? SIMD3<Float>(0, 0, 0)
        let walkedMeters = max(1, Int(Float(footsteps.count) * distanceThreshold))
        let moment = SpatialMoment(
            id: UUID().uuidString,
            index: index,
            title: label,
            subtitle: note.isEmpty ? "Moment \(index)" : note,
            narrative: note.isEmpty ? "Recorded at position (\(String(format: "%.1f", pos.x))m, \(String(format: "%.1f", pos.z))m)." : note,
            architecturalNote: "Local survey coordinate: X=\(String(format: "%.2f", pos.x)), Z=\(String(format: "%.2f", pos.z))",
            distanceAlongPathMeters: walkedMeters,
            hasAudio: false,
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
            guard self.isScanning else { return }
            
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
