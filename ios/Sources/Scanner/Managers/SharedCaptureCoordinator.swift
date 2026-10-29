//
//  SharedCaptureCoordinator.swift
//  Trails
//
//  Shared camera coordinator for Trails v0.2.1 (PRD §16).
//  Explicitly coordinates camera ownership between CameraCaptureEngine and RoomScannerEngine.
//

import Foundation
import Combine

@MainActor
final class SharedCaptureCoordinator: ObservableObject {
    enum ActiveSubsystem {
        case cameraMedia
        case indoorScanning
        case idle
    }

    @Published private(set) var activeSubsystem: ActiveSubsystem = .idle
    @Published var isScanningPresented: Bool = false

    private weak var cameraEngine: CameraCaptureEngine?
    private weak var roomEngine: RoomScannerEngine?

    init(cameraEngine: CameraCaptureEngine, roomEngine: RoomScannerEngine) {
        self.cameraEngine = cameraEngine
        self.roomEngine = roomEngine
    }

    /// Enter general media capture (photo, video, voice)
    func startCameraMedia() {
        guard activeSubsystem != .cameraMedia else { return }
        roomEngine?.stopScanning()
        cameraEngine?.setupAndStart()
        activeSubsystem = .cameraMedia
        isScanningPresented = false
    }

    /// Enter RoomPlan indoor scanning mode
    func enterIndoorScan() {
        guard activeSubsystem != .indoorScanning else { return }
        // 1. Release camera from media capture engine
        cameraEngine?.stop()
        // 2. Start RoomPlan scanner engine
        roomEngine?.startScanning()
        activeSubsystem = .indoorScanning
        isScanningPresented = true
    }

    /// Return from RoomPlan back to standard camera media
    func exitIndoorScan() {
        // 1. Stop RoomPlan scanner engine
        roomEngine?.stopScanning()
        isScanningPresented = false
        // 2. Re-acquire camera for media capture engine
        cameraEngine?.setupAndStart()
        activeSubsystem = .cameraMedia
    }

    /// Release all hardware resources when leaving the trail capture screen
    func shutdown() {
        cameraEngine?.stop()
        roomEngine?.stopScanning()
        activeSubsystem = .idle
        isScanningPresented = false
    }
}
