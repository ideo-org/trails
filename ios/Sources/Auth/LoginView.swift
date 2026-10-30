//
//  LoginView.swift
//  Trails
//
//  Sign-in screen with Apple and Google authentication options.
//  Only compiled when Firebase/GoogleSignIn are available.
//

#if canImport(GoogleSignIn)
import AuthenticationServices
import GoogleSignIn
import GoogleSignInSwift
import SwiftUI
import os.log

public struct LoginView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    @EnvironmentObject var authManager: AuthManager

    @StateObject private var googleButtonVM: GoogleSignInButtonViewModel
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var enteredUsername: String = ""
    @State private var showingUsernameInput: Bool = false

    private let logger = Logger(subsystem: "com.app2020.iportal", category: "Auth")

    public init() {
        let viewModel = GoogleSignInButtonViewModel()
        viewModel.style = .wide
        viewModel.scheme = .light
        _googleButtonVM = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            VStack {
                // Header Section
                VStack(spacing: 12) {
                    Text("Sign in to")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.top, 24)

                    Text(AppConfiguration.appName)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Author and explore trails. You can start with a username and link Google or Apple anytime.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                if let errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(12)
                    .frame(maxWidth: 320)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.bottom, 16)
                }

                // Sign-in Buttons Section
                VStack(spacing: 16) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.3)
                            .padding(.vertical, 20)
                    } else {
                        // Apple Sign-In Button
                        SignInWithAppleButton(
                            onRequest: { request in
                                errorMessage = nil
                                AppleSignInManager.shared.requestAppleAuthorization(request)
                            },
                            onCompletion: { result in
                                handleAppleID(result)
                            }
                        )
                        .signInWithAppleButtonStyle(colorScheme == .light ? .black : .white)
                        .frame(width: 312, height: 48, alignment: .center)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        // Divider
                        HStack {
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(Color.secondary.opacity(0.3))
                                .padding(.horizontal, 20)
                            Text("or")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(Color.secondary.opacity(0.3))
                                .padding(.horizontal, 20)
                        }
                        .frame(maxWidth: 312)

                        // Google Sign-In Button
                        GoogleSignInButton(viewModel: googleButtonVM) {
                            Task {
                                await signInWithGoogle()
                            }
                        }
                        .frame(maxWidth: 312)
                        .frame(height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        // Divider
                        HStack {
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(Color.secondary.opacity(0.3))
                                .padding(.horizontal, 20)
                            Text("or")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(Color.secondary.opacity(0.3))
                                .padding(.horizontal, 20)
                        }
                        .frame(maxWidth: 312)

                        // Username Section
                        if showingUsernameInput {
                            VStack(spacing: 10) {
                                HStack(spacing: 4) {
                                    Text("@")
                                        .foregroundColor(.secondary)
                                        .font(.body)
                                    TextField("username (e.g. explorer)", text: $enteredUsername)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .font(.body)
                                }
                                .padding(12)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .frame(maxWidth: 312)

                                Button {
                                    let clean = enteredUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                                        .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                                    guard !clean.isEmpty else { return }
                                    authManager.signInWithUsername(clean)
                                    dismiss()
                                } label: {
                                    Text("Use Username")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: 312)
                                        .frame(height: 44)
                                        .background(Color.accentColor)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .disabled(enteredUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        } else {
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    showingUsernameInput = true
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.circle")
                                    Text("Continue with Username")
                                }
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .frame(maxWidth: 312)
                                .frame(height: 44)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .background(Color(.systemBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task {
                Analytics.track(event: "view.LoginView")
            }
        }
    }

    // MARK: - Google Sign-In

    @MainActor
    func signInWithGoogle() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            logger.info("Starting Google Sign-In flow...")
            guard let user = try await GoogleSignInManager.shared.signInWithGoogle() else {
                logger.info("Google Sign-In dismissed or returned no user.")
                return
            }

            logger.info("Google Sign-In returned user: \(user.profile?.email ?? "no email"). Authenticating with Firebase...")
            let result = try await authManager.googleAuth(user)
            if result != nil {
                logger.info("Google Sign-In with Firebase succeeded! Dismissing sheet.")
                dismiss()
            }
        } catch let error as NSError {
            // Check for user cancellation (GIDSignInErrorCode.canceled is -5)
            if error.domain == "com.google.GIDSignIn" && error.code == -5 {
                logger.info("Google Sign-In was cancelled by user.")
                return
            }
            logger.error("Google Sign-In failed: \(error.localizedDescription) (Domain: \(error.domain), Code: \(error.code))")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Apple Sign-In

    func handleAppleID(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let appleIDCredentials = auth.credential as? ASAuthorizationAppleIDCredential else {
                logger.error("AppleAuthorization failed: AppleID credential not available")
                errorMessage = "Apple ID credential not available."
                return
            }

            isLoading = true
            Task {
                defer {
                    Task { @MainActor in
                        self.isLoading = false
                    }
                }
                do {
                    logger.info("Authenticating Apple credentials...")
                    let success = try await authManager.appleAuth(
                        appleIDCredentials,
                        nonce: AppleSignInManager.nonce
                    )
                    if success {
                        logger.info("Apple Sign-In succeeded! Dismissing sheet.")
                        await MainActor.run {
                            dismiss()
                        }
                    }
                } catch {
                    logger.error("Apple authentication failed: \(error.localizedDescription)")
                    await MainActor.run {
                        self.errorMessage = AppleSignInManager.friendlyErrorMessage(for: error) ?? error.localizedDescription
                    }
                }
            }

        case .failure(let error):
            if let message = AppleSignInManager.friendlyErrorMessage(for: error) {
                logger.error("AppleAuthorization failed: \(error.localizedDescription)")
                errorMessage = message
            } else {
                logger.info("Apple Sign-In cancelled by user.")
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager.shared)
}
#endif
