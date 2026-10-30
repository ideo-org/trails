//
//  OnboardingView.swift
//  Trails
//
//  First-launch onboarding aligned with Trails PRD v0.1.0:
//  - Living Heritage & Human Authorship (PRD Section 1 & 10.1)
//  - Quiet curiosity, spatial memory, and checkpoints (PRD Section 2 & 9.3)
//  - Private by default: captures stay locally on device (PRD Section 8.1 & 11.3)
//  - Welcome and local identity setup (PRD Section 7.2, 8.1 & 9.1)
//  - Warm limestone, forest green, terracotta, and brass palette (PRD Section 10.1 & DESIGN.md)
//

import SwiftUI
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

struct OnboardingView: View {
    @Binding var isOnboardingDone: Bool

    @AppStorage("localCreatorId") private var localCreatorId: String = ""
    @AppStorage("localDisplayName") private var localDisplayName: String = ""
    @AppStorage("localUsername") private var localUsername: String = ""
    @AppStorage("localIntroduction") private var localIntroduction: String = ""

    @ObservedObject private var authManager = AuthManager.shared

    @State private var currentPage = 0
    @State private var enteredUsername: String = ""
    @State private var enteredDisplayName: String = ""
    @State private var enteredIntroduction: String = ""
    @State private var isAuthenticatingSocial: Bool = false
    @State private var socialAuthError: String? = nil

    private let totalPages = 4

