import Foundation
import simd

struct ScanSnapshotCluster: Identifiable {
    let snapshots: [ScanSnapshot]
    let position: SIMD3<Float>

    init(snapshots: [ScanSnapshot], position: SIMD3<Float>? = nil) {
        precondition(!snapshots.isEmpty, "ScanSnapshotCluster requires at least one snapshot.")

        let orderedSnapshots = snapshots.sorted {
            if $0.capturedAt == $1.capturedAt {
                return $0.fileName < $1.fileName
            }
            return $0.capturedAt < $1.capturedAt
        }

        self.snapshots = orderedSnapshots
        self.position = position ?? Self.centroid(for: orderedSnapshots)
    }

    var id: String {
        snapshots.map(\.fileName).joined(separator: "|")
    }

    var count: Int {
        snapshots.count
    }

    var primarySnapshot: ScanSnapshot {
        snapshots[snapshots.count - 1]
    }

    private static func centroid(for snapshots: [ScanSnapshot]) -> SIMD3<Float> {
        guard !snapshots.isEmpty else { return SIMD3<Float>(repeating: 0) }

        let sum = snapshots.reduce(into: SIMD3<Float>(repeating: 0)) { partialResult, snapshot in
            partialResult += snapshot.position
        }

        return sum / Float(snapshots.count)
    }
}

enum ScanSnapshotClustering {
    static let defaultRadius: Float = 0.45

    static func clusters(
        for snapshots: [ScanSnapshot],
        radius: Float = defaultRadius
    ) -> [ScanSnapshotCluster] {
        guard !snapshots.isEmpty else { return [] }

        var clusterMembers: [[ScanSnapshot]] = []
        var centroids: [SIMD3<Float>] = []

        let orderedSnapshots = snapshots.sorted {
            if $0.capturedAt == $1.capturedAt {
                return $0.fileName < $1.fileName
            }
            return $0.capturedAt < $1.capturedAt
        }

        for snapshot in orderedSnapshots {
            if let clusterIndex = nearestClusterIndex(
                for: snapshot,
                centroids: centroids,
                radius: radius
            ) {
                clusterMembers[clusterIndex].append(snapshot)
                centroids[clusterIndex] = centroid(for: clusterMembers[clusterIndex])
            } else {
                clusterMembers.append([snapshot])
                centroids.append(snapshot.position)
            }
        }

        return clusterMembers.enumerated().map { index, members in
            ScanSnapshotCluster(snapshots: members, position: centroids[index])
        }
    }

    private static func nearestClusterIndex(
        for snapshot: ScanSnapshot,
        centroids: [SIMD3<Float>],
        radius: Float
    ) -> Int? {
        var bestMatch: (index: Int, distance: Float)?

        for (index, centroid) in centroids.enumerated() {
            let distance = simd_distance(snapshot.position, centroid)
            guard distance <= radius else { continue }

            if let currentBest = bestMatch {
                if distance < currentBest.distance {
                    bestMatch = (index, distance)
                }
            } else {
                bestMatch = (index, distance)
            }
        }

        return bestMatch?.index
    }

    private static func centroid(for snapshots: [ScanSnapshot]) -> SIMD3<Float> {
        let sum = snapshots.reduce(into: SIMD3<Float>(repeating: 0)) { partialResult, snapshot in
            partialResult += snapshot.position
        }
        return sum / Float(snapshots.count)
    }
}
