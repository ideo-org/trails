//
//  SettingsViewModel.swift
//  MyApp
//
//  Manages user settings with local persistence (UserDefaults).
//  Optionally syncs to Firestore when Firebase is enabled.
//
//  Offline-first: Settings always work locally. Cloud sync is optional.
//

import Combine
import SwiftUI
import ARKit

class SettingsViewModel: ObservableObject {

    static let shared = SettingsViewModel()

    private var cancellables = Set<AnyCancellable>()
    private var debounceTimer: Timer?

    // MARK: - Scanner Settings (Trails Capture)

    @AppStorage("pointDensity") var pointDensity: PointDensity = .high
    @AppStorage("pointSize") var pointSize: PointSize = .med
    @AppStorage("scanRange") var scanRange: ScanRange = .med
    @AppStorage("scannerFlashEnabled") var scannerFlashEnabled: Bool = false
    @AppStorage("scansCount") var scansCount: Int = 0

    // MARK: - App Settings (Always stored locally via @AppStorage)

    @AppStorage("showOnboardingOnLaunch") var showOnboardingOnLaunch: Bool = false
    @AppStorage("appearance") var appearance: Appearance = .system

    // MARK: - Notification Preferences

    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = false
    @AppStorage("streakReminderEnabled") var streakReminderEnabled: Bool = true

    // MARK: - Date Tracking

    private var _appInstallDate: Date?
    private var _lastAppUsageDate: Date?

    var appInstallDate: Date? {
        get {
            if _appInstallDate == nil {
                if let timestamp = UserDefaults.standard.object(forKey: "appInstallDate") as? TimeInterval {
                    _appInstallDate = Date(timeIntervalSince1970: timestamp)
                }
            }
            return _appInstallDate
        }
        set {
            _appInstallDate = newValue
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "appInstallDate")
            } else {
                UserDefaults.standard.removeObject(forKey: "appInstallDate")
            }
        }
    }

    var lastAppUsageDate: Date? {
        get {
            if _lastAppUsageDate == nil {
                if let timestamp = UserDefaults.standard.object(forKey: "lastAppUsageDate") as? TimeInterval {
                    _lastAppUsageDate = Date(timeIntervalSince1970: timestamp)
                }
            }
            return _lastAppUsageDate
        }
        set {
            _lastAppUsageDate = newValue
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "lastAppUsageDate")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastAppUsageDate")
            }
        }
    }

    // MARK: - Initialization

    private init() {
        // Set install date if not already set (first launch)
        if appInstallDate == nil {
            appInstallDate = Date()
        }
    }

    // MARK: - Settings Persistence

    /// Flag settings for Firestore update with debouncing
    func flagSettingsForUpdate() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.persistSettings()
        }
    }

    /// Get all settings as a dictionary for Firestore
    func getSettings() -> [String: Any] {
        [
            "pointDensity": pointDensity.rawValue,
            "pointSize": pointSize.rawValue,
            "scanRange": scanRange.rawValue,
            "scannerFlashEnabled": scannerFlashEnabled,
            "scansCount": scansCount,
            "showOnboardingOnLaunch": showOnboardingOnLaunch,
            "appearance": appearance.rawValue,
            "notificationsEnabled": notificationsEnabled,
            "streakReminderEnabled": streakReminderEnabled,
            "appInstallDate": appInstallDate?.timeIntervalSince1970 as Any,
            "lastAppUsageDate": lastAppUsageDate?.timeIntervalSince1970 as Any
        ]
    }

    /// Save settings to Firestore
    private func persistSettings() {
        let settingsData = getSettings()
        FirestoreManager.shared.saveUserSettings(settingsData: settingsData)
    }

    /// Restore settings from Firestore data
    func restoreSettings(newSettings: [String: Any]) {
        pointDensity = PointDensity(rawValue: newSettings["pointDensity"] as? String ?? "") ?? .high
        pointSize = PointSize(rawValue: newSettings["pointSize"] as? String ?? "") ?? .med
        scanRange = ScanRange(rawValue: newSettings["scanRange"] as? String ?? "") ?? .med
        scannerFlashEnabled = newSettings["scannerFlashEnabled"] as? Bool ?? false
        scansCount = newSettings["scansCount"] as? Int ?? 0
        
        showOnboardingOnLaunch = newSettings["showOnboardingOnLaunch"] as? Bool ?? false
        appearance = Appearance(rawValue: newSettings["appearance"] as? String ?? "") ?? .system
        notificationsEnabled = newSettings["notificationsEnabled"] as? Bool ?? false
        streakReminderEnabled = newSettings["streakReminderEnabled"] as? Bool ?? true

        if let installTimestamp = newSettings["appInstallDate"] as? TimeInterval {
            appInstallDate = Date(timeIntervalSince1970: installTimestamp)
        }
        if let usageTimestamp = newSettings["lastAppUsageDate"] as? TimeInterval {
            lastAppUsageDate = Date(timeIntervalSince1970: usageTimestamp)
        }
    }

    // MARK: - App Usage Tracking

    /// Mark app usage for activity tracking
    func markAppUsage() {
        let now = Date()

        var shouldUpdateFirestore = false
        if let lastUsage = lastAppUsageDate {
            if !Calendar.current.isDate(lastUsage, inSameDayAs: now) {
                shouldUpdateFirestore = true
            }
        } else {
            shouldUpdateFirestore = true
        }

        lastAppUsageDate = now

        if shouldUpdateFirestore {
            // Log activity for backend streak calculation
            FirestoreManager.shared.logActivity(type: "app_open")
            flagSettingsForUpdate()
        }
    }

    /// Days since app was installed
    var daysSinceInstall: Int {
        guard let installDate = appInstallDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
    }

    /// Reset all scanner and app settings to Trails defaults
    func resetToTrailsDefaults() {
        pointDensity = .high
        pointSize = .med
        scanRange = .med
        scannerFlashEnabled = false
        // Note: cameraMixerValue defaults to 0.72 — purely visual, no engine coupling.
        flagSettingsForUpdate()
    }

}