    var body: some View {
        ZStack {
            AppColors.canvas
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Header Bar
                headerBar
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                // Paged Content
                TabView(selection: $currentPage) {
                    // Page 0: Product Definition & Living Heritage
                    introPage
                        .tag(0)

                    // Page 1: Moments & Human Perspective
                    momentsPage
                        .tag(1)

                    // Page 2: Local & Private by Default
                    privacyPage
                        .tag(2)

                    // Page 3: Local Identity Setup (PRD 8.1 & 9.1)
                    identityPage
                        .tag(3)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

                // Bottom Controls & Indicators
                bottomControls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
        .onAppear {
            initializeLocalCreatorId()
            if !localDisplayName.isEmpty {
                enteredDisplayName = localDisplayName
            }
            if !localUsername.isEmpty {
                enteredUsername = localUsername
            }
            if !localIntroduction.isEmpty {
                enteredIntroduction = localIntroduction
            }
        }
        .task {
            Analytics.trackOnboardingStep(0, stepName: "started")
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(AppColors.terracotta)
                    .frame(width: 6, height: 6)

                Text("TRAILS · PRIVATE SCANS")
                    .font(AppFonts.labelSpatial)
                    .tracking(1.4)
                    .foregroundColor(AppColors.forestGreen)
            }

            Spacer()

            if currentPage < totalPages - 1 {
                Button("Skip") {
                    completeOnboarding()
                }
                .font(AppFonts.headlineSmall)
                .foregroundColor(AppColors.onSurfaceVariant)
                .accessibilityIdentifier("onboarding.skip")
            }
        }
    }

    // MARK: - Page 0: Living Heritage

    private var introPage: some View {
        VStack(spacing: 28) {
            Spacer()

            // Visual Emblem
            ZStack {
                Circle()
                    .stroke(AppColors.forestGreen.opacity(0.12), lineWidth: 1)
                    .frame(width: 190, height: 190)

                Circle()
                    .fill(AppColors.surfaceContainerLow)
                    .frame(width: 140, height: 140)

                Image(systemName: "compass.drawing")
                    .font(.system(size: 64, weight: .light))
                    .foregroundColor(AppColors.forestGreen)

                // Small terracotta trail node
                Circle()
                    .fill(AppColors.terracotta)
                    .frame(width: 14, height: 14)
                    .offset(x: 48, y: -48)
            }

            // Copy
            VStack(spacing: 14) {
                Text("LIVING HERITAGE")
                    .font(AppFonts.labelSpatial)
                    .tracking(2.0)
                    .foregroundColor(AppColors.mutedBrass)

                Text("A place’s story includes the people who passed through it.")
                    .font(AppFonts.headlineLarge)
                    .foregroundColor(AppColors.deepInk)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 16)

                Text("Trails lets you capture movement through a space and preserve the observations, memories, and moments you associate with it.")
                    .font(AppFonts.bodyMedium)
                    .foregroundColor(AppColors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 24)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Page 1: Human Perspective & Moments

    private var momentsPage: some View {
        VStack(spacing: 28) {
            Spacer()

            // Visual Emblem
            ZStack {
                Circle()
                    .stroke(AppColors.terracotta.opacity(0.18), lineWidth: 1)
                    .frame(width: 190, height: 190)

                Circle()
                    .fill(AppColors.surfaceContainerLow)
                    .frame(width: 140, height: 140)

                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 62, weight: .light))
                    .foregroundColor(AppColors.terracotta)

                // Brass waypoint accent
                Circle()
                    .fill(AppColors.mutedBrass)
                    .frame(width: 12, height: 12)
                    .offset(x: -46, y: -38)
            }

            // Copy
            VStack(spacing: 14) {
                Text("HUMAN PERSPECTIVE")
                    .font(AppFonts.labelSpatial)
                    .tracking(2.0)
                    .foregroundColor(AppColors.terracotta)

                Text("Mark moments along your journey.")
                    .font(AppFonts.headlineLarge)
                    .foregroundColor(AppColors.deepInk)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 16)

                Text("Drop checkpoints at meaningful thresholds—architectural details, quiet reflections, or notes on air and light. An authored perspective, not just geometry.")
                    .font(AppFonts.bodyMedium)
                    .foregroundColor(AppColors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 24)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Page 2: Private by Default

    private var privacyPage: some View {
        VStack(spacing: 24) {
            Spacer()

            // Visual Emblem
            ZStack {
                Circle()
                    .stroke(AppColors.forestGreen.opacity(0.12), lineWidth: 1)
                    .frame(width: 180, height: 180)

                Circle()
                    .fill(AppColors.surfaceContainerLow)
                    .frame(width: 130, height: 130)

                Image(systemName: "lock.shield")
                    .font(.system(size: 58, weight: .light))
                    .foregroundColor(AppColors.forestGreen)
            }

            // Copy
            VStack(spacing: 12) {
                Text("PRIVATE BY DEFAULT")
                    .font(AppFonts.labelSpatial)
                    .tracking(2.0)
                    .foregroundColor(AppColors.forestGreen)

                Text("Your captures stay on this device.")
                    .font(AppFonts.headlineLarge)
                    .foregroundColor(AppColors.deepInk)
                    .multilineTextAlignment(.center)

                Text("No account, password, or cloud sync is required for your core workflow. Scans, paths, and notes are preserved locally in your hands.")
                    .font(AppFonts.bodyMedium)
                    .foregroundColor(AppColors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 20)
            }

            // Approved Security & Privacy Reassurance Card (PRD 11.3)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(AppColors.forestGreen)
                    Text("Saved privately on this device.")
                        .font(AppFonts.headlineSmall)
                        .foregroundColor(AppColors.deepInk)
                }

                Text("Trails does not upload this capture. Captures stay on your device and are not automatically backed up.")
                    .font(AppFonts.bodySmall)
                    .foregroundColor(AppColors.onSurfaceVariant)
                    .lineSpacing(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.pureWhite)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.outlineVariant.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            .padding(.horizontal, 16)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Page 3: Identity & Access (Username, Google, Apple)

    private var identityPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                Spacer(minLength: 12)

                // Icon
                Circle()
                    .fill(AppColors.surfaceContainerLow)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 36, weight: .light))
                            .foregroundColor(AppColors.terracotta)
                    )

                // Headline
                VStack(spacing: 8) {
                    Text("CHOOSE YOUR IDENTITY")
                        .font(AppFonts.labelSpatial)
                        .tracking(2.0)
                        .foregroundColor(AppColors.mutedBrass)

                    Text("How would you like to start?")
                        .font(AppFonts.headlineLarge)
                        .foregroundColor(AppColors.deepInk)
                        .multilineTextAlignment(.center)

                    Text("Pick a username to start exploring privately right away, or sign in with Google / Apple. You can link accounts anytime in your Profile.")
                        .font(AppFonts.bodyMedium)
                        .foregroundColor(AppColors.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                if let error = socialAuthError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColors.error)
                        Text(error)
                            .font(AppFonts.bodySmall)
                            .foregroundColor(AppColors.error)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(AppColors.error.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                }

                if isAuthenticatingSocial {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Connecting your account...")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.forestGreen)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(AppColors.pureWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 16)
                } else {
                    // Option 1: Start with Username (Private & Instant)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(AppColors.forestGreen)
                            Text("START WITH USERNAME")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.forestGreen)
                                .tracking(1.2)
                            Spacer()
                            Text("100% PRIVATE")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.mutedBrass)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("USERNAME")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.outline)

