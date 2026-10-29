//
//  FullScreenCameraCaptureView.swift
//  Trails
//
//  Dedicated full-screen camera & video recording interface for Trails.
//  Enables creators to document trail stops/waypoints with full-screen focus,
//  and seamlessly return to the active trail view once captured or dismissed.
//

import SwiftUI
import AVFoundation

public struct FullScreenCameraCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var cameraEngine: CameraCaptureEngine

    let mode: CameraCaptureEngine.CameraMode
    let waypointIndex: Int
    let trailId: String
    let onSavedVideo: (URL, TimeInterval, URL) -> Void
    let onSavedPhoto: (UIImage, URL, URL) -> Void
    let onCancel: () -> Void

    @State private var isFlashActive: Bool = false
    @State private var isProcessing: Bool = false

    public init(
        cameraEngine: CameraCaptureEngine,
        mode: CameraCaptureEngine.CameraMode,
        waypointIndex: Int,
        trailId: String,
        onSavedVideo: @escaping (URL, TimeInterval, URL) -> Void,
        onSavedPhoto: @escaping (UIImage, URL, URL) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.cameraEngine = cameraEngine
        self.mode = mode
        self.waypointIndex = waypointIndex
        self.trailId = trailId
        self.onSavedVideo = onSavedVideo
        self.onSavedPhoto = onSavedPhoto
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            // MARK: - 1. Full Screen Live Camera Viewport
            CameraPreviewView(cameraEngine: cameraEngine)
                .ignoresSafeArea()
                .overlay(
                    Color.white
                        .opacity(isFlashActive ? 0.85 : 0.0)
                        .animation(.easeOut(duration: 0.15), value: isFlashActive)
                        .ignoresSafeArea()
                )

            // MARK: - 2. HUD Overlays
            VStack(spacing: 0) {
                // Top Action & Status Bar
                topHUDBar

                // Microphone Warning (if recording video without audio permission)
                if let warning = cameraEngine.microphoneWarningMessage, mode == .video {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 11))
                        Text(warning)
                            .font(AppFonts.caption)
                    }
                    .foregroundColor(AppColors.terracotta)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.top, 8)
                }

                Spacer()

                // Quick Zoom Dock [ 1x | 2x | 3x ]
                zoomDock
                    .padding(.bottom, 20)

                // Bottom Shutter & Controls Console
                bottomShutterConsole
            }

            // Processing overlay if saving media
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.3)
                        Text(mode == .video ? "Anchoring Video Waypoint..." : "Anchoring Photo Waypoint...")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(18)
                }
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            cameraEngine.cameraMode = mode
            cameraEngine.setupAndStart()
        }
    }

    // MARK: - Top HUD Bar

    private var topHUDBar: some View {
        HStack {
            // Back to Trail View Button
            Button {
                Haptics.light()
                if cameraEngine.captureState == .recordingVideo {
                    Task {
                        _ = try? await cameraEngine.stopVideoRecording()
                        cameraEngine.stop()
                        onCancel()
                        dismiss()
                    }
                } else {
                    cameraEngine.stop()
                    onCancel()
                    dismiss()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                    Text("Trail View")
                        .font(AppFonts.labelUI)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.55))
                .clipShape(Capsule())
            }

            Spacer()

            // Waypoint Badge & Recording Timer
            HStack(spacing: 6) {
                if cameraEngine.captureState == .recordingVideo {
                    Circle()
                        .fill(AppColors.terracotta)
                        .frame(width: 8, height: 8)
                        .scaleEffect(1.2)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: cameraEngine.captureState == .recordingVideo)
                    Text("REC · \(cameraEngine.activeVideoDurationString)")
                        .font(AppFonts.labelSpatial)
                        .fontWeight(.bold)
                        .foregroundColor(AppColors.terracotta)
                } else {
                    Circle()
                        .fill(mode == .video ? AppColors.terracotta : AppColors.mutedBrass)
                        .frame(width: 7, height: 7)
                    Text("WAYPOINT \(waypointIndex) · \(mode.rawValue)")
                        .font(AppFonts.labelSpatial)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.65))
            .clipShape(Capsule())

            Spacer()

            // Torch & Camera Flip actions
            HStack(spacing: 10) {
                // Torch
                Button {
                    Haptics.light()
                    cameraEngine.toggleTorch()
                } label: {
                    Image(systemName: cameraEngine.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.system(size: 14))
                        .foregroundColor(cameraEngine.isTorchOn ? AppColors.mutedBrass : .white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                }

                // Flip Camera
                Button {
                    Haptics.light()
                    cameraEngine.switchCamera()
                } label: {
                    Image(systemName: "camera.rotate.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                }
                .disabled(cameraEngine.captureState == .recordingVideo)
                .opacity(cameraEngine.captureState == .recordingVideo ? 0.35 : 1.0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 48)
    }

    // MARK: - Zoom Dock

    private var zoomDock: some View {
        HStack(spacing: 6) {
            ForEach([1.0, 2.0, 3.0], id: \.self) { factor in
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.25)) {
                        cameraEngine.setZoom(factor: CGFloat(factor))
                    }
                } label: {
                    Text(String(format: "%.0fx", factor))
                        .font(AppFonts.labelSpatial)
                        .fontWeight(.bold)
                        .foregroundColor(abs(cameraEngine.zoomFactor - factor) < 0.2 ? AppColors.primary : .white)
                        .frame(width: 36, height: 36)
                        .background(abs(cameraEngine.zoomFactor - factor) < 0.2 ? Color.white : Color.clear)
                        .clipShape(Circle())
                }
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.55))
        .clipShape(Capsule())
    }

    // MARK: - Bottom Shutter Console

    private var bottomShutterConsole: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()

                // Primary Shutter Button
                if mode == .video {
                    videoShutterButton
                } else {
                    photoShutterButton
                }

                Spacer()
            }

            Text(mode == .video ? (cameraEngine.captureState == .recordingVideo ? "Tap red square to finish & anchor waypoint" : "Tap to record checkpoint video") : "Tap to snap photo & anchor waypoint")
                .font(AppFonts.caption)
                .foregroundColor(Color.white.opacity(0.75))
                .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 36)
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.65), Color.black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Shutter Buttons

    private var videoShutterButton: some View {
        Button {
            triggerVideoToggle()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4.5)
                    .frame(width: 78, height: 78)

                if cameraEngine.captureState == .recordingVideo {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppColors.terracotta)
                        .frame(width: 32, height: 32)
                } else {
                    Circle()
                        .fill(AppColors.terracotta)
                        .frame(width: 64, height: 64)
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var photoShutterButton: some View {
        Button {
            triggerPhotoCapture()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4.5)
                    .frame(width: 78, height: 78)

                Circle()
                    .fill(Color.white)
                    .frame(width: 64, height: 64)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isProcessing)
    }

    // MARK: - Capture Handlers

    private func triggerVideoToggle() {
        if cameraEngine.captureState == .recordingVideo {
            // Stop recording
            Haptics.heavy()
            isProcessing = true
            Task {
                do {
                    let result = try await cameraEngine.stopVideoRecording()
                    cameraEngine.stop()
                    isProcessing = false
                    onSavedVideo(result.fileURL, result.duration, result.thumbnailURL)
                    dismiss()
                } catch {
                    isProcessing = false
                    cameraEngine.stop()
                    dismiss()
                }
            }
        } else {
            // Start recording
            Haptics.medium()
            let id = UUID().uuidString
            let videoName = "video_\(id).mov"
            let thumbName = "thumb_video_\(id).jpg"
            let destURL = TrailPackageStore.shared.mediaDirectory(for: trailId).appendingPathComponent(videoName)
            let thumbURL = TrailPackageStore.shared.mediaDirectory(for: trailId).appendingPathComponent(thumbName)

            cameraEngine.startVideoRecording(destinationURL: destURL, thumbnailURL: thumbURL)
        }
    }

    private func triggerPhotoCapture() {
        guard !isProcessing else { return }
        Haptics.medium()
        isFlashActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            isFlashActive = false
        }

        let id = UUID().uuidString
        let photoName = "photo_\(id).jpg"
        let thumbName = "thumb_\(id).jpg"
        let destURL = TrailPackageStore.shared.mediaDirectory(for: trailId).appendingPathComponent(photoName)
        let thumbURL = TrailPackageStore.shared.mediaDirectory(for: trailId).appendingPathComponent(thumbName)

        isProcessing = true
        Task {
            do {
                let result = try await cameraEngine.capturePhoto(destinationURL: destURL, thumbnailURL: thumbURL)
                cameraEngine.stop()
                isProcessing = false
                onSavedPhoto(result.image, result.fileURL, result.thumbnailURL)
                dismiss()
            } catch {
                isProcessing = false
                cameraEngine.stop()
                dismiss()
            }
        }
    }
}
