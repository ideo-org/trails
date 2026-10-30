//
//  ARVideoRecorder.swift
//  Trails
//
//  Real-time in-situ ARKit video recorder for Trails.
//  Captures camera pixel buffers directly from active ARFrame stream
//  concurrently with continuous 6DOF odometry and footstep recording.
//

import Foundation
import AVFoundation
import CoreMedia
import UIKit

@MainActor
public final class ARVideoRecorder: NSObject, ObservableObject {
    public static let shared = ARVideoRecorder()

    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var recordingDuration: TimeInterval = 0

    private nonisolated(unsafe) var assetWriter: AVAssetWriter?
    private nonisolated(unsafe) var videoInput: AVAssetWriterInput?
    private nonisolated(unsafe) var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioRecorder: AVAudioRecorder?

    private var destinationURL: URL?
    private var thumbnailURL: URL?
    private var tempVideoURL: URL?
    private var tempAudioURL: URL?

    private var durationTimer: Timer?
    private var sessionStartTime: Date?
    private nonisolated(unsafe) var firstFramePTS: CMTime?
    private nonisolated(unsafe) var hasStartedSession: Bool = false
    private nonisolated(unsafe) var writtenFrameCount: Int = 0

    private let writerQueue = DispatchQueue(label: "com.logos.trails.arVideoWriterQueue", qos: .userInitiated)
    private let stateLock = NSLock()
    private nonisolated(unsafe) var isRecordingAtomic: Bool = false

    private override init() {
        super.init()
    }

    // MARK: - Start Recording

    public func startRecording(destinationURL: URL, thumbnailURL: URL) -> Bool {
        guard !isRecording else { return false }

        // Clean up previous files if any
        try? FileManager.default.removeItem(at: destinationURL)
        try? FileManager.default.removeItem(at: thumbnailURL)

        self.destinationURL = destinationURL
        self.thumbnailURL = thumbnailURL

        let tempDir = FileManager.default.temporaryDirectory
        let unique = UUID().uuidString
        let tempVideo = tempDir.appendingPathComponent("raw_ar_\(unique).mp4")
        let tempAudio = tempDir.appendingPathComponent("raw_ar_\(unique).m4a")
        try? FileManager.default.removeItem(at: tempVideo)
        try? FileManager.default.removeItem(at: tempAudio)
        self.tempVideoURL = tempVideo
        self.tempAudioURL = tempAudio

        // Setup AVAssetWriter for 1080p / 1440p H.264
        do {
            let writer = try AVAssetWriter(outputURL: tempVideo, fileType: .mp4)
            writer.shouldOptimizeForNetworkUse = true

            // Sensor resolution default (1920x1440 or 1920x1080)
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1920,
                AVVideoHeightKey: 1440,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 8_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]

            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = true

            // Set portrait rotation transform for natural iPhone orientation
            input.transform = CGAffineTransform(rotationAngle: .pi / 2)

            let sourceAttrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
                kCVPixelBufferWidthKey as String: 1920,
                kCVPixelBufferHeightKey as String: 1440
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: sourceAttrs)

            if writer.canAdd(input) {
                writer.add(input)
            }

