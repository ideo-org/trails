import Foundation
import UIKit
import Vision
import Combine

/// Real-time frame visual and orientation matcher that compares live AR/camera frames
/// against reference vantage frames (initial start photo or checkpoint moments).
@MainActor
public final class FrameAlignmentMatcher: ObservableObject {
    public static let shared = FrameAlignmentMatcher()

    // MARK: - Published Alignment State
    @Published public private(set) var matchPercentage: Int = 0
    @Published public private(set) var headingDeltaDegrees: Double = 0
    @Published public private(set) var visualSimilarityScore: Double = 0
    @Published public private(set) var alignmentGuidanceText: String = "Point camera at starting view"
    @Published public private(set) var isWellAligned: Bool = false
    @Published public private(set) var isAnalyzing: Bool = false

    // MARK: - Reference Target
    private var referenceImage: UIImage?
    private var referenceFeaturePrint: VNFeaturePrintObservation?
    private var referenceHeading: Double?
    private var referenceTitle: String = "Start Frame"

    // Queue for Vision feature extraction off the main thread
    private let visionQueue = DispatchQueue(label: "com.trails.frameAlignmentMatcher", qos: .userInitiated)
    private var lastAnalysisTimestamp: Date = .distantPast
    private let analysisInterval: TimeInterval = 0.35 // Run match analysis ~3 times per second

    public init() {}

    /// Configure the matcher with a reference image and optional target compass heading.
    public func setReference(image: UIImage?, heading: Double?, title: String = "Start Frame") {
        self.referenceImage = image
        self.referenceHeading = heading
        self.referenceTitle = title
        self.referenceFeaturePrint = nil
        self.matchPercentage = 0
        self.visualSimilarityScore = 0
        self.isWellAligned = false
        self.alignmentGuidanceText = "Analyzing reference frame..."

        guard let img = image, let cgImage = img.cgImage else {
            alignmentGuidanceText = "No reference frame image available"
            return
        }

        // Precompute reference feature print asynchronously
        visionQueue.async { [weak self] in
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let request = VNGenerateImageFeaturePrintRequest()
            do {
                try handler.perform([request])
                if let observation = request.results?.first as? VNFeaturePrintObservation {
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.referenceFeaturePrint = observation
                        self.alignmentGuidanceText = "Aim camera to match \(title)"
                    }
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.alignmentGuidanceText = "Aim camera to match \(title)"
                }
            }
        }
    }

    /// Reset all alignment state
    public func reset() {
        referenceImage = nil
        referenceFeaturePrint = nil
        referenceHeading = nil
        matchPercentage = 0
        headingDeltaDegrees = 0
        visualSimilarityScore = 0
        isWellAligned = false
        alignmentGuidanceText = "Point camera at starting view"
    }

    /// Update with the current live camera frame and live compass/AR yaw heading.
    public func updateLiveFrame(image: UIImage?, liveHeading: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastAnalysisTimestamp) >= analysisInterval else { return }
        lastAnalysisTimestamp = now

        // 1. Heading Alignment Calculation
        var headingScore: Double = 0.5
        var turnCue: String = ""

        if let targetHeading = referenceHeading {
            // Signed angle difference in -180...180
            var diff = (targetHeading - liveHeading).truncatingRemainder(dividingBy: 360.0)
            if diff > 180 { diff -= 360 }
            if diff < -180 { diff += 360 }

            self.headingDeltaDegrees = diff
            let absDiff = abs(diff)

            if absDiff <= 8.0 {
                headingScore = 1.0
                turnCue = "Facing target view ✓"
            } else if absDiff <= 25.0 {
                headingScore = max(0.6, 1.0 - (absDiff / 35.0))
                turnCue = diff > 0 ? "Turn right \(Int(absDiff))°" : "Turn left \(Int(absDiff))°"
            } else if absDiff <= 65.0 {
                headingScore = max(0.2, 1.0 - (absDiff / 75.0))
                turnCue = diff > 0 ? "Turn right \(Int(absDiff))°" : "Turn left \(Int(absDiff))°"
            } else {
                headingScore = 0.05
                turnCue = diff > 0 ? "Turn right \(Int(absDiff))°" : "Turn left \(Int(absDiff))°"
            }
        } else {
            self.headingDeltaDegrees = 0
        }

        // 2. Visual Feature Print Comparison
        guard let refPrint = referenceFeaturePrint,
              let liveImg = image,
              let liveCGImage = liveImg.cgImage else {
            // Fallback to heading only if visual print is not ready yet
            applyScore(visualScore: 0.5, headingScore: headingScore, turnCue: turnCue)
            return
        }

        guard !isAnalyzing else { return }
        isAnalyzing = true

        visionQueue.async { [weak self, refPrint] in
            let handler = VNImageRequestHandler(cgImage: liveCGImage, options: [:])
            let request = VNGenerateImageFeaturePrintRequest()
            var computedVisualScore: Double = 0.5

            do {
                try handler.perform([request])
                if let livePrint = request.results?.first as? VNFeaturePrintObservation {
                    var distance: Float = 1.0
                    try refPrint.computeDistance(&distance, to: livePrint)

                    // Apple Vision distance:
                    // 0.0 .. 0.35 = very high similarity (same physical vantage)
                    // 0.35 .. 0.65 = moderate scene match
                    // 0.65 .. 1.0+ = divergent / different room or angle
                    let clampedDist = max(0.0, min(1.2, Double(distance)))
                    // Map distance to 0.0 .. 1.0
                    computedVisualScore = max(0.0, min(1.0, 1.0 - (clampedDist / 1.0)))
                }
            } catch {
                computedVisualScore = 0.4
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isAnalyzing = false
                self.visualSimilarityScore = computedVisualScore
                self.applyScore(visualScore: computedVisualScore, headingScore: headingScore, turnCue: turnCue)
            }
        }
    }

    private func applyScore(visualScore: Double, headingScore: Double, turnCue: String) {
        let finalScore: Double
        if referenceHeading != nil {
            // 65% visual likeness + 35% heading accuracy
            finalScore = (visualScore * 0.65) + (headingScore * 0.35)
        } else {
            finalScore = visualScore
        }

        let percentage = max(0, min(100, Int(round(finalScore * 100))))
        self.matchPercentage = percentage
        self.isWellAligned = percentage >= 72

        if percentage >= 80 {
            self.alignmentGuidanceText = "Frames Aligned (\(percentage)%) · Ready to Retrace ✓"
        } else if percentage >= 60 {
            if !turnCue.isEmpty && abs(headingDeltaDegrees) > 10 {
                self.alignmentGuidanceText = "\(percentage)% Match · \(turnCue)"
            } else {
                self.alignmentGuidanceText = "\(percentage)% Match · Hold steady to lock in"
            }
        } else if percentage >= 35 {
            if !turnCue.isEmpty {
                self.alignmentGuidanceText = "\(percentage)% Match · \(turnCue)"
            } else {
                self.alignmentGuidanceText = "\(percentage)% Match · Match viewpoint in camera"
            }
        } else {
            if !turnCue.isEmpty {
                self.alignmentGuidanceText = "\(turnCue) · Look for \(referenceTitle)"
            } else {
                self.alignmentGuidanceText = "Point phone toward \(referenceTitle)"
            }
        }
    }
}
