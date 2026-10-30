//
//  CameraCaptureEngine.swift
//  Trails
//
//  Native AVCam-style capture pipeline for Trails v0.2.1 (PRD §9, §10, §11, §12).
//  Provides:
//  - Responsive AVCaptureSession with 1080p 30fps video and high-res photo capture
//  - Real AVCapturePhotoOutput and AVCaptureMovieFileOutput
//  - Front / rear camera switching
//  - Torch / flash controls
//  - Supported zoom controls (1.0x, 2.0x, pinch-to-zoom)
//  - Tap to focus and expose
//  - Durable file persistence to trail media storage with lightweight thumbnail generation
//  - Graceful audio permission handling (silent video with clear warning if mic denied)
//

import Foundation
import AVFoundation
import UIKit
import Combine
import ImageIO

@MainActor
public final class CameraCaptureEngine: NSObject, ObservableObject {
    public enum CameraMode: String, CaseIterable, Identifiable {
        case photo = "PHOTO"
        case video = "VIDEO"
        case voice = "VOICE"

        public var id: String { rawValue }
    }

    public enum CaptureState {
        case idle
        case recordingVideo
        case finalizing
    }

    // Published observable states
    @Published public private(set) var isSessionRunning: Bool = false
    @Published public private(set) var captureState: CaptureState = .idle
    @Published public var cameraMode: CameraMode = .photo
    @Published public private(set) var isFrontCamera: Bool = false
    @Published public private(set) var isTorchOn: Bool = false
    @Published public private(set) var isFlashOn: Bool = false
    @Published public private(set) var zoomFactor: CGFloat = 1.0
    @Published public private(set) var maxZoomFactor: CGFloat = 5.0
    @Published public private(set) var isMicrophoneAuthorized: Bool = true
    @Published public private(set) var isCameraAuthorized: Bool = true
    @Published public private(set) var videoRecordingSeconds: Int = 0
    @Published public private(set) var activeVideoDurationString: String = "00:00"
    @Published public var microphoneWarningMessage: String? = nil

    // AVFoundation Session and Devices
    public let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.logos.trails.camera.sessionQueue")

    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let movieFileOutput = AVCaptureMovieFileOutput()

    private var photoContinuation: CheckedContinuation<(image: UIImage, fileURL: URL, thumbnailURL: URL), Error>?
    private var pendingPhotoDestinationURL: URL?
    private var pendingPhotoThumbnailURL: URL?

    private var videoContinuation: CheckedContinuation<(fileURL: URL, duration: TimeInterval, thumbnailURL: URL), Error>?
    private var pendingVideoDestinationURL: URL?
    private var pendingVideoThumbnailURL: URL?
    private var videoTimer: Timer?

    public override init() {
        super.init()
        checkPermissions()
    }

