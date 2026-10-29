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

struct OnboardingView: View {
    @Binding var isOnboardingDone: Bool

    @AppStorage("localCreatorId") private var localCreatorId: String = ""
    @AppStorage("localDisplayName") private var localDisplayName: String = ""
    @AppStorage("localIntroduction") private var localIntroduction: String = ""

    @State private var currentPage = 0
    @State private var enteredDisplayName: String = ""
    @State private var enteredIntroduction: String = ""

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

    // MARK: - Page 3: Local Identity Setup (PRD Section 8.1 & 9.1)

    private var identityPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                Spacer(minLength: 16)

                // Icon
                Circle()
                    .fill(AppColors.surfaceContainerLow)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(AppColors.terracotta)
                    )

                // Headline
                VStack(spacing: 10) {
                    Text("LOCAL IDENTITY")
                        .font(AppFonts.labelSpatial)
                        .tracking(2.0)
                        .foregroundColor(AppColors.mutedBrass)

                    Text("Author your spatial journey.")
                        .font(AppFonts.headlineLarge)
                        .foregroundColor(AppColors.deepInk)
                        .multilineTextAlignment(.center)

                    Text("Set a display name to attribute your trails and moments. No password or email needed.")
                        .font(AppFonts.bodyMedium)
                        .foregroundColor(AppColors.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                // Input Card
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DISPLAY NAME")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.outline)

                        TextField("e.g., Sarah Chen (or leave blank)", text: $enteredDisplayName)
                            .font(AppFonts.bodyLarge)
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

                    VStack(alignment: .leading, spacing: 6) {
                        Text("CONTEXT / FOCUS (OPTIONAL)")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.outline)

                        TextField("e.g., Resident, Architect, Explorer", text: $enteredIntroduction)
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
                        Image(systemName: "info.circle")
                            .foregroundColor(AppColors.mutedBrass)
                            .font(.system(size: 13))

                        Text("Default attribution: “A trail by you” until a name is supplied.")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.outline)
                    }
                    .padding(.top, 2)
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

                Spacer(minLength: 16)
            }
        }
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
                VStack(spacing: 10) {
                    Button("Open My Trails") {
                        saveIdentityAndComplete()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("onboarding.startScanning")

                    Button("Skip and use default identity") {
                        completeOnboarding()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
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
        let trimmedIntro = enteredIntroduction.trimmingCharacters(in: .whitespacesAndNewlines)

        localDisplayName = trimmedName
        localIntroduction = trimmedIntro

        completeOnboarding()
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
