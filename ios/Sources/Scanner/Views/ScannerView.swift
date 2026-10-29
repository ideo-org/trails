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

    var body: some View {
        ZStack {
            if scannerEngine.isSupported {
                VStack(spacing: 0) {
                    // Top: AR Camera Feed
                    RoomCameraView(engine: scannerEngine)
                        .frame(height: UIScreen.main.bounds.height * 0.52)
                        .ignoresSafeArea(edges: .top)

                    // Instruction Banner
                    HStack(spacing: 8) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        Text("Walk slowly and keep scanning")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)

                        Spacer()

                        if !scannerEngine.recordedMoments.isEmpty {
                            Label("\(scannerEngine.recordedMoments.count) moments", systemImage: "flag.fill")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppColors.terracotta)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(white: 0.12)) // Dark gray banner
                    
                    // Bottom: Minimap (Top-down 2D layout)
                    ZStack(alignment: .bottom) {
                        RoomLayoutView(
                            capturedRoom: scannerEngine.capturedRoom,
                            footsteps: scannerEngine.footsteps,
                            moments: scannerEngine.recordedMoments
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // In-capture Actions Dock: Add Moment & Finish
                        HStack(spacing: 12) {
                            Button {
                                momentLabel = ""
                                momentNote = ""
                                showingAddMomentSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "flag.badge.ellipsis")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("Add Moment")
                                        .font(.system(size: 13, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.18))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                            }

                            Spacer()

                            Button {
                                finishScan()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("Finish Trail")
                                        .font(.system(size: 13, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(AppColors.primary)
                                .clipShape(Capsule())
                                .shadow(color: AppColors.primary.opacity(0.4), radius: 6, x: 0, y: 3)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                    }
                    
                    // Bottom Metrics Bar
                    HStack(spacing: 0) {
                        metricItem(value: "\(scannerEngine.capturedRoom?.walls.count ?? 0)", label: "WALLS")
                        metricItem(value: "\(scannerEngine.capturedRoom?.doors.count ?? 0)", label: "DOORS")
                        metricItem(value: "\(scannerEngine.capturedRoom?.objects.count ?? 0)", label: "OBJECTS")
                        metricItem(value: "\(scannerEngine.footsteps.count)", label: "POINTS")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
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
            
            // Top Controls Overlay
            VStack {
                HStack {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)

                        Text("Trails")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .shadow(radius: 4)

                    Spacer()

                    Button {
                        showingCancelConfirm = true
                    } label: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 28))
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
        .sheet(isPresented: $showingAddMomentSheet) {
            AddMomentSheet(
                label: $momentLabel,
                note: $momentNote,
                onSave: {
                    scannerEngine.addMoment(label: momentLabel, note: momentNote)
                    showingAddMomentSheet = false
                },
                onCancel: {
                    showingAddMomentSheet = false
                }
            )
            .presentationDetents([.height(280)])
        }
        .sheet(isPresented: $showingReviewSheet) {
            ReviewPublishTrailView()
        }
        .confirmationDialog(
            "Discard this recording?",
            isPresented: $showingCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard and Restart", role: .destructive) {
                scannerEngine.stopScanning()
                scannerEngine.startScanning()
            }
            Button("Keep Recording", role: .cancel) {}
        }
    }
    
    private func finishScan() {
        scannerEngine.stopScanning()

        let walkedMeters = max(1, Int(Float(scannerEngine.footsteps.count) * 0.2))
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
            meshDensity: "\(scannerEngine.capturedRoom?.walls.count ?? 0) walls detected",
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

// MARK: - Add Moment Quick Sheet (PRD §8.3 & §9.3)

private struct AddMomentSheet: View {
    @Binding var label: String
    @Binding var note: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tag Moment Along Trail")
                    .font(AppFonts.headlineSmall)
                    .foregroundColor(AppColors.deepInk)

                TextField("Moment label (e.g. Entrance Archway)", text: $label)
                    .font(AppFonts.bodyMedium)
                    .padding(12)
                    .background(AppColors.surfaceContainerLow)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                TextField("Optional observation or note", text: $note)
                    .font(AppFonts.bodyMedium)
                    .padding(12)
                    .background(AppColors.surfaceContainerLow)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer()

                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .font(AppFonts.labelUI)
                        .foregroundColor(AppColors.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.surfaceContainerHigh)
                        .clipShape(Capsule())

                    Button("Save Moment", action: onSave)
                        .font(AppFonts.labelUI)
                        .foregroundColor(AppColors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(label.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : AppColors.primary)
                        .clipShape(Capsule())
                        .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .background(AppColors.canvas.ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }
}
