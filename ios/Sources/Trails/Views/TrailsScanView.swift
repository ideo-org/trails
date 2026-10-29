import SwiftUI
import SwiftData
import ARKit
import CoreLocation
import Combine

struct TrailsScanView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var session = TrailsScannerSession()
    @StateObject private var locationManager = TrailsLocationManager()
    @State private var hasSavedCapture = false

    var body: some View {
        ZStack {
            if session.isSupported {
                TrailsScannerContainerView(session: session) { result in
                    saveCapture(result)
                }
                .ignoresSafeArea()
            } else {
                unsupportedView
            }

            overlayChrome
        }
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .navigationBarHidden(true)
        .task {
            locationManager.requestAccessIfNeeded()
            Analytics.trackScreenView("TrailsScanView")
        }
    }

    private var unsupportedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.warning)

            Text("LiDAR-capable Pro device required")
                .font(AppFonts.title2)
                .foregroundStyle(AppColors.textPrimary)

            Text("Trails is designed for iPhone Pro hardware with LiDAR. This device can browse the library, but native scanning is unavailable here.")
                .font(AppFonts.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var overlayChrome: some View {
        VStack(spacing: 0) {
            topTelemetry
                .padding(.horizontal, 16)
                .padding(.top, 12)

            Spacer()

            bottomControls
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var topTelemetry: some View {
        HStack(spacing: 12) {
            telemetryPill(title: "Points", value: session.pointCount.formatted())
            telemetryPill(title: "Clock", value: session.elapsedLabel)
            telemetryPill(title: "GPS", value: locationManager.statusDescription)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    session.takeSnapshot()
                } label: {
                    Label("Snap", systemImage: "camera.fill")
                }
                .secondaryStyle()
                .disabled(!session.isReadyForSnapshots)

                Button {
                    if session.isScanning {
                        session.stop()
                    } else {
                        session.start()
                    }
                } label: {
                    Label(session.isScanning ? "Stop Scan" : "Start Scan", systemImage: session.isScanning ? "stop.fill" : "record.circle.fill")
                }
                .primaryStyle(isEnabled: session.isSupported)
                .disabled(!session.isSupported)
            }

            HStack(spacing: 12) {
                statusCard(title: "Status", value: session.statusText)
                statusCard(title: "Snaps", value: session.snapshots.count.formatted())
                statusCard(title: "Last Scan", value: hasSavedCapture ? "Saved" : "None")
            }
        }
    }

    private func telemetryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(AppFonts.caption2)
                .foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(AppFonts.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppColors.glass)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func statusCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppFonts.caption)
                .foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(AppFonts.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.glass)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func saveCapture(_ result: TrailsScannerResult) {
        let location = locationManager.currentLocation?.coordinate
        let capture = TrailsCapture(
            name: captureName(for: location),
            latitude: location?.latitude,
            longitude: location?.longitude,
            durationSeconds: result.durationSeconds,
            pointCount: result.pointCount,
            fileSizeBytes: result.fileSizeBytes,
            pointCloudPath: result.filePath,
            snapshotPaths: session.snapshots
        )

        // Attach the Metal-rendered 3-D scene thumbnail captured just before export
        capture.thumbnailData = session.controller?.pendingSceneThumbnail
            .flatMap { $0.jpegData(compressionQuality: 0.82) }

        modelContext.insert(capture)
        try? modelContext.save()
        hasSavedCapture = true
        session.finishSaving()
        Analytics.track(event: "scan.saved", parameters: [
            "points": result.pointCount,
            "duration": result.durationSeconds,
            "snaps": session.snapshots.count
        ])
    }

    private func captureName(for coordinate: CLLocationCoordinate2D?) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let base = formatter.string(from: .now)
        if let coordinate {
            return "Trails Capture · \(coordinate.latitude.formatted(.number.precision(.fractionLength(3)))), \(coordinate.longitude.formatted(.number.precision(.fractionLength(3))))"
        }
        return "Trails Capture · \(base)"
    }
}

@MainActor
final class TrailsScannerSession: ObservableObject {
    @Published var pointCount = 0
    @Published var isScanning = false
    @Published var statusText = "Ready to capture"
    @Published var snapshots: [String] = []
    @Published var startedAt: Date?

    weak var controller: LiDARPointScannerViewController?

    let isSupported = ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)

    var isReadyForSnapshots: Bool {
        controller != nil
    }

    var elapsedLabel: String {
        guard let startedAt else { return "00:00" }
        let elapsed = Date().timeIntervalSince(startedAt)
        return TrailsTimeFormatter.minuteSecond(elapsed)
    }

    func attach(_ controller: LiDARPointScannerViewController) {
        self.controller = controller
    }

    func start() {
        guard isSupported else { return }
        pointCount = 0
        snapshots = []
        startedAt = Date()
        statusText = "Painting point cloud"
        isScanning = true
        controller?.applyCurrentScanSettings()
        controller?.startAccumulatingPoints()
    }

    func stop() {
        statusText = "Finalising local PLY"
        controller?.stopScan()
    }

    func cancelled() {
        isScanning = false
        startedAt = nil
        statusText = "Capture cancelled"
    }

    func finishSaving() {
        isScanning = false
        startedAt = nil
        statusText = "Saved locally"
    }

    func takeSnapshot() {
        controller?.takePhoto { [weak self] path in
            guard let self, let path else { return }
            Task { @MainActor in
                self.snapshots.append(path)
                self.statusText = "Snap captured"
            }
        }
    }
}

struct TrailsScannerResult {
    let filePath: String
    let pointCount: Int
    let durationSeconds: Double
    let fileSizeBytes: Int64
}

private struct TrailsScannerContainerView: UIViewControllerRepresentable {
    @ObservedObject var session: TrailsScannerSession
    let onFinished: (TrailsScannerResult) -> Void

    func makeUIViewController(context: Context) -> LiDARPointScannerViewController {
        let controller = LiDARPointScannerViewController()
        controller.onProgress = { current, _ in
            Task { @MainActor in
                session.pointCount = current
            }
        }
        controller.onScanFinished = { filePath, vertexCount, duration, fileSize in
            Task { @MainActor in
                onFinished(
                    TrailsScannerResult(
                        filePath: filePath,
                        pointCount: vertexCount,
                        durationSeconds: duration,
                        fileSizeBytes: fileSize
                    )
                )
            }
        }
        controller.onScanCancelled = {
            Task { @MainActor in
                session.cancelled()
            }
        }
        session.attach(controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: LiDARPointScannerViewController, context: Context) {
        uiViewController.applyCurrentScanSettings()
        session.attach(uiViewController)
    }
}