                            HStack(spacing: 4) {
                                Text("@")
                                    .font(AppFonts.bodyLarge)
                                    .foregroundColor(AppColors.outline)

                                TextField("username (e.g., alex, explorer)", text: $enteredUsername)
                                    .font(AppFonts.bodyLarge)
                                    .foregroundColor(AppColors.deepInk)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(AppColors.surfaceContainerLow)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AppColors.outlineVariant.opacity(0.5), lineWidth: 1)
                            )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("DISPLAY NAME (OPTIONAL)")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.outline)

                            TextField("e.g., Alex Chen", text: $enteredDisplayName)
                                .font(AppFonts.bodyMedium)
                                .foregroundColor(AppColors.deepInk)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(AppColors.surfaceContainerLow)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(AppColors.outlineVariant.opacity(0.5), lineWidth: 1)
                                )
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(AppColors.forestGreen)
                                .font(.system(size: 13))

                            Text("No password needed. Captures stay on device.")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.outline)
                        }
                        .padding(.top, 2)

                        Button {
                            saveIdentityAndComplete()
                        } label: {
                            HStack(spacing: 8) {
                                Text(buttonTitleForUsername)
                                    .font(AppFonts.headlineSmall)
                                Image(systemName: "arrow.right")
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .foregroundColor(AppColors.onPrimary)
                            .background(AppColors.forestGreen)
                            .clipShape(Capsule())
                        }
                        .padding(.top, 4)
                        .accessibilityIdentifier("onboarding.startWithUsername")
                    }
                    .padding(20)
                    .background(AppColors.pureWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(AppColors.outlineVariant.opacity(0.5), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 3)
                    .padding(.horizontal, 16)

                    // Divider
                    HStack {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(AppColors.outlineVariant.opacity(0.4))
                            .padding(.horizontal, 20)
                        Text("or continue with")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.outline)
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(AppColors.outlineVariant.opacity(0.4))
                            .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 4)

                    // Option 2 & 3: Social Sign-In Options (Google & Apple)
                    VStack(spacing: 12) {
                        #if canImport(GoogleSignIn)
                        Button {
                            Task {
                                await continueWithGoogle()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "g.circle.fill")
                                    .font(.system(size: 20, weight: .bold))
                                Text("Continue with Google")
                                    .font(AppFonts.headlineSmall)
                            }
                            .foregroundColor(AppColors.deepInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(AppColors.pureWhite)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(AppColors.outlineVariant.opacity(0.6), lineWidth: 1)
                            )
                        }
                        #endif

                        Button {
                            continueWithApple()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Continue with Apple")
                                    .font(AppFonts.headlineSmall)
                            }
                            .foregroundColor(AppColors.pureWhite)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(AppColors.deepInk)
                            .clipShape(Capsule())
                        }

                        Text("Link Google or Apple to sync your creator identity and publish verified trails.")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.outline)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 16)
            }
        }
    }

    private var buttonTitleForUsername: String {
        let clean = enteredUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        if !clean.isEmpty {
            return "Start as @\(clean)"
        }
        return "Start Exploring with Username"
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 16) {
            // Page Indicator Dots
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    if index == currentPage {
                        Capsule()
                            .fill(AppColors.forestGreen)
                            .frame(width: 24, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                    } else {
                        Circle()
                            .fill(AppColors.outlineVariant.opacity(0.5))
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .padding(.vertical, 4)

            // Action Buttons
            if currentPage < totalPages - 1 {
                Button("Continue") {
                    Haptics.selection()
                    withAnimation(.snappy(duration: 0.25)) {
                        currentPage += 1
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("onboarding.next")
            } else {
                Button("Skip and use guest identity") {
                    completeOnboarding()
                }
                .font(AppFonts.labelUI)
                .foregroundColor(AppColors.outline)
                .padding(.vertical, 4)
                .accessibilityIdentifier("onboarding.skipFinal")
            }

            // Contextual Guidance Note (PRD 8.1 & 10.3)
            Text("LiDAR-ready on iPhone Pro & iPad Pro. Camera permission requested contextually.")
                .font(AppFonts.labelSpatial)
                .foregroundColor(AppColors.outline)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Identity & Completion Logic

    private func initializeLocalCreatorId() {
        if localCreatorId.isEmpty {
            localCreatorId = UUID().uuidString
        }
    }

    private func saveIdentityAndComplete() {
        let trimmedName = enteredDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = enteredUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
        let trimmedIntro = enteredIntroduction.trimmingCharacters(in: .whitespacesAndNewlines)

        localDisplayName = trimmedName
        localUsername = trimmedUsername
        localIntroduction = trimmedIntro

        let effectiveDisplayName = trimmedName.isEmpty ? (trimmedUsername.isEmpty ? "A trail by you" : trimmedUsername.capitalized) : trimmedName

        // Persist to the TrailsDataStore local profile so You tab and trail authorship pick it up
        TrailsDataStore.shared.updateProfile(
            displayName: effectiveDisplayName,
            introduction: trimmedIntro.isEmpty ? "Spatial explorer documenting living spaces." : trimmedIntro,
            username: trimmedUsername.isEmpty ? nil : trimmedUsername
        )

        completeOnboarding()
    }

    private func continueWithGoogle() async {
        isAuthenticatingSocial = true
        socialAuthError = nil
        do {
            #if canImport(GoogleSignIn)
            guard let user = try await GoogleSignInManager.shared.signInWithGoogle() else {
                isAuthenticatingSocial = false
                return
            }
            _ = try await authManager.googleAuth(user)
            await MainActor.run {
                self.isAuthenticatingSocial = false
                completeOnboarding()
            }
            #else
            isAuthenticatingSocial = false
            #endif
        } catch let error as NSError {
            await MainActor.run {
                self.isAuthenticatingSocial = false
                if error.domain == "com.google.GIDSignIn" && error.code == -5 {
                    // Cancelled by user
                    return
                }
                self.socialAuthError = error.localizedDescription
            }
        }
    }

    private func continueWithApple() {
        isAuthenticatingSocial = true
        socialAuthError = nil
        Task {
            do {
                let credential = try await AppleSignInManager.shared.requestAppleAuthorization()
                _ = try await authManager.appleAuth(credential, nonce: AppleSignInManager.nonce)
                await MainActor.run {
                    self.isAuthenticatingSocial = false
                    completeOnboarding()
                }
            } catch {
                await MainActor.run {
                    self.isAuthenticatingSocial = false
                    if let message = AppleSignInManager.friendlyErrorMessage(for: error) {
                        self.socialAuthError = message
                    }
                }
            }
        }
    }

    private func completeOnboarding() {
        initializeLocalCreatorId()
        Haptics.success()
        Analytics.trackOnboardingStep(totalPages, stepName: "completed")
        isOnboardingDone = true
    }
}

#Preview {
    OnboardingView(isOnboardingDone: .constant(false))
}