    public func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isCameraAuthorized = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    self?.isCameraAuthorized = granted
                    if granted {
                        self?.configureSession()
                    }
                }
            }
        default:
            isCameraAuthorized = false
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            isMicrophoneAuthorized = true
            microphoneWarningMessage = nil
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor [weak self] in
                    self?.isMicrophoneAuthorized = granted
                    if !granted {
                        self?.microphoneWarningMessage = "Microphone access is off. This video will be recorded without sound."
                    }
                }
            }
        default:
            isMicrophoneAuthorized = false
            microphoneWarningMessage = "Microphone access is off. This video will be recorded without sound."
        }
    }

    public func setupAndStart() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.configureSession()
            self.session.startRunning()
            Task { @MainActor in
                self.isSessionRunning = self.session.isRunning
            }
        }
    }

    public func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            Task { @MainActor in
                self.isSessionRunning = false
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        // Add Video Input
        if let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if session.canAddInput(videoInput) {
                    session.addInput(videoInput)
                    self.videoDeviceInput = videoInput
                }
            } catch {
                print("Failed to create video input: \(error)")
            }
        }

        // Add Audio Input if authorized
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                do {
                    let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                    if session.canAddInput(audioInput) {
                        session.addInput(audioInput)
                        self.audioDeviceInput = audioInput
                    }
                } catch {
                    print("Failed to create audio input: \(error)")
                }
            }
        }

        // Add Photo Output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.maxPhotoQualityPrioritization = .balanced
        }

        // Add Movie Output
        if session.canAddOutput(movieFileOutput) {
            session.addOutput(movieFileOutput)
            if let connection = movieFileOutput.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
        }

        session.commitConfiguration()
    }

    // MARK: - Camera Controls

    public func switchCamera() {
        guard captureState != .recordingVideo else { return }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            let currentPosition = self.videoDeviceInput?.device.position ?? .back
            let newPosition: AVCaptureDevice.Position = (currentPosition == .back) ? .front : .back

            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
                return
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)
                self.session.beginConfiguration()
                if let oldInput = self.videoDeviceInput {
                    self.session.removeInput(oldInput)
                }
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.videoDeviceInput = newInput
                }
                self.session.commitConfiguration()

                Task { @MainActor in
                    self.isFrontCamera = (newPosition == .front)
                    self.zoomFactor = 1.0
                }
            } catch {
                print("Error switching camera: \(error)")
            }
        }
    }

    public func toggleTorch() {
        guard let device = videoDeviceInput?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if device.torchMode == .on {
                device.torchMode = .off
                isTorchOn = false
            } else {
                try device.setTorchModeOn(level: 1.0)
                isTorchOn = true
            }
            device.unlockForConfiguration()
        } catch {
            print("Torch error: \(error)")
        }
    }

    public func toggleFlash() {
        isFlashOn.toggle()
    }

    public func setZoom(factor: CGFloat) {
        guard let device = videoDeviceInput?.device else { return }
        let clamped = max(1.0, min(factor, min(5.0, device.activeFormat.videoMaxZoomFactor)))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            self.zoomFactor = clamped
        } catch {
            print("Zoom error: \(error)")
        }
    }

    public func focusAndExpose(at devicePoint: CGPoint) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {
            print("Focus error: \(error)")
        }
    }

    // MARK: - Photo Capture

    public func capturePhoto(destinationURL: URL, thumbnailURL: URL) async throws -> (image: UIImage, fileURL: URL, thumbnailURL: URL) {
        guard isSessionRunning else {
            throw NSError(domain: "CameraCaptureEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera session is not running."])
        }

        self.pendingPhotoDestinationURL = destinationURL
        self.pendingPhotoThumbnailURL = thumbnailURL

        return try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation
            self.sessionQueue.async { [weak self] in
                guard let self = self else { return }
                var settings = AVCapturePhotoSettings()
                if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                }
                if self.isFlashOn && self.photoOutput.supportedFlashModes.contains(.on) {
                    settings.flashMode = .on
                } else {
                    settings.flashMode = .off
                }
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    // MARK: - Video Recording

    public func startVideoRecording(destinationURL: URL, thumbnailURL: URL) {
        guard captureState == .idle, !movieFileOutput.isRecording else { return }

        // Remove old file if it exists
        try? FileManager.default.removeItem(at: destinationURL)

        self.pendingVideoDestinationURL = destinationURL
        self.pendingVideoThumbnailURL = thumbnailURL
        self.captureState = .recordingVideo
        self.videoRecordingSeconds = 0
        self.activeVideoDurationString = "00:00"

        // Setup recording orientation
        if let connection = movieFileOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.movieFileOutput.startRecording(to: destinationURL, recordingDelegate: self)
        }

        // Start elapsed timer
        videoTimer?.invalidate()
        videoTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.captureState == .recordingVideo else { return }
                self.videoRecordingSeconds += 1
                let m = self.videoRecordingSeconds / 60
                let s = self.videoRecordingSeconds % 60
                self.activeVideoDurationString = String(format: "%02d:%02d", m, s)
            }
        }
    }

    public func stopVideoRecording() async throws -> (fileURL: URL, duration: TimeInterval, thumbnailURL: URL) {
        guard captureState == .recordingVideo else {
            throw NSError(domain: "CameraCaptureEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "No active video recording."])
        }

        videoTimer?.invalidate()
        videoTimer = nil
        captureState = .finalizing

        return try await withCheckedThrowingContinuation { continuation in
            self.videoContinuation = continuation
            sessionQueue.async { [weak self] in
                self?.movieFileOutput.stopRecording()
            }
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraCaptureEngine: AVCapturePhotoCaptureDelegate {
    nonisolated public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            Task { @MainActor in
                self.photoContinuation?.resume(throwing: error)
                self.photoContinuation = nil
            }
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            Task { @MainActor in
                self.photoContinuation?.resume(throwing: NSError(domain: "CameraCaptureEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to extract photo data."]))
                self.photoContinuation = nil
            }
            return
        }

        // Process file I/O and thumbnail generation entirely off the main thread
        Task.detached(priority: .userInitiated) { [weak self, data] in
            guard let self = self else { return }
            let (destURL, thumbURL) = await (self.pendingPhotoDestinationURL, self.pendingPhotoThumbnailURL)

            guard let destURL = destURL, let thumbURL = thumbURL, let image = UIImage(data: data) else {
                await MainActor.run {
                    self.photoContinuation?.resume(throwing: NSError(domain: "CameraCaptureEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to process photo data."]))
                    self.photoContinuation = nil
                }
                return
            }

            do {
                // 1. Write full photo data to disk asynchronously in background
                try data.write(to: destURL, options: .atomic)

                // 2. Hardware-accelerated thumbnail downsampling using ImageIO
                if let thumb = Self.generateDownsampledThumbnail(from: data, maxPixelSize: 400),
                   let thumbData = thumb.jpegData(compressionQuality: 0.8) {
                    try thumbData.write(to: thumbURL, options: .atomic)
                }

                // 3. Return lightweight result to MainActor without freezing the UI or camera pipeline
                await MainActor.run {
                    self.photoContinuation?.resume(returning: (image: image, fileURL: destURL, thumbnailURL: thumbURL))
                    self.photoContinuation = nil
                }
            } catch {
                await MainActor.run {
                    self.photoContinuation?.resume(throwing: error)
                    self.photoContinuation = nil
                }
            }
        }
    }

    nonisolated public static func generateDownsampledThumbnail(from data: Data, maxPixelSize: Int = 400) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraCaptureEngine: AVCaptureFileOutputRecordingDelegate {
    nonisolated public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            let nsError = error as NSError
            if !FileManager.default.fileExists(atPath: outputFileURL.path) {
                Task { @MainActor in
                    self.captureState = .idle
                    self.videoContinuation?.resume(throwing: error)
                    self.videoContinuation = nil
                }
                return
            }
        }

        // Generate video duration and thumbnail off the main thread
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            let thumbURL = await self.pendingVideoThumbnailURL

            guard let thumbURL = thumbURL else {
                await MainActor.run {
                    self.captureState = .idle
                    self.videoContinuation?.resume(throwing: NSError(domain: "CameraCaptureEngine", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing thumbnail target URL."]))
                    self.videoContinuation = nil
                }
                return
            }

            let asset = AVURLAsset(url: outputFileURL)
            let durationSeconds = CMTimeGetSeconds(asset.duration)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 400, height: 400)

            let time = CMTime(seconds: min(1.0, max(0.1, durationSeconds / 2.0)), preferredTimescale: 600)
            if let cgImage = try? imageGenerator.copyCGImage(at: time, actualTime: nil) {
                let thumbImage = UIImage(cgImage: cgImage)
                if let thumbData = thumbImage.jpegData(compressionQuality: 0.8) {
                    try? thumbData.write(to: thumbURL, options: .atomic)
                }
            }

            await MainActor.run {
                self.captureState = .idle
                self.videoContinuation?.resume(returning: (fileURL: outputFileURL, duration: durationSeconds, thumbnailURL: thumbURL))
                self.videoContinuation = nil
            }
        }
    }
}
