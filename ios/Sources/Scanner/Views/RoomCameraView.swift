//
//  RoomCameraView.swift
//  Trails
//

import SwiftUI
import RoomPlan

struct RoomCameraView: UIViewRepresentable {
    @ObservedObject var engine: RoomScannerEngine
    
    func makeUIView(context: Context) -> RoomCaptureView {
        let captureView = engine.getOrCreateCaptureView()
        return captureView
    }
    
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        if engine.captureView !== uiView {
            engine.attach(to: uiView)
        }
    }
}
