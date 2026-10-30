//
//  TrailsApp.swift
//  Trails
//
//  Main app entry point with conditional Firebase, RevenueCat, and TelemetryDeck initialization.
//

import SwiftUI
import SwiftData

#if canImport(GoogleMaps)
import GoogleMaps
#endif

#if canImport(RevenueCat)
import RevenueCat
#endif

#if canImport(TelemetryDeck)
import TelemetryDeck
#endif

#if canImport(Firebase)
import Firebase
import FirebaseCrashlytics
#endif

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct TrailsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var authManager: AuthManager
    @StateObject private var remoteSyncManager: RemoteSyncManager

    init() {
        #if canImport(Firebase)
        if AppConfiguration.useFirebase && FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        #endif

        _authManager = StateObject(wrappedValue: AuthManager.shared)
        _remoteSyncManager = StateObject(wrappedValue: RemoteSyncManager.shared)

        // Ensure the Application Support directory exists to suppress scary SwiftData first-launch logs
        if let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        }

        // Skip initialization in SwiftUI previews
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else {
            return
        }

        #if canImport(GoogleMaps)
        GMSServices.provideAPIKey("AIzaSyAWhxNz0G35PyUeJfvO6qrn6nybnZt3174")
        #endif

        // Initialize auth (Firebase or local depending on config)
        if AppConfiguration.useFirebase {
            Task { @MainActor in
                await AuthManager.shared.handleInitialAuthentication()
            }
        }

        // Configure RevenueCat (if enabled)
        if AppConfiguration.isRevenueCatConfigured {
            #if canImport(RevenueCat)
            Purchases.logLevel = .info
            Purchases.configure(withAPIKey: AppConfiguration.revenueCatAPIKey)
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .modifier(DarkModeViewModifier())
                .environmentObject(authManager)
                .environmentObject(remoteSyncManager)
                .onOpenURL { url in
                    #if canImport(GoogleSignIn)
                    _ = GIDSignIn.sharedInstance.handle(url)
                    #endif
                }
        }
        .modelContainer(for: [Scan.self])
    }
}

private struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var remoteSyncManager: RemoteSyncManager
    @AppStorage("hasCompletedTrailsOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        MainTabView()
            .task {
                remoteSyncManager.attach(modelContext: modelContext)
            }
            .fullScreenCover(isPresented: onboardingPresentation) {
                OnboardingView(isOnboardingDone: $hasCompletedOnboarding)
            }
    }

    private var onboardingPresentation: Binding<Bool> {
        Binding {
            !AppConfiguration.isUITesting && !hasCompletedOnboarding
        } set: { isPresented in
            if !isPresented {
                hasCompletedOnboarding = true
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Skip initialization in SwiftUI previews
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else {
            return true
        }

        // Initialize TelemetryDeck (if enabled)
        if AppConfiguration.isTelemetryDeckConfigured {
            #if canImport(TelemetryDeck)
            let config = TelemetryDeck.Config(appID: AppConfiguration.telemetryDeckAppID)
            TelemetryDeck.initialize(config: config)
            TelemetryDeck.signal("app_launch", parameters: ["launch_type": "cold"])
            #endif
        }

        // Initialize Firebase (if enabled)
        if AppConfiguration.useFirebase {
            #if canImport(Firebase)
            if FirebaseApp.app() == nil {
                FirebaseApp.configure()
            }

            #if DEBUG
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
            #else
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
            let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
            Crashlytics.crashlytics().setCustomValue(deviceId, forKey: "device_id")
            Crashlytics.crashlytics().log("App launched successfully")
            #endif
            #endif
        }

        // Setup notification handling
        UNUserNotificationCenter.current().delegate = self

        return true
    }

    // MARK: - Notification Handling

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let notificationIdentifier = response.notification.request.identifier

        Analytics.track(event: "notification.opened", parameters: ["type": notificationIdentifier])

        // Handle specific notification types here
        // Example:
        // let userInfo = response.notification.request.content.userInfo
        // if let action = userInfo["action"] as? String { ... }

        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    // MARK: - URL Handling (Google Sign-In)

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        #if canImport(GoogleSignIn)
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }
        #endif
        return false
    }
}
