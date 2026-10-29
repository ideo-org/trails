//
//  AppConfiguration.swift
//  Trails
//
//  Central configuration for the app. Toggle features here.
//

import Foundation

/// Central app configuration
/// Toggle features on/off based on your app's needs
enum AppConfiguration {
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing") ||
            ProcessInfo.processInfo.environment["TRAILS_UI_TESTING"] == "1"
    }

    // MARK: - Backend Configuration

    /// Enable Firebase backend (Auth, Firestore, Crashlytics) when a Firebase-backed feature is active.
    /// When disabled:
    /// - Auth uses local-only mode (no cloud sync)
    /// - Settings stored locally only (UserDefaults)
    /// - Streaks are local-only (no cloud calculation)
    /// - Crashlytics disabled
    ///
    /// When enabled:
    /// - Requires GoogleService-Info.plist
    /// - Requires Firebase project setup
    /// - Settings sync to Firestore
    /// - Streaks calculated by Cloud Functions
    static var useFirebase: Bool {
        !isUITesting && requiresFirebaseBackend
    }

    private static var requiresFirebaseBackend: Bool {
        enableAuth || enableScanCloudSync || enableStreaks
    }

    /// Enable RevenueCat for subscriptions.
    ///
    /// Keep disabled until a production API key and entitlement model are configured.
    static let useRevenueCat = false

    /// Enable TelemetryDeck analytics
    /// Privacy-preserving analytics - no PII collected.
    ///
    /// Keep disabled until a production app ID is configured.
    static let useTelemetryDeck = false

    // MARK: - Feature Flags

    /// Enable sign-in UI (Apple/Google Sign-In)
    ///
    /// This flag controls whether users see the sign-in option in Settings.
    /// It is independent of `useFirebase` to support progressive onboarding:
    ///
    /// **Recommended Strategy (Low-Friction Onboarding):**
    /// ```
    /// useFirebase = true, enableAuth = false
    /// ```
    /// - Anonymous Firebase account created automatically on first launch
    /// - Full Firestore sync works (streaks, settings, user data)
    /// - No sign-in UI - users enjoy the app without friction
    /// - Later, enable auth or prompt contextually: "Sign in to save your streak!"
    /// - When user signs in, anonymous account links to real account
    /// - All existing data (streaks, settings) preserved automatically
    ///
    /// **Full Auth from Start:**
    /// ```
    /// useFirebase = true, enableAuth = true
    /// ```
    /// - Sign-in option visible in Settings immediately
    /// - Good for apps where account is core to the experience
    ///
    /// **Local-Only Mode:**
    /// ```
    /// useFirebase = false, enableAuth = false
    /// ```
    /// - No Firebase dependency at all
    /// - Device-based identity for RevenueCat/analytics
    /// - All data stored locally (UserDefaults)
    ///
    /// Note: `enableAuth` requires `useFirebase = true` to function.
    /// If Firebase is disabled, sign-in UI is always hidden regardless of this flag.
    static let enableAuth = false

    /// Enable scan cloud sync UI and background asset upload.
    ///
    /// Keep this disabled until the roadmap in `docs/sync-roadmap.md` is complete.
    /// Other Firebase-backed product features can remain enabled while LiDAR scan
    /// captures stay local-first and export/share driven.
    static let enableScanCloudSync = false

    /// Enable streak tracking
    /// Works in both local mode (UserDefaults) and Firebase mode (Firestore + Cloud Functions)
    static let enableStreaks = false

    /// Enable the Library/CMS feature
    static let enableLibrary = false

    /// Enable widgets
    static let enableWidgets = false

    /// Enable app review prompts
    ///
    /// When enabled, the app will request an App Store review at strategic moments.
    /// Currently triggers when user achieves a 7-day streak (configurable via `appReviewStreakThreshold`).
    ///
    /// The system (SKStoreReviewController) ultimately decides whether to show the prompt.
    /// Apple limits how often the prompt appears, so calling requestReview() doesn't guarantee
    /// the dialog will show. This is by design to prevent review spam.
    ///
    /// Best practices followed:
    /// - Only prompts once per threshold achievement
    /// - Triggers at a moment of positive achievement
    /// - Doesn't interrupt critical user flows
    static let enableAppReview = false

    /// Streak threshold for triggering app review prompt
    /// User must achieve this streak count before review prompt is requested
    static let appReviewStreakThreshold = 7

    // MARK: - API Keys (Replace with your own)

    /// RevenueCat API Key
    /// Get yours at: https://app.revenuecat.com
    static let revenueCatAPIKey = "YOUR_REVENUECAT_API_KEY"

    /// TelemetryDeck App ID
    /// Get yours at: https://dashboard.telemetrydeck.com
    static let telemetryDeckAppID = "YOUR_TELEMETRYDECK_APP_ID"

    // MARK: - URLs (Replace with your own)

    /// Library content index URL (GitHub raw URL)
    /// Points at the Trails content repository
    static let libraryIndexURL = "https://raw.githubusercontent.com/20-20/trails/main/content/index.json"

    /// Terms of Service URL
    /// Replace with the production legal URL before App Store submission
    static let termsOfServiceURL = "https://github.com/20-20/trails/blob/main/content/terms.md"

    /// Privacy Policy URL
    /// Replace with the production legal URL before App Store submission
    static let privacyPolicyURL = "https://github.com/20-20/trails/blob/main/content/privacy.md"

    /// Tracker Host
    static var trackerHost: String {
        return Bundle.main.object(forInfoDictionaryKey: "TrackerHost") as? String ?? "vm.ideomind.org"
    }


    // MARK: - App Info

    /// App name displayed in UI
    static let appName = "Trails"

    /// Short marketing tagline used in onboarding and about surfaces
    static let appTagline = "RoomPlan 3D mapping & trails"

    /// Product description used in onboarding and about surfaces
    static let appDescription = "Scan rooms with RoomPlan LiDAR and map your footsteps in real time with Trails."

    /// App Store ID (for review prompts)
    static let appStoreID = "YOUR_APP_STORE_ID"
}

// MARK: - Convenience Accessors

extension AppConfiguration {
    /// Check if cloud features are available
    static var hasCloudFeatures: Bool {
        useFirebase
    }

    /// Check if RevenueCat is ready to receive SDK calls.
    static var isRevenueCatConfigured: Bool {
        useRevenueCat && hasConfiguredValue(revenueCatAPIKey)
    }

    /// Check if TelemetryDeck is ready to receive analytics events.
    static var isTelemetryDeckConfigured: Bool {
        useTelemetryDeck && hasConfiguredValue(telemetryDeckAppID)
    }

    /// Check if monetization is enabled
    static var hasMonetization: Bool {
        isRevenueCatConfigured
    }

    private static func hasConfiguredValue(_ value: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedValue.isEmpty && !trimmedValue.hasPrefix("YOUR_")
    }
}
