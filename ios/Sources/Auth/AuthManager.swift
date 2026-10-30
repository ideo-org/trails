//
//  AuthManager.swift
//  MyApp
//
//  Central authentication manager supporting two modes:
//  - Firebase mode: Full auth with Apple/Google Sign-In, anonymous auth, credential linking
//  - Local mode: Device-based identity for RevenueCat/TelemetryDeck without Firebase
//
//  Mode is controlled by AppConfiguration.useFirebase
//

import Foundation
import AuthenticationServices
import SwiftUI
import Combine

#if canImport(Firebase)
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
#endif

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

#if canImport(RevenueCat)
import RevenueCat
#endif

#if canImport(TelemetryDeck)
import TelemetryDeck
#endif

/// Authentication states for the app
enum AuthState {
    /// Anonymously authenticated (Firebase) or local mode
    case authenticated
    /// Authenticated with a sign-in provider (Apple, Google)
    case signedIn
    /// Not authenticated
    case signedOut
}

/// Authentication errors
enum AuthError: Error {
    case noAnonymousUser
    case invalidCredentials
    case firebaseDisabled
    case unknown
}

class AuthManager: ObservableObject {

    static let shared = AuthManager()
    private let firestoreManager = FirestoreManager.shared

    /// Current user ID (Firebase UID or device ID depending on mode)
    var userId: String {
        #if canImport(Firebase)
        if AppConfiguration.useFirebase {
            return user?.uid ?? localUserId
        }
        #endif
        return localUserId
    }

