import Foundation
import SwiftData
import Combine
import Network
import SwiftUI

#if canImport(Firebase)
import FirebaseAuth
import FirebaseFirestore
#endif

#if canImport(FirebaseStorage)
import FirebaseStorage
#endif

@MainActor
final class RemoteSyncManager: ObservableObject {
    static let shared = RemoteSyncManager()

    @Published private(set) var statusMessage = "Remote sync is unavailable"
    @Published private(set) var pendingCount = 0
    @Published private(set) var failedCount = 0
    @Published private(set) var isSyncing = false
    @Published private(set) var isConfigured = false
    @Published private(set) var isNetworkReachable = true
    @Published var transientNotification: SyncNotification?

    private var modelContext: ModelContext?
    private var authCancellable: AnyCancellable?
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "RemoteSyncManager.network")
    private var listenerToken: Any?
    private var scanSyncEnabled: Bool {
        AppConfiguration.useFirebase && AppConfiguration.enableScanCloudSync
    }

    #if canImport(Firebase)
    private var firestore: Firestore? {
        AppConfiguration.useFirebase ? Firestore.firestore() : nil
    }
    #endif

    #if canImport(FirebaseStorage)
    private var storage: Storage? {
        AppConfiguration.useFirebase ? Storage.storage() : nil
    }
    #endif

    private init() {
        isConfigured = scanSyncEnabled
        startNetworkMonitor()
        authCancellable = AuthManager.shared.$authState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.refreshConnectionState()
                    guard self.scanSyncEnabled else { return }
                    await self.refreshRemoteListener()
                    await self.syncNow()
                }
            }
    }

    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
        refreshConnectionState()
        Task {
            guard scanSyncEnabled else {
                removeRemoteListener()
                updateCounters()
                return
            }
            await refreshRemoteListener()
            await syncNow()
        }
    }

    func enqueue(_ scan: Scan) {
        guard scanSyncEnabled else {
            scan.updatedAt = .now
            scan.syncStatus = .localOnly
            scan.syncErrorMessage = nil
            saveContext()
            updateCounters()
            return
        }

        scan.updatedAt = .now
        scan.syncStatus = .pendingUpload
        scan.syncErrorMessage = nil
        saveContext()
        updateCounters()

        Task {
            await syncNow()
        }
    }

    func retry(_ scan: Scan) async {
        guard scanSyncEnabled else {
            scan.syncStatus = .localOnly
            scan.syncErrorMessage = nil
            saveContext()
            updateCounters()
            return
        }
        scan.syncStatus = .pendingUpload
        scan.syncErrorMessage = nil
        scan.updatedAt = .now
        saveContext()
        updateCounters()
        await syncNow()
    }

    func syncNow() async {
        guard !isSyncing else { return }
        guard scanSyncEnabled else {
            refreshConnectionState()
            updateCounters()
            return
        }

        guard isNetworkReachable else {
            statusMessage = pendingCount > 0 ? "Waiting for connection to resume sync" : "Offline — local captures stay on this device"
            updateCounters()
            return
        }

        #if canImport(Firebase)
        guard Auth.auth().currentUser != nil else {
            statusMessage = "Preparing secure cloud session"
            updateCounters()
            return
        }
        #endif

        refreshConnectionState()
        updateCounters()

        guard let modelContext else { return }

        isSyncing = true
        defer {
            isSyncing = false
            updateCounters()
        }

        let scans = fetchAllScans(in: modelContext)
        let candidates = scans.filter { scan in
            switch scan.syncStatus {
            case .localOnly:
                return false
            case .pendingUpload, .uploading, .failed:
                return true
            case .synced:
                if let lastSyncedAt = scan.lastSyncedAt {
                    return lastSyncedAt < scan.updatedAt
                }
                return true
            }
        }

        guard !candidates.isEmpty else {
            statusMessage = "Trails cloud library is up to date"
            return
        }

        for scan in candidates {
            await upload(scan)
        }
    }

    func delete(scan: Scan, modelContext: ModelContext) async -> Bool {
        if scanSyncEnabled, !scan.remoteDocumentID.isEmpty {
            if isNetworkReachable {
                do {
                    try await deleteRemoteAssets(for: scan)
                } catch {
                    postNotification(
                        title: "Cloud cleanup failed",
                        message: "Removed \(scan.title) from this device, but Trails could not remove its cloud copy right now.",
                        style: .warning
                    )
                }
            } else {
                postNotification(
                    title: "Removed locally",
                    message: "\(scan.title) was deleted on this device. Cloud cleanup will need a later connection.",
                    style: .warning
                )
            }
        }

        ScanFileStore.deleteLocalFiles(for: scan)
        modelContext.delete(scan)
        try? modelContext.save()
        updateCounters()
        return true
    }

    var shouldOfferLoginUpgrade: Bool {
        scanSyncEnabled && AuthManager.shared.canSignIn && AuthManager.shared.authState != .signedIn
    }

    var syncSummary: String {
        if failedCount > 0 {
            return "\(failedCount) capture\(failedCount == 1 ? "" : "s") need attention"
        }
        if pendingCount > 0 {
            return "\(pendingCount) capture\(pendingCount == 1 ? "" : "s") waiting to sync"
        }
        return statusMessage
    }

    private func refreshConnectionState() {
        isConfigured = scanSyncEnabled

        guard scanSyncEnabled else {
            statusMessage = "Scan cloud sync is on the roadmap"
            return
        }

        #if canImport(FirebaseStorage)
        statusMessage = isNetworkReachable ? "Trails will keep this library mirrored in the cloud" : "Offline — changes will queue on device"
        #else
        statusMessage = "Add Firebase Storage to enable Trails asset sync"
        #endif
    }

    private func updateCounters() {
        guard let modelContext else {
            pendingCount = 0
            failedCount = 0
            return
        }

        let scans = fetchAllScans(in: modelContext)
        pendingCount = scans.filter { [.pendingUpload, .uploading].contains($0.syncStatus) }.count
        failedCount = scans.filter { $0.syncStatus == .failed }.count
    }

    private func fetchAllScans(in modelContext: ModelContext) -> [Scan] {
        (try? modelContext.fetch(FetchDescriptor<Scan>(sortBy: [SortDescriptor(\Scan.timestamp, order: .reverse)]))) ?? []
    }

    private func fetchScan(id: UUID, in modelContext: ModelContext) -> Scan? {
        let descriptor = FetchDescriptor<Scan>(predicate: #Predicate<Scan> { scan in
            scan.id == id
        })
        return try? modelContext.fetch(descriptor).first
    }

    private func saveContext() {
        try? modelContext?.save()
    }

    private func startNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isNetworkReachable = path.status == .satisfied
                self?.refreshConnectionState()
                if path.status == .satisfied {
                    await self?.syncNow()
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    private func refreshRemoteListener() async {
        removeRemoteListener()

        guard scanSyncEnabled else { return }

        #if canImport(Firebase)
        guard let user = Auth.auth().currentUser, let firestore else { return }

        listenerToken = firestore.collection("users")
            .document(user.uid)
            .collection("scans")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    Task { @MainActor in
                        self.statusMessage = "Cloud listener paused: \(error.localizedDescription)"
                        self.postNotification(
                            title: "Cloud connection paused",
                            message: "Trails will keep working locally and retry remote updates when the connection settles.",
                            style: .warning
                        )
                    }
                    return
                }

                guard let snapshot else { return }

                Task { @MainActor in
                    await self.mergeRemoteSnapshot(snapshot.documents)
                }
            }
        #endif
    }

    private func removeRemoteListener() {
        #if canImport(Firebase)
        if let listener = listenerToken as? ListenerRegistration {
            listener.remove()
        }
        #endif
        listenerToken = nil
    }

    private func upload(_ scan: Scan) async {
        guard let modelContext else { return }
        guard scanSyncEnabled else {
            scan.syncStatus = .localOnly
            scan.syncErrorMessage = nil
            saveContext()
            updateCounters()
            return
        }

        scan.syncStatus = .uploading
        scan.syncErrorMessage = nil
        saveContext()
        updateCounters()

        do {
            let remotePayload = try await uploadAssets(for: scan)
            try await upsertRemoteMetadata(for: scan, payload: remotePayload)
            scan.remoteDocumentID = scan.id.uuidString
            scan.remoteStoragePath = remotePayload.plyStoragePath
            scan.remoteSubscanStoragePaths = remotePayload.subscanStoragePaths
            scan.remoteSnapshotStoragePaths = remotePayload.snapshotStoragePaths
            scan.lastSyncedAt = .now
            scan.syncStatus = .synced
            scan.syncErrorMessage = nil
            saveContext()
            statusMessage = "Synced \(scan.title)"
        } catch {
            scan.syncStatus = .failed
            scan.syncErrorMessage = error.localizedDescription
            saveContext()
            statusMessage = "Sync needs attention"
            postNotification(
                title: "Sync failed",
                message: "Trails saved \(scan.title) locally, but remote sync needs another try.",
                style: .error
            )
        }

        _ = modelContext
    }

    private func mergeRemoteSnapshot(_ documents: [Any]) async {
        guard let modelContext else { return }
        guard scanSyncEnabled else { return }

        #if canImport(Firebase)
        for case let document as QueryDocumentSnapshot in documents {
            guard let remote = RemoteScanRecord(document: document) else { continue }

            let localScan = fetchScan(id: remote.id, in: modelContext)
            let needsMerge = localScan == nil || localScan?.syncStatus == .synced || localScan?.lastSyncedAt == nil
            guard needsMerge else { continue }

            let scan = localScan ?? Scan(
                id: remote.id,
                title: remote.title,
                timestamp: remote.timestamp,
                updatedAt: remote.updatedAt,
                pointCount: remote.pointCount,
                fileSize: remote.fileSize,
                latitude: remote.latitude,
                longitude: remote.longitude,
                thumbnailData: nil,
                plyFileName: remote.plyFileName,
                subscanMetadataJSON: remote.subscanMetadataJSON,
                snapFileNames: remote.snapFileNames,
                snapshotMetadataJSON: remote.snapshotMetadataJSON,
                syncStatusRaw: ScanSyncStatus.synced.rawValue,
                remoteDocumentID: remote.id.uuidString,
                remoteStoragePath: remote.plyStoragePath,
                remoteSubscanStoragePaths: remote.subscanStoragePaths,
                remoteSnapshotStoragePaths: remote.snapshotStoragePaths,
                lastSyncedAt: remote.updatedAt,
                syncErrorMessage: nil
            )

            scan.title = remote.title
            scan.timestamp = remote.timestamp
            scan.updatedAt = remote.updatedAt
            scan.pointCount = remote.pointCount
            scan.fileSize = remote.fileSize
            scan.latitude = remote.latitude
            scan.longitude = remote.longitude
            scan.plyFileName = remote.plyFileName
            scan.subscanMetadataJSON = remote.subscanMetadataJSON
            scan.snapFileNames = remote.snapFileNames
            scan.snapshotMetadataJSON = remote.snapshotMetadataJSON
            scan.remoteDocumentID = remote.id.uuidString
            scan.remoteStoragePath = remote.plyStoragePath
            scan.remoteSubscanStoragePaths = remote.subscanStoragePaths
            scan.remoteSnapshotStoragePaths = remote.snapshotStoragePaths
            scan.lastSyncedAt = remote.updatedAt
            scan.syncStatus = .synced
            scan.syncErrorMessage = nil

            if localScan == nil {
                modelContext.insert(scan)
            }

            do {
                try await downloadAssetsIfNeeded(remote: remote)
                if scan.thumbnailData == nil, let firstSnap = scan.snapFileNames.first {
                    scan.thumbnailData = ScanFileStore.loadImageData(fileName: firstSnap)
                }
                saveContext()
            } catch {
                scan.syncStatus = .failed
                scan.syncErrorMessage = error.localizedDescription
                saveContext()
                postNotification(
                    title: "Download incomplete",
                    message: "Trails fetched metadata for \(scan.title), but some remote assets still need another try.",
                    style: .warning
                )
            }
        }
        #endif

        updateCounters()
    }

    private func uploadAssets(for scan: Scan) async throws -> RemoteAssetPayload {
        #if canImport(Firebase) && canImport(FirebaseStorage)
        guard let user = Auth.auth().currentUser else {
            throw SyncError.notAuthenticated
        }
        guard let storage else {
            throw SyncError.storageUnavailable
        }

        let basePath = "users/\(user.uid)/scans/\(scan.id.uuidString)"
        let plyStoragePath = "\(basePath)/\(scan.plyFileName)"
        try await uploadFile(localURL: ScanFileStore.fileURL(fileName: scan.plyFileName), storagePath: plyStoragePath, contentType: "application/octet-stream", storage: storage)

        var subscanStoragePaths: [String] = []
        for part in scan.scanParts {
            let subscanStoragePath = "\(basePath)/subscans/\(part.fileName)"
            try await uploadFile(localURL: ScanFileStore.fileURL(fileName: part.fileName), storagePath: subscanStoragePath, contentType: "application/octet-stream", storage: storage)
            subscanStoragePaths.append(subscanStoragePath)
        }

        var snapshotPaths: [String] = []
        for snapFileName in scan.snapFileNames {
            let snapStoragePath = "\(basePath)/snaps/\(snapFileName)"
            try await uploadFile(localURL: ScanFileStore.fileURL(fileName: snapFileName), storagePath: snapStoragePath, contentType: "image/jpeg", storage: storage)
            snapshotPaths.append(snapStoragePath)
        }

        return RemoteAssetPayload(
            plyStoragePath: plyStoragePath,
            subscanStoragePaths: subscanStoragePaths,
            snapshotStoragePaths: snapshotPaths
        )
        #else
        throw SyncError.storageUnavailable
        #endif
    }

    private func upsertRemoteMetadata(for scan: Scan, payload: RemoteAssetPayload) async throws {
        #if canImport(Firebase)
        guard let user = Auth.auth().currentUser else {
            throw SyncError.notAuthenticated
        }
        guard let firestore else {
            throw SyncError.firestoreUnavailable
        }

        let docRef = firestore.collection("users").document(user.uid).collection("scans").document(scan.id.uuidString)
        let data: [String: Any] = [
            "id": scan.id.uuidString,
            "title": scan.title,
            "timestamp": Timestamp(date: scan.timestamp),
            "updatedAt": Timestamp(date: scan.updatedAt),
            "pointCount": scan.pointCount,
            "fileSize": scan.fileSize,
            "latitude": scan.latitude as Any,
            "longitude": scan.longitude as Any,
            "plyFileName": scan.plyFileName,
            "subscanMetadataJSON": scan.subscanMetadataJSON as Any,
            "snapFileNames": scan.snapFileNames,
            "snapshotMetadataJSON": scan.snapshotMetadataJSON as Any,
            "plyStoragePath": payload.plyStoragePath,
            "subscanStoragePaths": payload.subscanStoragePaths,
            "snapshotStoragePaths": payload.snapshotStoragePaths,
            "ownerUid": user.uid
        ]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            docRef.setData(data, merge: true) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
        #else
        throw SyncError.firestoreUnavailable
        #endif
    }

    private func deleteRemoteAssets(for scan: Scan) async throws {
        #if canImport(Firebase) && canImport(FirebaseStorage)
        guard let user = Auth.auth().currentUser else {
            throw SyncError.notAuthenticated
        }
        guard let firestore else {
            throw SyncError.firestoreUnavailable
        }
        guard let storage else {
            throw SyncError.storageUnavailable
        }

        let storagePaths = ([scan.remoteStoragePath] + scan.remoteSubscanStoragePaths + scan.remoteSnapshotStoragePaths).filter { !$0.isEmpty }
        for storagePath in storagePaths {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                storage.reference(withPath: storagePath).delete { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            firestore.collection("users").document(user.uid).collection("scans").document(scan.id.uuidString).delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
        #else
        throw SyncError.storageUnavailable
        #endif
    }

    private func downloadAssetsIfNeeded(remote: RemoteScanRecord) async throws {
        #if canImport(FirebaseStorage)
        guard let storage else {
            throw SyncError.storageUnavailable
        }

        let plyURL = ScanFileStore.fileURL(fileName: remote.plyFileName)
        if !FileManager.default.fileExists(atPath: plyURL.path) {
            try await downloadFile(storagePath: remote.plyStoragePath, localURL: plyURL, storage: storage)
        }

        for (index, part) in remote.scanParts.enumerated() {
            let partURL = ScanFileStore.fileURL(fileName: part.fileName)
            if !FileManager.default.fileExists(atPath: partURL.path), index < remote.subscanStoragePaths.count {
                try await downloadFile(storagePath: remote.subscanStoragePaths[index], localURL: partURL, storage: storage)
            }
        }

        for (index, fileName) in remote.snapFileNames.enumerated() {
            let snapURL = ScanFileStore.fileURL(fileName: fileName)
            if !FileManager.default.fileExists(atPath: snapURL.path), index < remote.snapshotStoragePaths.count {
                try await downloadFile(storagePath: remote.snapshotStoragePaths[index], localURL: snapURL, storage: storage)
            }
        }
        #endif
    }

    #if canImport(FirebaseStorage)
    private func uploadFile(localURL: URL, storagePath: String, contentType: String, storage: Storage) async throws {
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        let reference = storage.reference(withPath: storagePath)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = reference.putFile(from: localURL, metadata: metadata) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
            task.observe(.progress) { [weak self] snapshot in
                guard let progress = snapshot.progress, progress.totalUnitCount > 0 else { return }
                Task { @MainActor in
                    self?.statusMessage = "Uploading \(progress.completedUnitCount.formatted()) of \(progress.totalUnitCount.formatted()) bytes"
                }
            }
        }
    }

    private func downloadFile(storagePath: String, localURL: URL, storage: Storage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            storage.reference(withPath: storagePath).write(toFile: localURL) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
    #endif

    func dismissNotification() {
        transientNotification = nil
    }

    private func postNotification(title: String, message: String, style: SyncNotification.Style) {
        guard scanSyncEnabled else { return }
        transientNotification = SyncNotification(title: title, message: message, style: style)
    }
}

private struct RemoteAssetPayload {
    let plyStoragePath: String
    let subscanStoragePaths: [String]
    let snapshotStoragePaths: [String]
}

#if canImport(Firebase)
private struct RemoteScanRecord {
    let id: UUID
    let title: String
    let timestamp: Date
    let updatedAt: Date
    let pointCount: Int
    let fileSize: Int64
    let latitude: Double?
    let longitude: Double?
    let plyFileName: String
    let subscanMetadataJSON: String?
    let snapFileNames: [String]
    let snapshotMetadataJSON: String?
    let plyStoragePath: String
    let subscanStoragePaths: [String]
    let snapshotStoragePaths: [String]

    var scanParts: [ScanPart] {
        let decoded = ScanPart.decode(subscanMetadataJSON)
        guard decoded.isEmpty else { return decoded }

        return [
            ScanPart(index: 1, fileName: plyFileName, pointCount: pointCount, fileSize: fileSize)
        ]
    }

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let id = UUID(uuidString: document.documentID),
              let title = data["title"] as? String,
              let timestamp = data["timestamp"] as? Timestamp,
              let updatedAt = data["updatedAt"] as? Timestamp,
              let pointCount = data["pointCount"] as? Int,
              let plyFileName = data["plyFileName"] as? String,
              let plyStoragePath = data["plyStoragePath"] as? String else {
            return nil
        }

        self.id = id
        self.title = title
        self.timestamp = timestamp.dateValue()
        self.updatedAt = updatedAt.dateValue()
        self.pointCount = pointCount
        self.fileSize = (data["fileSize"] as? NSNumber)?.int64Value ?? 0
        self.latitude = data["latitude"] as? Double
        self.longitude = data["longitude"] as? Double
        self.plyFileName = plyFileName
        self.subscanMetadataJSON = data["subscanMetadataJSON"] as? String
        self.snapFileNames = data["snapFileNames"] as? [String] ?? []
        self.snapshotMetadataJSON = data["snapshotMetadataJSON"] as? String
        self.plyStoragePath = plyStoragePath
        self.subscanStoragePaths = data["subscanStoragePaths"] as? [String] ?? []
        self.snapshotStoragePaths = data["snapshotStoragePaths"] as? [String] ?? []
    }
}
#endif

enum SyncError: LocalizedError {
    case notAuthenticated
    case firestoreUnavailable
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Trails needs a Firebase session before it can sync this capture."
        case .firestoreUnavailable:
            return "Firestore is unavailable in this build."
        case .storageUnavailable:
            return "Firebase Storage is unavailable in this build."
        }
    }
}

struct SyncNotification: Identifiable, Equatable {
    enum Style {
        case warning
        case error

        var tint: Color {
            switch self {
            case .warning:
                return .orange
            case .error:
                return .red
            }
        }

        var iconName: String {
            switch self {
            case .warning:
                return "exclamationmark.triangle.fill"
            case .error:
                return "wifi.exclamationmark"
            }
        }
    }

    let id = UUID()
    let title: String
    let message: String
    let style: Style
}
