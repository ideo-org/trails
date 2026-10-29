//
//  ScanSnapshot.swift
//  Trails
//
//  Persisted snapshot metadata for positioned scan photos.
//

import Foundation
import simd

struct ScanSnapshot: Codable, Hashable, Identifiable {
    let fileName: String
    let positionX: Float
    let positionY: Float
    let positionZ: Float
    let capturedAt: Date

    var id: String { fileName }

    var position: SIMD3<Float> {
        SIMD3(positionX, positionY, positionZ)
    }

    init(fileName: String, position: SIMD3<Float>, capturedAt: Date = .now) {
        self.fileName = fileName
        self.positionX = position.x
        self.positionY = position.y
        self.positionZ = position.z
        self.capturedAt = capturedAt
    }

    func withPosition(_ newPosition: SIMD3<Float>) -> ScanSnapshot {
        ScanSnapshot(fileName: fileName, position: newPosition, capturedAt: capturedAt)
    }

    static func encode(_ snapshots: [ScanSnapshot]) -> String? {
        guard !snapshots.isEmpty,
              let data = try? JSONEncoder().encode(snapshots) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ value: String?) -> [ScanSnapshot] {
        guard let value,
              let data = value.data(using: .utf8),
              let snapshots = try? JSONDecoder().decode([ScanSnapshot].self, from: data) else {
            return []
        }
        return snapshots
    }
}