// MARK: - Enums

enum Appearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
}


enum PointDensity: String, CaseIterable, Identifiable {
    case low = "Low"
    case med = "Med"
    case high = "High"
    case ultra = "Ultra"
    
    var id: String { rawValue }
    
    var densityFactor: Float {
        switch self {
        case .low: return 0.2
        case .med: return 0.4
        case .high: return 0.7
        case .ultra: return 1.0
        }
    }

    // SiteScape-style capture tiers:
    // medium ≈ 2x low, high ≈ 4x low, with ultra added in 2025.
    // The step sizes are intentionally explicit so each tier produces
    // a materially different point budget profile while scanning.
    var capturePixelStep: Int {
        switch self {
        case .low: return 3
        case .med: return 2
        case .high: return 1
        case .ultra: return 1
        }
    }
    
    var arConfidence: ARConfidenceLevel? {
        switch self {
        case .low: return nil
        case .med, .high, .ultra: return .low
        }
    }

    var liveVoxelSize: Float {
        switch self {
        case .low: return 0.010
        case .med: return 0.006
        case .high: return 0.004
        case .ultra: return 0.0025
        }
    }

    var minimumConfidenceRaw: UInt8 {
        guard let arConfidence else { return 0 }
        return UInt8(arConfidence.rawValue)
    }

    var summaryText: String {
        switch self {
        case .low:
            return "Largest coverage before the point budget fills. Best for broad area passes."
        case .med:
            return "Balanced SiteScape-style mode. Public research describes Medium as roughly 2x Low."
        case .high:
            return "Detail-first capture. Public research describes High as roughly 4x Low."
        case .ultra:
            return "Maps to SiteScape's newer ultra-high density tier for small-area, maximum-detail scans."
        }
    }
}

enum PointSize: String, CaseIterable, Identifiable {
    case low = "Low"
    case med = "Med"
    case high = "High"
    
    var id: String { rawValue }
    
    var value: Float {
        switch self {
        case .low: return 5.0
        case .med: return 10.0
        case .high: return 20.0
        }
    }

    var livePreviewPointSize: Float {
        switch self {
        case .low: return 2.2
        case .med: return 3.0
        case .high: return 4.2
        }
    }

    var liveSplatRadius: Float {
        switch self {
        case .low: return 5.0
        case .med: return 7.0
        case .high: return 9.0
        }
    }

    var summaryText: String {
        switch self {
        case .low:
            return "Small live points make edges and gaps easier to judge while scanning."
        case .med:
            return "Balanced live point size for most room-scale captures."
        case .high:
            return "Larger live points make sparse areas easier to see on screen."
        }
    }
}

enum ScanRange: String, CaseIterable, Identifiable {
    case close = "Close"
    case med = "Med"
    case full = "Full"
    
    var id: String { rawValue }
    
    var meters: Float {
        switch self {
        case .close: return 2.0
        case .med: return 3.5
        case .full: return 5.0
        }
    }

    var summaryText: String {
        switch self {
        case .close:
            return "Limits capture to nearby surfaces to reduce background intrusion."
        case .med:
            return "Balanced indoor working range, aligned to common 1-4 m SiteScape guidance."
        case .full:
            return "Keeps the capture ceiling at 5 m, matching published SiteScape-style LiDAR limits."
        }
    }
}
