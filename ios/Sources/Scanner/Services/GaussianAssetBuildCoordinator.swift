import Foundation
import SwiftData

@MainActor
final class GaussianAssetBuildCoordinator {
    static let shared = GaussianAssetBuildCoordinator()

    private var activeScanIDs = Set<UUID>()
    private var deferredScanIDs = Set<UUID>()
    private nonisolated static let deferredBuildDelay: TimeInterval = 0
    private nonisolated static let busyRetryDelay: TimeInterval = 4.0

    private init() {}

    func isActive(scan: Scan) -> Bool {
        activeScanIDs.contains(scan.id)
    }

    func enqueueDeferred(
        scan: Scan,
        modelContext: ModelContext,
        force: Bool = false,
        delay: TimeInterval = deferredBuildDelay
    ) {
        guard !activeScanIDs.contains(scan.id),
              !deferredScanIDs.contains(scan.id),
              force || scan.gaussianStatus == .queued || scan.needsGaussianAssetRebuild,
              !scan.plyFileNames.isEmpty else {
            return
        }

        let scanID = scan.id
        deferredScanIDs.insert(scanID)
        let delayNanoseconds = UInt64(max(0, delay) * 1_000_000_000)

        Task { @MainActor [weak self, weak scan] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self else { return }
            self.deferredScanIDs.remove(scanID)
            guard let scan,
                  force || scan.gaussianStatus == .queued || scan.needsGaussianAssetRebuild,
                  !scan.plyFileNames.isEmpty else {
                return
            }

            if !self.activeScanIDs.isEmpty {
                self.enqueueDeferred(
                    scan: scan,
                    modelContext: modelContext,
                    force: force,
                    delay: Self.busyRetryDelay
                )
                return
            }

            self.enqueue(scan: scan, modelContext: modelContext, force: force)
        }
    }

    func enqueue(scan: Scan, modelContext: ModelContext, force: Bool = false) {
        guard !activeScanIDs.contains(scan.id) else { return }
        guard activeScanIDs.isEmpty else { return }
        guard force || scan.gaussianStatus != .ready || scan.needsGaussianAssetRebuild else { return }
        guard !scan.plyFileNames.isEmpty else { return }

        activeScanIDs.insert(scan.id)
        scan.gaussianStatus = .building
        scan.gaussianErrorMessage = nil
        scan.updatedAt = .now
        guard save(modelContext, action: "start PlayCanvas build") else {
            scan.gaussianStatus = .failed
            scan.gaussianErrorMessage = "Could not save PlayCanvas build start state."
            scan.updatedAt = .now
            _ = save(modelContext, action: "record PlayCanvas start failure")
            activeScanIDs.remove(scan.id)
            return
        }

        let scanID = scan.id
        let sourceFileNames = scan.plyFileNames
        let captureManifestFileName = scan.gaussianCaptureManifestFileName

        Task {
            defer {
                activeScanIDs.remove(scan.id)
            }

            let result = await Task.detached(priority: .utility) {
                try GaussianAssetBuilder().build(
                    scanID: scanID,
                    sourcePLYFileNames: sourceFileNames,
                    captureManifestFileName: captureManifestFileName
                )
            }.result

            switch result {
            case .success(let buildResult):
                scan.gaussianAssetManifestFileName = buildResult.manifestFileName
                scan.gaussianSplatFileName = buildResult.splatFileName
                scan.gaussianPLYFileName = buildResult.gaussianPLYFileName
                scan.gaussianSPZFileName = buildResult.spzFileName
                scan.gaussianSOGFileName = buildResult.sogFileName
                scan.gaussianErrorMessage = nil
                scan.gaussianStatus = .ready
            case .failure(let error):
                scan.gaussianAssetManifestFileName = nil
                scan.gaussianSplatFileName = nil
                scan.gaussianPLYFileName = nil
                scan.gaussianSPZFileName = nil
                scan.gaussianSOGFileName = nil
                scan.gaussianErrorMessage = error.localizedDescription
                scan.gaussianStatus = .failed
            }

            scan.updatedAt = .now
            if !save(modelContext, action: "finish PlayCanvas build") {
                scan.gaussianStatus = .failed
                scan.gaussianErrorMessage = "PlayCanvas viewer build finished, but saving its status failed."
                scan.updatedAt = .now
                _ = save(modelContext, action: "record PlayCanvas save failure")
            }
        }
    }

    private func save(_ modelContext: ModelContext, action: String) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            print("Failed to \(action): \(error)")
            return false
        }
    }
}
