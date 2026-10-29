//
//  AudioManager.swift
//  Trails
//
//  Offline audio recording and playback service for voice moments (PRD v0.2.0 §8.3 & §10.1).
//

import Foundation
import AVFoundation
import Combine

@MainActor
public final class AudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate, AVAudioRecorderDelegate {
    public static let shared = AudioManager()

    @Published public var isRecording: Bool = false
    @Published public var isPlaying: Bool = false
    @Published public var recordingDuration: TimeInterval = 0
    @Published public var playbackTime: TimeInterval = 0
    @Published public var playbackDuration: TimeInterval = 0
    @Published public var currentPlayingId: String?

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var playbackTimer: Timer?

    private override init() {
        super.init()
    }

    // MARK: - Recording

    public func startRecording(destinationURL: URL) -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            return false
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: destinationURL, settings: settings)
            recorder.delegate = self
            recorder.record()
            self.audioRecorder = recorder
            self.isRecording = true
            self.recordingDuration = 0

            recordingTimer?.invalidate()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, self.isRecording else { return }
                    self.recordingDuration = self.audioRecorder?.currentTime ?? 0
                }
            }
            return true
        } catch {
            return false
        }
    }

    public func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard let recorder = audioRecorder, isRecording else { return nil }
        let duration = recorder.currentTime
        let url = recorder.url
        recorder.stop()
        audioRecorder = nil
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        return (url, duration)
    }

    // MARK: - Playback

    public func playAudio(url: URL, identifier: String? = nil) {
        stopPlayback()

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.play()
            self.audioPlayer = player
            self.isPlaying = true
            self.currentPlayingId = identifier
            self.playbackDuration = player.duration
            self.playbackTime = 0

            playbackTimer?.invalidate()
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, let p = self.audioPlayer, p.isPlaying else { return }
                    self.playbackTime = p.currentTime
                }
            }
        } catch {
            // Audio playback error handling
        }
    }

    public func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        playbackTimer?.invalidate()
    }

    public func resumePlayback() {
        audioPlayer?.play()
        isPlaying = true
    }

    public func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentPlayingId = nil
        playbackTime = 0
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    // MARK: - Delegates

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentPlayingId = nil
            self.playbackTime = 0
            self.playbackTimer?.invalidate()
            self.playbackTimer = nil
        }
    }
}
