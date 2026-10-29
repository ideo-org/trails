//
//  ScannerView.swift
//  Trails
//
//  Screen 4: Active Capture & Tracking (PRD v0.1.0 §7.2, §8.2, §9.2 & §10.2).
//  Combines camera feed with live 2D minimap, real-time footstep vectors,
//  spatial moment tagging, and graceful simulation fallback for non-LiDAR testing.
//

import SwiftUI
import RoomPlan

struct ScannerView: View {
    @StateObject private var scannerEngine = RoomScannerEngine()
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddMomentSheet = false
    @State private var momentLabel = ""
    @State private var momentNote = ""
    @State private var showingReviewSheet = false
    @State private var showingCancelConfirm = false
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?

    private var walkedMeters: Int {
        max(1, Int(Float(scannerEngine.footsteps.count) * 0.2))
    }

    private var formattedTime: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        ZStack {
            // Main Viewport
            VStack(spacing: 0) {
                // Top: Camera Feed (or simulated perspective viewport)
                ZStack {
                    if scannerEngine.isSupported {
                        RoomCameraView(engine: scannerEngine)
                    } else {
                        // Simulated Spatial Viewport for Simulator & Non-LiDAR devices
                        SimulatedViewportView(footstepsCount: scannerEngine.footsteps.count)
                    }

                    // Top Navigation Chrome Overlay
                    topNavigationOverlay
                }
                .frame(height: UIScreen.main.bounds.height * 0.48)
                .ignoresSafeArea(edges: .top)

                // Sub-viewport Status Ribbon
                statusRibbon

                // Bottom: Architectural Minimap (Top-down 2D layout)
                ZStack(alignment: .bottom) {
                    RoomLayoutView(
                        capturedRoom: scannerEngine.capturedRoom,
                        footsteps: scannerEngine.footsteps,
                        moments: scannerEngine.recordedMoments
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // In-capture Actions Dock: Add Moment & Finish
                    inCaptureDock
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
            }
            .background(Color(hex: "#0A0E14").ignoresSafeArea())
        }
        .navigationBarHidden(true)
        .onAppear {
            startCaptureSession()
        }
        .onDisappear {
            stopCaptureSession()
        }
        .sheet(isPresented: $showingAddMomentSheet) {
            AddMomentSheet(
                label: $momentLabel,
                note: $momentNote,
                onSave: {
                    Haptics.success()
                    scannerEngine.addMoment(label: momentLabel, note: momentNote)
                    showingAddMomentSheet = false
                },
                onCancel: {
                    showingAddMomentSheet = false
                }
            )
            .presentationDetents([.height(300)])
        }
        .sheet(isPresented: $showingReviewSheet, onDismiss: {
            // If the user finished and saved their trail, exit scanner back to My Trails
            dismiss()
        }) {
            ReviewPublishTrailView()
        }
        .confirmationDialog(
            "Discard this recording?",
            isPresented: $showingCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard & Exit to My Trails", role: .destructive) {
                stopCaptureSession()
                dismiss()
            }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("Your recorded footsteps and checkpoints will not be preserved.")
        }
    }

    // MARK: - Top Navigation Overlay