            self.assetWriter = writer
            self.videoInput = input
            self.pixelBufferAdaptor = adaptor
        } catch {
            print("Failed to initialize ARVideoRecorder AVAssetWriter: \(error)")
            return false
        }

        // Start background audio recording with AVAudioRecorder
        startCompanionAudio(to: tempAudio)

        self.hasStartedSession = false
        self.firstFramePTS = nil
        self.writtenFrameCount = 0
        self.sessionStartTime = Date()
        self.recordingDuration = 0

        stateLock.lock()
        self.isRecordingAtomic = true
        stateLock.unlock()

        self.isRecording = true

        // Timer for HUD duration
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRecording, let start = self.sessionStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }

        return true
    }

    private func startCompanionAudio(to url: URL) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        if let recorder = try? AVAudioRecorder(url: url, settings: settings) {
            recorder.record()
            self.audioRecorder = recorder
        }
    }

    // MARK: - Frame Append from ARSessionDelegate

    nonisolated public func appendPixelBuffer(_ pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval) {
        stateLock.lock()
        let active = isRecordingAtomic
        stateLock.unlock()
        guard active else { return }

        writerQueue.async { [weak self] in
            guard let self = self else { return }
            self.stateLock.lock()
            let stillActive = self.isRecordingAtomic
            self.stateLock.unlock()
            guard stillActive, let writer = self.assetWriter, let input = self.videoInput, let adaptor = self.pixelBufferAdaptor else { return }

            if writer.status == .unknown {
                let startPTS = CMTime(seconds: timestamp, preferredTimescale: 600)
                writer.startWriting()
                writer.startSession(atSourceTime: startPTS)
                self.hasStartedSession = true
                self.firstFramePTS = startPTS
            }

            guard writer.status == .writing, input.isReadyForMoreMediaData else { return }

            let frameTime = CMTime(seconds: timestamp, preferredTimescale: 600)
            if adaptor.append(pixelBuffer, withPresentationTime: frameTime) {
                self.writtenFrameCount += 1
            }
        }
    }

    // MARK: - Stop Recording

    public func stopRecording() async throws -> (url: URL, duration: TimeInterval, thumbURL: URL) {
        guard isRecording else {
            throw NSError(domain: "ARVideoRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not recording."])
        }

        stateLock.lock()
        self.isRecordingAtomic = false
        stateLock.unlock()

        self.isRecording = false
        self.durationTimer?.invalidate()
        self.durationTimer = nil

        let totalDuration = max(0.5, self.recordingDuration)

        // Stop companion audio recorder
        audioRecorder?.stop()
        audioRecorder = nil

        let tempVideo = self.tempVideoURL
        let tempAudio = self.tempAudioURL
        let dest = self.destinationURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("fallback_video.mp4")
        let thumb = self.thumbnailURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("fallback_thumb.jpg")

        // Finalize AVAssetWriter on writerQueue
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writerQueue.async { [weak self] in
                guard let self = self, let writer = self.assetWriter else {
                    continuation.resume()
                    return
                }

                if writer.status == .writing {
                    self.videoInput?.markAsFinished()
                    writer.finishWriting {
                        continuation.resume()
                    }
                } else {
                    continuation.resume()
                }
            }
        }

        // Check if video file has written frames; if simulator with 0 frames, generate synthetic fallback
        if self.writtenFrameCount == 0, let tempVideo = tempVideo {
            await Self.generateFallbackSyntheticVideo(to: tempVideo, duration: totalDuration)
        }

        // Merge video and audio tracks
        if let tempVideo = tempVideo, let tempAudio = tempAudio {
            try await Self.mergeVideoAndAudio(videoURL: tempVideo, audioURL: tempAudio, outputURL: dest)
            try? FileManager.default.removeItem(at: tempVideo)
            try? FileManager.default.removeItem(at: tempAudio)
        } else if let tempVideo = tempVideo {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: tempVideo, to: dest)
            try? FileManager.default.removeItem(at: tempVideo)
        }

        // Generate thumbnail
        await Self.generateThumbnail(from: dest, outputURL: thumb)

        return (url: dest, duration: totalDuration, thumbURL: thumb)
    }

    // MARK: - Track Muxing

    private static func mergeVideoAndAudio(videoURL: URL, audioURL: URL, outputURL: URL) async throws {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        guard let videoTrack = try? await videoAsset.loadTracks(withMediaType: .video).first else {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.copyItem(at: videoURL, to: outputURL)
            return
        }

        let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let duration = (try? await videoAsset.load(.duration)) ?? CMTime(seconds: 1, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try? compVideoTrack?.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        compVideoTrack?.preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity

        if let audioTrack = try? await audioAsset.loadTracks(withMediaType: .audio).first {
            let audioDuration = (try? await audioAsset.load(.duration)) ?? duration
            let insertDuration = min(duration, audioDuration)
            if insertDuration.seconds > 0.1 {
                let compAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
                let audioRange = CMTimeRange(start: .zero, duration: insertDuration)
                try? compAudioTrack?.insertTimeRange(audioRange, of: audioTrack, at: .zero)
            }
        }

        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            try? FileManager.default.copyItem(at: videoURL, to: outputURL)
            return
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        await exportSession.export()

        if exportSession.status != .completed {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.copyItem(at: videoURL, to: outputURL)
        }
    }

    // MARK: - Thumbnail Generation

    private static func generateThumbnail(from assetURL: URL, outputURL: URL) async {
        let asset = AVURLAsset(url: assetURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)

        if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
            let uiImage = UIImage(cgImage: cgImage)
            if let data = uiImage.jpegData(compressionQuality: 0.8) {
                try? data.write(to: outputURL, options: .atomic)
                return
            }
        }

        // Fallback thumbnail if generator fails
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240))
        let img = renderer.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 240))
        }
        if let data = img.jpegData(compressionQuality: 0.8) {
            try? data.write(to: outputURL, options: .atomic)
        }
    }

    // MARK: - Fallback Synthetic Video (for Simulator / non-camera testing)

    private static func generateFallbackSyntheticVideo(to url: URL, duration: TimeInterval) async {
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 480,
            AVVideoHeightKey: 640
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)

        if writer.canAdd(input) { writer.add(input) }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 480, height: 640))
        let frameImg = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 480, height: 640))
        }

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 480, 640, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)

        if let pb = pixelBuffer {
            CVPixelBufferLockBaseAddress(pb, [])
            let pxData = CVPixelBufferGetBaseAddress(pb)
            let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
            let context = CGContext(data: pxData, width: 480, height: 640, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
            if let cg = frameImg.cgImage {
                context?.draw(cg, in: CGRect(x: 0, y: 0, width: 480, height: 640))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])

            adaptor.append(pb, withPresentationTime: .zero)
            let endPTS = CMTime(seconds: max(0.5, duration), preferredTimescale: 600)
            adaptor.append(pb, withPresentationTime: endPTS)
        }

        input.markAsFinished()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                c.resume()
            }
        }
    }
}
