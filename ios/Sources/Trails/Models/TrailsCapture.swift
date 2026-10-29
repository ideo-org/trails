import Foundation
import SwiftData
import CoreLocation

@Model
final class TrailsCapture {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var name: String
    var latitude: Double?
    var longitude: Double?
    var durationSeconds: Double
    var pointCount: Int
    var fileSizeBytes: Int64
    var pointCloudPath: String
    var snapshotsJSON: String
    /// JPEG data of the Metal-rendered 3-D point cloud scene captured at save time.
    var thumbnailData: Data?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        name: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        durationSeconds: Double,
        pointCount: Int,
        fileSizeBytes: Int64,
        pointCloudPath: String,
        snapshotPaths: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.durationSeconds = durationSeconds
        self.pointCount = pointCount
        self.fileSizeBytes = fileSizeBytes
        self.pointCloudPath = pointCloudPath
        self.snapshotsJSON = TrailsCapture.encode(snapshotPaths)
        self.thumbnailData = nil
    }

    var snapshotPaths: [String] {
        get {
            TrailsCapture.decode(snapshotsJSON)
        }
        set {
            snapshotsJSON = TrailsCapture.encode(newValue)
        }
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var formattedDuration: String {
        TrailsTimeFormatter.minuteSecond(durationSeconds)
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    private static func encode(_ snapshotPaths: [String]) -> String {
        guard let data = try? JSONEncoder().encode(snapshotPaths),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private static func decode(_ snapshotsJSON: String) -> [String] {
        guard let data = snapshotsJSON.data(using: .utf8),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return paths
    }
}

enum TrailsTimeFormatter {
    static func minuteSecond(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