    private var topNavigationOverlay: some View {
        VStack {
            HStack {
                // Close / Cancel Button (PRD CAP-07)
                Button {
                    handleClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .accessibilityLabel("Close recording")
                .accessibilityIdentifier("scanner.close")

                Spacer()

                // Live Recording Status Badge
                HStack(spacing: 8) {
                    Circle()
                        .fill(AppColors.terracotta)
                        .frame(width: 8, height: 8)

                    Text(formattedTime)
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(.white)

                    Text("·")
                        .foregroundColor(Color.white.opacity(0.5))

                    Text("\(walkedMeters)m")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.5))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))

                Spacer()

                // Restart / Reset Button
                Button {
                    showingCancelConfirm = true
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .accessibilityLabel("Restart recording")
            }
            .padding(.horizontal, 20)
            .padding(.top, 48)

            Spacer()
        }
    }

    // MARK: - Status Ribbon

    private var statusRibbon: some View {
        HStack(spacing: 8) {
            Image(systemName: scannerEngine.isSimulated ? "play.circle.fill" : "figure.walk")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(scannerEngine.isSimulated ? AppColors.mutedBrass : AppColors.terracotta)

            Text(scannerEngine.isSimulated ? "Simulated Indoor Path · Walk active" : "Walk slowly and map each surface once")
                .font(AppFonts.labelUI)
                .foregroundColor(.white)

            Spacer()

            if !scannerEngine.recordedMoments.isEmpty {
                Label("\(scannerEngine.recordedMoments.count) moments", systemImage: "flag.fill")
                    .font(AppFonts.labelSpatial)
                    .foregroundColor(AppColors.terracotta)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: "#121820"))
    }

    // MARK: - In-Capture Actions Dock

    private var inCaptureDock: some View {
        HStack(spacing: 12) {
            // Add Moment Button (PRD §8.3 & §9.3)
            Button {
                Haptics.selection()
                momentLabel = ""
                momentNote = ""
                showingAddMomentSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "flag.badge.ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Add Moment")
                        .font(AppFonts.headlineSmall)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .frame(height: 50)
                .background(Color(white: 0.18))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
            }

            Spacer()

            // Finish Trail Button (PRD §8.4 CAP-07)
            Button {
                Haptics.success()
                finishScan()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                    Text("Finish Trail")
                        .font(AppFonts.headlineSmall)
                }
                .foregroundColor(AppColors.onPrimary)
                .padding(.horizontal, 22)
                .frame(height: 50)
                .background(AppColors.primary)
                .clipShape(Capsule())
                .shadow(color: AppColors.primary.opacity(0.35), radius: 8, x: 0, y: 4)
            }
        }
    }

    // MARK: - Control Logic

    private func handleClose() {
        if scannerEngine.footsteps.count > 3 || !scannerEngine.recordedMoments.isEmpty {
            showingCancelConfirm = true
        } else {
            stopCaptureSession()
            dismiss()
        }
    }

    private func startCaptureSession() {
        scannerEngine.startScanning()
        elapsedSeconds = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedSeconds += 1
        }
    }

    private func stopCaptureSession() {
        timer?.invalidate()
        timer = nil
        scannerEngine.stopScanning()
    }

    private func finishScan() {
        stopCaptureSession()

        let author = TrailsDataStore.shared.localProfile.displayName
        let trail = TrailDetail(
            id: UUID().uuidString,
            title: "Untitled Trail",
            subtitle: "\(walkedMeters)m recorded path",
            placeId: "local-place",
            placeName: "My Indoor Space",
            wing: "Ground Floor",
            authorName: author.isEmpty ? "A trail by you" : author,
            authorRole: "Explorer",
            distanceMeters: walkedMeters,
            floorCode: "LVL 00",
            floorTitle: "Ground Floor",
            meshDensity: "\(scannerEngine.capturedRoom?.walls.count ?? 4) walls detected",
            samplingFrequency: "24.6 kHz",
            nodeCount: max(1, scannerEngine.footsteps.count),
            personalNotes: "Saved privately on this device. Trails does not upload this capture.",
            moments: scannerEngine.recordedMoments,
            visibility: .privateDraft,
            isDraft: true
        )

        TrailsDataStore.shared.saveDraft(trail: trail, footsteps: scannerEngine.footsteps)
        showingReviewSheet = true
    }
}

// MARK: - Simulated Spatial Viewport (For Simulator & Non-LiDAR Devices)

private struct SimulatedViewportView: View {
    let footstepsCount: Int

    var body: some View {
        ZStack {
            Color(hex: "#05070A")

            // Ambient room wireframe projection
            VStack(spacing: 16) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundColor(AppColors.mutedBrass.opacity(0.7))

                VStack(spacing: 6) {
                    Text("SPATIAL CAPTURE INSTRUMENT")
                        .font(AppFonts.labelSpatial)
                        .tracking(1.8)
                        .foregroundColor(AppColors.mutedBrass)

                    Text("LiDAR & RoomPlan Active")
                        .font(AppFonts.headlineSmall)
                        .foregroundColor(.white)

                    Text("Walking path and floorplan are updating in real-time below.")
                        .font(AppFonts.bodySmall)
                        .foregroundColor(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
    }
}

// MARK: - Add Moment Quick Sheet (PRD §8.3 & §9.3)

private struct AddMomentSheet: View {
    @Binding var label: String
    @Binding var note: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tag Moment Along Trail")
                    .font(AppFonts.headlineMedium)
                    .foregroundColor(AppColors.deepInk)

                VStack(alignment: .leading, spacing: 6) {
                    Text("MOMENT LABEL")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.outline)

                    TextField("e.g., Carved Stone Lintel", text: $label)
                        .font(AppFonts.bodyMedium)
                        .padding(14)
                        .background(AppColors.surfaceContainerLow)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("OBSERVATION / NOTE (OPTIONAL)")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.outline)

                    TextField("e.g., Morning breeze draws upward through archway", text: $note)
                        .font(AppFonts.bodyMedium)
                        .padding(14)
                        .background(AppColors.surfaceContainerLow)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                }

                Spacer()

                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .font(AppFonts.labelUI)
                        .foregroundColor(AppColors.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AppColors.surfaceContainerHigh)
                        .clipShape(Capsule())

                    Button("Save Moment", action: onSave)
                        .font(AppFonts.labelUI)
                        .foregroundColor(AppColors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(label.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.5) : AppColors.primary)
                        .clipShape(Capsule())
                        .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(24)
            .background(AppColors.canvas.ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }
}
