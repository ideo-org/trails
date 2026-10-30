//
//  LoginView.swift
//  MyApp
//
//  Sign-in screen with Apple and Google authentication options.
//  Only compiled when Firebase/GoogleSignIn are available.
//

#if canImport(GoogleSignIn)
import AuthenticationServices
import GoogleSignInSwift
import SwiftUI

public struct LoginView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    @EnvironmentObject var authManager: AuthManager

    @StateObject private var googleButtonVM: GoogleSignInButtonViewModel

    public init() {
        let viewModel = GoogleSignInButtonViewModel()
        viewModel.style = .wide
        viewModel.scheme = .light
        _googleButtonVM = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack {
            // Header Section
            VStack(spacing: 16) {
                Text("Sign in to")
                    .font(.title3)
                    .fontWeight(.bold)
                    .padding(.horizontal, 20)
                    .padding(.top)

                Text(AppConfiguration.appName)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.horizontal, 20)

                Text("Keep your Trails account ready for cloud features as they roll out.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            // Sign-in Buttons Section
            VStack(spacing: 16) {
                // Apple Sign-In Button
                SignInWithAppleButton(
                    onRequest: { request in
                        AppleSignInManager.shared.requestAppleAuthorization(request)
                    },
                    onCompletion: { result in
                        handleAppleID(result)
                    }
                )
                .signInWithAppleButtonStyle(colorScheme == .light ? .black : .white)
                .frame(width: 312, height: 48, alignment: .center)

                // Divider
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                    Text("or")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                }

                // Google Sign-In Button
                GoogleSignInButton(viewModel: googleButtonVM) {
                    Task {
                        await signInWithGoogle()
                    }
                }
                .frame(maxWidth: 312)
                .frame(height: 48)

            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .task {
            Analytics.track(event: "view.LoginView")
        }
    }

    // MARK: - Google Sign-In

    func signInWithGoogle() async {
        do {
            guard let user = try await GoogleSignInManager.shared.signInWithGoogle() else { return }

            let result = try await authManager.googleAuth(user)
            if result != nil {
                dismiss()
            }
        } catch {
            debugPrint("GoogleSignInError: \(error)")
        }
    }

    // MARK: - Apple Sign-In

    func handleAppleID(_ result: Result<ASAuthorization, Error>) {
        if case let .success(auth) = result {
            guard let appleIDCredentials = auth.credential as? ASAuthorizationAppleIDCredential else {
                debugPrint("AppleAuthorization failed: AppleID credential not available")
                return
            }

            Task {
                do {
                    let result = try await authManager.appleAuth(
                        appleIDCredentials,
                        nonce: AppleSignInManager.nonce
                    )
                    if result != nil {
                        dismiss()
                    }
                } catch {
                    debugPrint("AppleAuthorization failed: \(error)")
                }
            }
        } else if case let .failure(error) = result {
            debugPrint("AppleAuthorization failed: \(error)")
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager.shared)
}
#endif
