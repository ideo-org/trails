//
//  ScannerView.swift
//  Trails
//

import SwiftUI
import RoomPlan

struct ScannerView: View {
    @StateObject private var scannerEngine = RoomScannerEngine()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if scannerEngine.isSupported {
                VStack(spacing: 0) {
                    // Top: AR Camera Feed
                    RoomCameraView(engine: scannerEngine)
                        .frame(height: UIScreen.main.bounds.height * 0.55)
                        .ignoresSafeArea(edges: .top)

                    // Instruction Banner
                    HStack(spacing: 8) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Text("Walk slowly and keep scanning")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.12)) // Dark gray banner
                    
                    // Bottom: Minimap (Top-down 2D layout)
                    RoomLayoutView(
                        capturedRoom: scannerEngine.capturedRoom,
                        footsteps: scannerEngine.footsteps
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Bottom Metrics Bar
                    HStack(spacing: 0) {
                        metricItem(value: "\(scannerEngine.capturedRoom?.walls.count ?? 0)", label: "WALLS")
                        metricItem(value: "\(scannerEngine.capturedRoom?.doors.count ?? 0)", label: "DOORS")
                        metricItem(value: "\(scannerEngine.capturedRoom?.objects.count ?? 0)", label: "OBJECTS")
                        metricItem(value: "\(scannerEngine.footsteps.count)", label: "POINTS")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color(white: 0.12))
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.yellow)
                    Text("RoomPlan is not supported on this device.")
                        .font(.headline)
                    Text("Requires an iPhone or iPad with a LiDAR scanner (iOS 16+).")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            // Top Controls
            VStack {
                HStack {
                    Text("Trails")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(radius: 4)

                    Spacer()

                    Button(action: {
                        scannerEngine.stopScanning()
                        scannerEngine.startScanning()
                    }) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.85))
                            .shadow(radius: 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Spacer()
            }
        }
        .navigationBarHidden(true)
        .background(AppColors.void.ignoresSafeArea())
        .onAppear {
            scannerEngine.startScanning()
        }
        .onDisappear {
            scannerEngine.stopScanning()
        }
    }
    
    private func metricItem(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
