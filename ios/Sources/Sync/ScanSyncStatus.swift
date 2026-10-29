import SwiftUI

enum ScanSyncStatus: String, Codable, CaseIterable {
    case localOnly
    case pendingUpload
    case uploading
    case synced
    case failed

    var title: String {
        switch self {
        case .localOnly:
            return "Local"
        case .pendingUpload:
            return "Queued"
        case .uploading:
            return "Syncing"
        case .synced:
            return "Synced"
        case .failed:
            return "Failed"
        }
    }

    var iconName: String {
        switch self {
        case .localOnly:
            return "internaldrive.fill"
        case .pendingUpload:
            return "clock.arrow.circlepath"
        case .uploading:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .synced:
            return "checkmark.icloud.fill"
        case .failed:
            return "exclamationmark.icloud.fill"
        }
    }

    var tint: Color {
        switch self {
        case .localOnly:
            return .secondary
        case .pendingUpload:
            return .orange
        case .uploading:
            return AppColors.primary
        case .synced:
            return .green
        case .failed:
            return .red
        }
    }
}
