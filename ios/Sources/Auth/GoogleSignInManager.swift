//
//  GoogleSignInManager.swift
//  Trails
//
//  Handles Google Sign-In flow with configuration fallback and session restore.
//

#if canImport(GoogleSignIn)
import GoogleSignIn
import UIKit
#if canImport(FirebaseCore)
import FirebaseCore
#endif

class GoogleSignInManager {

    static let shared = GoogleSignInManager()

    private init() {}

    /// Ensure GoogleSignIn is properly configured with client ID
    func ensureConfiguration() {
        if GIDSignIn.sharedInstance.configuration == nil {
            #if canImport(FirebaseCore)
            if let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty {
                GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
                return
            }
            #endif

            if let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String, !clientID.isEmpty {
                GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
                return
            }

            // Fallback from GoogleService-Info.plist
            if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
               let plist = NSDictionary(contentsOfFile: path),
               let clientID = plist["CLIENT_ID"] as? String, !clientID.isEmpty {
                GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            }
        }
    }

    /// Sign in with Google, restoring previous session if available
    @MainActor
    func signInWithGoogle() async throws -> GIDGoogleUser? {
        ensureConfiguration()

        // Check for previous sign-in
        if GIDSignIn.sharedInstance.hasPreviousSignIn() {
            do {
                try await GIDSignIn.sharedInstance.restorePreviousSignIn()
                return try await GIDSignIn.sharedInstance.currentUser?.refreshTokensIfNeeded()
            } catch {
                // Previous sign in was revoked, initiate new sign-in flow
                return try await googleSignInFlow()
            }
        } else {
            return try await googleSignInFlow()
        }
    }

    /// Present the Google Sign-In flow using the topmost presented view controller
    @MainActor
    private func googleSignInFlow() async throws -> GIDGoogleUser? {
        ensureConfiguration()

        guard GIDSignIn.sharedInstance.configuration != nil else {
            throw NSError(
                domain: "GoogleSignInManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Google Sign-In is not configured yet for com.logos.trails in Firebase. You can continue using your Username!"]
            )
        }

        guard let topViewController = topPresentedViewController() else {
            throw NSError(
                domain: "GoogleSignInManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No active view controller found to present Google Sign-In."]
            )
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: topViewController)
        return result.user
    }

    @MainActor
    private func topPresentedViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        guard let window = activeScene?.windows.first(where: { $0.isKeyWindow }) ?? activeScene?.windows.first,
              let root = window.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    /// Sign out from Google
    func signOutFromGoogle() {
        GIDSignIn.sharedInstance.signOut()
    }
}
#endif