    /// Local device-based user ID for non-Firebase mode
    private var localUserId: String {
        if let storedId = UserDefaults.standard.string(forKey: "localUserId") {
            return storedId
        }
        let newId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "localUserId")
        return newId
    }

    #if canImport(Firebase)
    var user: User?
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var db: Firestore? = nil
    #endif

    @Published var authState: AuthState = .signedOut
    @Published var isCheckingAuth: Bool = true

    @Published var localAppleUserId: String? {
        didSet {
            UserDefaults.standard.set(localAppleUserId, forKey: "localAppleUserId")
        }
    }
    @Published var localAppleEmail: String? {
        didSet {
            UserDefaults.standard.set(localAppleEmail, forKey: "localAppleEmail")
        }
    }
    @Published var localAppleFullName: String? {
        didSet {
            UserDefaults.standard.set(localAppleFullName, forKey: "localAppleFullName")
        }
    }

    private init() {
        self.localAppleUserId = UserDefaults.standard.string(forKey: "localAppleUserId")
        self.localAppleEmail = UserDefaults.standard.string(forKey: "localAppleEmail")
        self.localAppleFullName = UserDefaults.standard.string(forKey: "localAppleFullName")

        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else {
            #if canImport(Firebase)
            db = nil
            #endif
            isCheckingAuth = false
            return
        }

        if self.localAppleUserId != nil {
            self.authState = .signedIn
        }

        #if canImport(Firebase)
        if AppConfiguration.useFirebase {
            if FirebaseApp.app() == nil {
                FirebaseApp.configure()
            }
            db = Firestore.firestore()
            Task {
                await handleSignInValidationAndProviderChecks()
            }
        } else {
            db = nil
            setupLocalMode()
        }
        #else
        setupLocalMode()
        #endif
    }

    /// Setup for local (non-Firebase) mode
    private func setupLocalMode() {
        DispatchQueue.main.async {
            self.authState = .authenticated
            self.isCheckingAuth = false
        }

        // Configure analytics with local user ID
        #if canImport(TelemetryDeck)
        if AppConfiguration.isTelemetryDeckConfigured {
            TelemetryDeck.updateDefaultUserID(to: localUserId)
        }
        #endif

        // Configure RevenueCat with local user ID
        #if canImport(RevenueCat)
        if AppConfiguration.isRevenueCatConfigured {
            Task {
                do {
                    _ = try await Purchases.shared.logIn(localUserId)
                } catch {
                    debugPrint("Failed to log in to RevenueCat: \(error)")
                }
            }
        }
        #endif
    }

    // MARK: - Initial Authentication

    @MainActor
    func handleInitialAuthentication() async {
        #if canImport(Firebase)
        guard AppConfiguration.useFirebase else {
            setupLocalMode()
            return
        }

        if Auth.auth().currentUser == nil {
            do {
                try await signInAnonymously()
            } catch {
                debugPrint("Error creating anonymous account: \(error)")
            }
        }
        #else
        setupLocalMode()
        #endif
    }

    /// Sign in anonymously for users who haven't created an account yet
    func signInAnonymously() async throws {
        #if canImport(Firebase)
        guard AppConfiguration.useFirebase else {
            throw AuthError.firebaseDisabled
        }

        let result = try await Auth.auth().signInAnonymously()
        debugPrint("Signed in anonymously with user: \(result.user.uid)")
        updateState(user: result.user)
        #else
        throw AuthError.firebaseDisabled
        #endif
    }

    /// Check if current user is anonymous
    var isAnonymous: Bool {
        #if canImport(Firebase)
        if AppConfiguration.useFirebase {
            guard let currentUser = Auth.auth().currentUser else { return false }
            return currentUser.isAnonymous
        }
        #endif
        return false
    }

    /// Check if sign-in UI should be shown
    /// Requires both Firebase enabled AND enableAuth flag set
    var canSignIn: Bool {
        AppConfiguration.useFirebase && AppConfiguration.enableAuth
    }

    // MARK: - Auth State Management

    #if canImport(Firebase)
    func configureAuthStateChanges() {
        guard AppConfiguration.useFirebase else { return }

        authStateHandle = Auth.auth().addStateDidChangeListener { _, user in
            self.updateState(user: user)
        }
    }

    func removeAuthStateListener() {
        guard AppConfiguration.useFirebase else { return }

        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    internal func updateState(user: User?) {
        DispatchQueue.main.async {
            self.user = user

            if let user = user {
                // Update analytics user IDs
                #if canImport(TelemetryDeck)
                if AppConfiguration.isTelemetryDeckConfigured {
                    TelemetryDeck.updateDefaultUserID(to: user.uid)
                }
                #endif

                // Update RevenueCat user ID
                #if canImport(RevenueCat)
                if AppConfiguration.isRevenueCatConfigured {
                    Task {
                        do {
                            _ = try await Purchases.shared.logIn(user.uid)
                            Purchases.shared.attribution.setAttributes([
                                "$telemetryDeckUserId": user.uid,
                                "$telemetryDeckAppId": AppConfiguration.telemetryDeckAppID
                            ])
                        } catch {
                            debugPrint("Failed to log in to RevenueCat: \(error)")
                        }
                    }
                }
                #endif

                if user.isAnonymous {
                    self.authState = .authenticated
                } else {
                    self.authState = .signedIn
                    self.firestoreManager.refreshUserCollection()
                }
            } else {
                self.authState = .signedOut
            }
        }
    }
    #endif

    // MARK: - Sign-In Validation

    #if canImport(Firebase)
    func handleSignInValidationAndProviderChecks() async {
        guard AppConfiguration.useFirebase else {
            setupLocalMode()
            return
        }

        configureAuthStateChanges()

        defer {
            DispatchQueue.main.async {
                self.isCheckingAuth = false
            }
        }

        guard let currentUser = Auth.auth().currentUser else {
            return
        }

        // Validate sign-in
        do {
            try await currentUser.reload()
        } catch {
            debugPrint("User is no longer valid: \(error.localizedDescription)")
            try? Auth.auth().signOut()
            return
        }

        // Verify provider credentials
        await verifySignInProviders(currentUser: currentUser)
    }

    private func verifySignInProviders(currentUser: User) async {
        let providerData = currentUser.providerData

        var isAppleCredentialRevoked = false
        var isGoogleCredentialRevoked = false

        if providerData.contains(where: { $0.providerID == "apple.com" }) {
            isAppleCredentialRevoked = await !verifySignInWithAppleID()
        }

        #if canImport(GoogleSignIn)
        if providerData.contains(where: { $0.providerID == "google.com" }) {
            isGoogleCredentialRevoked = await !verifyGoogleSignIn()
        }
        #endif

        if isAppleCredentialRevoked && isGoogleCredentialRevoked {
            signOut()
        }
    }

    private func verifySignInWithAppleID() async -> Bool {
        let appleIDProvider = ASAuthorizationAppleIDProvider()

        guard let providerData = Auth.auth().currentUser?.providerData,
              let appleProviderData = providerData.first(where: { $0.providerID == "apple.com" }) else {
            return false
        }

        do {
            let credentialState = try await appleIDProvider.credentialState(forUserID: appleProviderData.uid)
            return credentialState != .revoked && credentialState != .notFound
        } catch {
            return false
        }
    }

    #if canImport(GoogleSignIn)
    private func verifyGoogleSignIn() async -> Bool {
        guard let providerData = Auth.auth().currentUser?.providerData,
              providerData.contains(where: { $0.providerID == "google.com" }) else {
            return false
        }

        do {
            try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            return true
        } catch {
            return false
        }
    }
    #endif
    #endif

    // MARK: - Sign Out

    func signOut() {
        self.localAppleUserId = nil
        self.localAppleEmail = nil
        self.localAppleFullName = nil
        UserDefaults.standard.removeObject(forKey: "localAppleUserId")
        UserDefaults.standard.removeObject(forKey: "localAppleEmail")
        UserDefaults.standard.removeObject(forKey: "localAppleFullName")

        #if canImport(Firebase)
        if AppConfiguration.useFirebase {
            do {
                try Auth.auth().signOut()
                SettingsViewModel.shared.restoreSettings(newSettings: [:])

                // Reset RevenueCat to anonymous
                #if canImport(RevenueCat)
                if AppConfiguration.isRevenueCatConfigured {
                    Purchases.shared.logOut { _, error in
                        if let error = error {
                            debugPrint("Failed to log out of RevenueCat: \(error)")
                        }
                    }
                }
                #endif

                // Reset TelemetryDeck to anonymous
                #if canImport(TelemetryDeck)
                if AppConfiguration.isTelemetryDeckConfigured {
                    let anonymousID = UIDevice.current.identifierForVendor?.uuidString ?? "unknown_user"
                    TelemetryDeck.updateDefaultUserID(to: anonymousID)
                }
                #endif
            } catch {
                debugPrint("Failed to sign out: \(error.localizedDescription)")
            }
        }
        #endif

        DispatchQueue.main.async {
            self.authState = .authenticated
        }
    }

    // MARK: - Anonymous User Linking

    #if canImport(Firebase)
    private func linkAnonymousUser(with credentials: AuthCredential) async throws -> AuthDataResult {
        guard AppConfiguration.useFirebase else {
            throw AuthError.firebaseDisabled
        }

        guard let anonymousUser = Auth.auth().currentUser, anonymousUser.isAnonymous else {
            let result = try await Auth.auth().signIn(with: credentials)
            await MainActor.run {
                self.updateState(user: result.user)
            }
            return result
        }

        do {
            let result = try await anonymousUser.link(with: credentials)
            await MainActor.run {
                self.updateState(user: result.user)
            }
            return result
        } catch let error as NSError {
            if error.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                // Credentials already in use - sign in with existing account
                let fallbackCredential = (error.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential) ?? credentials
                let result = try await Auth.auth().signIn(with: fallbackCredential)

                // Migrate anonymous user data
                await migrateAnonymousUserData(from: anonymousUser.uid, to: result.user.uid)

                await MainActor.run {
                    self.updateState(user: result.user)
                }
                return result
            }
            throw error
        }
    }

    private func migrateAnonymousUserData(from anonymousUID: String, to permanentUID: String) async {
        guard let db = db else { return }

        await withCheckedContinuation { continuation in
            db.runTransaction({ (transaction, errorPointer) -> Any? in
                do {
                    let anonymousRef = db.collection("users").document(anonymousUID)
                    let anonymousDoc = try transaction.getDocument(anonymousRef)
                    guard let anonymousData = anonymousDoc.data() else { return nil }

                    let permanentRef = db.collection("users").document(permanentUID)
                    let permanentDoc = try? transaction.getDocument(permanentRef)
                    var newData = permanentDoc?.data() ?? [:]

                    // Fields to migrate from anonymous account
                    let fieldsToMigrate = [
                        "subscriptionStatus",
                        "subscriptionTier",
                        "settings",
                        "createdAt"
                    ]

                    for field in fieldsToMigrate {
                        if let value = anonymousData[field] {
                            newData[field] = value
                        }
                    }

                    // Add migration metadata
                    newData["migratedFromAnonymous"] = true
                    newData["migrationDate"] = Timestamp(date: Date())
                    newData["previousUID"] = anonymousUID

                    // Add user profile data
                    if let currentUser = Auth.auth().currentUser {
                        newData["email"] = currentUser.email
                        newData["displayName"] = currentUser.displayName
                        newData["photoURL"] = currentUser.photoURL?.absoluteString
                        newData["lastUpdated"] = Timestamp(date: Date())
                    }

                    transaction.setData(newData, forDocument: permanentRef, merge: true)
                    transaction.deleteDocument(anonymousRef)

                    return true
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }) { _, error in
                if let error = error {
                    debugPrint("Error migrating anonymous user data: \(error)")
                }
                continuation.resume()
            }
        }
    }
    #endif

    /// Check if Google is linked as an authentication provider
    var isGoogleLinked: Bool {
        #if canImport(Firebase)
        guard let user = user else { return false }
        return user.providerData.contains(where: { $0.providerID == "google.com" })
        #else
        return false
        #endif
    }

    /// Check if Apple is linked as an authentication provider (native Apple ID or Firebase)
    var isAppleLinked: Bool {
        if let appleId = localAppleUserId, !appleId.isEmpty {
            return true
        }
        #if canImport(Firebase)
        guard let user = user else { return false }
        return user.providerData.contains(where: { $0.providerID == "apple.com" })
        #else
        return false
        #endif
    }

    /// User's email from Apple ID or Google/Firebase
    var effectiveEmail: String? {
        if let appleEmail = localAppleEmail, !appleEmail.isEmpty {
            return appleEmail
        }
        #if canImport(Firebase)
        if let email = user?.email, !email.isEmpty {
            return email
        }
        #endif
        return nil
    }

    /// Set or switch the active username locally without requiring credentials
    @MainActor
    func signInWithUsername(_ rawUsername: String, displayName: String? = nil) {
        let cleanUsername = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
        guard !cleanUsername.isEmpty else { return }

        let effectiveName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameToUse = (effectiveName != nil && !effectiveName!.isEmpty) ? effectiveName! : cleanUsername.capitalized

        UserDefaults.standard.set(cleanUsername, forKey: "localUsername")
        UserDefaults.standard.set(nameToUse, forKey: "localDisplayName")

        TrailsDataStore.shared.updateProfile(
            displayName: nameToUse,
            introduction: TrailsDataStore.shared.localProfile.introduction,
            username: cleanUsername
        )
    }

    // MARK: - Google Sign-In

    #if canImport(Firebase) && canImport(GoogleSignIn)
    func googleAuth(_ user: GIDGoogleUser) async throws -> AuthDataResult? {
        guard AppConfiguration.useFirebase else {
            throw AuthError.firebaseDisabled
        }

        guard let idToken = user.idToken?.tokenString else {
            throw NSError(
                domain: "AuthManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Google Sign-In failed to return an ID token."]
            )
        }

        let credentials = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: user.accessToken.tokenString
        )

        let result: AuthDataResult
        if let currentUser = Auth.auth().currentUser, currentUser.isAnonymous {
            result = try await linkAnonymousUser(with: credentials)
        } else {
            result = try await Auth.auth().signIn(with: credentials)
            await MainActor.run {
                self.updateState(user: result.user)
            }
        }

        // Synchronize Google user info with Trails profile (without overwriting existing custom username)
        await MainActor.run {
            let dataStore = TrailsDataStore.shared
            var newName = dataStore.localProfile.displayName
            if (newName.isEmpty || newName == "A trail by you"), let gName = result.user.displayName, !gName.isEmpty {
                newName = gName
            }
            let newAvatar = result.user.photoURL?.absoluteString ?? dataStore.localProfile.avatarURL
            var newUsername = dataStore.localProfile.username
            if (newUsername == nil || newUsername!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
               let email = result.user.email,
               let prefix = email.split(separator: "@").first {
                newUsername = String(prefix).lowercased()
            }
            dataStore.updateProfile(
                displayName: newName,
                introduction: dataStore.localProfile.introduction,
                username: newUsername,
                avatarURL: newAvatar
            )
        }

        return result
    }
    #endif

    // MARK: - Apple Sign-In

    @discardableResult
    func appleAuth(
        _ appleIDCredential: ASAuthorizationAppleIDCredential,
        nonce: String?
    ) async throws -> Bool {
        let appleUserId = appleIDCredential.user
        let appleEmail = appleIDCredential.email
        let formattedName = appleIDCredential.fullName?.formatted()

        // 1. Immediately establish verified native Apple ID identity on device
        await MainActor.run {
            self.localAppleUserId = appleUserId
            if let appleEmail, !appleEmail.isEmpty {
                self.localAppleEmail = appleEmail
            }
            if let formattedName, !formattedName.isEmpty {
                self.localAppleFullName = formattedName
            }

            let dataStore = TrailsDataStore.shared
            var newName = dataStore.localProfile.displayName
            if (newName.isEmpty || newName == "A trail by you"), let formattedName, !formattedName.isEmpty {
                newName = formattedName
            }
            var newUsername = dataStore.localProfile.username
            if (newUsername == nil || newUsername!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                if let email = appleEmail ?? self.localAppleEmail, let prefix = email.split(separator: "@").first {
                    newUsername = String(prefix).lowercased()
                }
            }
            dataStore.updateProfile(
                displayName: newName,
                introduction: dataStore.localProfile.introduction,
                username: newUsername,
                avatarURL: dataStore.localProfile.avatarURL
            )

            self.authState = .signedIn
        }

        // 2. Opportunistically link with Firebase if Firebase backend is available
        #if canImport(Firebase)
        if AppConfiguration.useFirebase,
           let nonce = nonce,
           let appleIDToken = appleIDCredential.identityToken,
           let idTokenString = String(data: appleIDToken, encoding: .utf8) {
            let credentials = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )
            do {
                if let currentUser = Auth.auth().currentUser, currentUser.isAnonymous {
                    _ = try await linkAnonymousUser(with: credentials)
                } else {
                    let result = try await Auth.auth().signIn(with: credentials)
                    await MainActor.run {
                        self.updateState(user: result.user)
                    }
                }
            } catch {
                debugPrint("Note: Firebase Apple sync skipped/offline: \(error.localizedDescription)")
            }
        }
        #endif

        return true
    }
}
