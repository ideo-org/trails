//
//  RoomCameraView.swift
//  Trails
//

import SwiftUI
import RoomPlan

struct RoomCameraView: UIViewRepresentable {
    @ObservedObject var engine: RoomScannerEngine
    
    func makeUIView(context: Context) -> RoomCaptureView {
        let captureView = RoomCaptureView(frame: .zero)
        engine.attach(to: captureView)
        return captureView
    }
    
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        // No updates needed
    }
}
