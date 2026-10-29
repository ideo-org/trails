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
    
    // Support state
    @Published var isSupported: Bool = RoomCaptureSession.isSupported
    
    private weak var captureView: RoomCaptureView?
    private var isRelocalizing = false
    
    // For path plotting distance threshold (to avoid too many points)
    private var lastRecordedPosition: SIMD3<Float>?
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
        lastRecordedPosition = nil
    }
    
    func stopScanning() {
        captureView?.captureSession.stop()
        isScanning = false
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
