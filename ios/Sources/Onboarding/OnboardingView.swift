//
//  OnboardingView.swift
//  Trails
//
//  Scan-first onboarding for new Trails users.
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isOnboardingDone: Bool

    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: AppConfiguration.appName,
            description: "A LiDAR-first scanner built for precise iPhone captures, local archives, and fast revisits.",
            imageName: "viewfinder.rectangular",
            imageColor: AppColors.secondary,
            eyebrow: "PRO SPATIAL SCANNER"
        ),
        OnboardingPage(
            title: "Paint every surface",
            description: "Walk naturally, sweep each surface once, and add a quick second pass only where the cloud looks thin.",
            imageName: "dot.viewfinder",
            imageColor: AppColors.lidar,
            eyebrow: "SCAN TECHNIQUE"
        ),
        OnboardingPage(
            title: "Tune the live view",
            description: "Use the center mixer to balance camera passthrough against the point cloud while keeping scan controls responsive.",
            imageName: "slider.vertical.3",
            imageColor: AppColors.accent,
            eyebrow: "LIVE MIXER"
        ),
        OnboardingPage(
            title: "Build a spatial archive",
            description: "Save scans locally, revisit them in 3D, export PLY files, and share selected captures when you need to move data.",
            imageName: "cube.transparent.fill",
            imageColor: AppColors.primary,
            eyebrow: "LIBRARY"
        )
    ]

    var body: some View {
        ZStack {
            AppColors.scannerGradient
                .ignoresSafeArea()

            VStack {
                HStack {
                    Text(AppConfiguration.appTagline.uppercased())
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(AppColors.secondary)

                    Spacer()

                    Button("Skip") {
                        completeOnboarding()
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .opacity(currentPage < pages.count - 1 ? 1 : 0)
                    .allowsHitTesting(currentPage < pages.count - 1)
                    .accessibilityIdentifier("onboarding.skip")
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(page: page)
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))

                VStack(spacing: 16) {
                    if currentPage < pages.count - 1 {
                        Button("Next") {
                            Haptics.selection()
                            withAnimation(.snappy(duration: 0.2)) {
                                currentPage += 1
                            }
                        }
                        .primaryStyle()
                        .accessibilityIdentifier("onboarding.next")
                    } else {
                        Button("Start scanning") {
                            completeOnboarding()
                        }
                        .primaryStyle()
                        .accessibilityIdentifier("onboarding.startScanning")
                    }

                    Text("Best on LiDAR-capable iPhone Pro and iPad Pro devices.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.52))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
        .task {
            Analytics.trackOnboardingStep(0, stepName: "started")
        }
    }

    private func completeOnboarding() {
        Haptics.success()
        Analytics.trackOnboardingStep(pages.count, stepName: "completed")
        isOnboardingDone = true
    }
}

// MARK: - Onboarding Page Model

struct OnboardingPage {
    let title: String
    let description: String
    let imageName: String
    let imageColor: Color
    let eyebrow: String

    init(title: String, description: String, imageName: String, imageColor: Color = .primary, eyebrow: String) {
        self.title = title
        self.description = description
        self.imageName = imageName
        self.imageColor = imageColor
        self.eyebrow = eyebrow
    }
}

// MARK: - Onboarding Page View

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(page.imageColor.opacity(0.18), lineWidth: 1)
                    .frame(width: 180, height: 180)
                Circle()
                    .fill(page.imageColor.opacity(0.09))
                    .frame(width: 132, height: 132)
                    .blur(radius: 1)
                Image(systemName: page.imageName)
                    .font(.system(size: 78, weight: .light))
                    .foregroundStyle(page.imageColor)
                    .shadow(color: page.imageColor.opacity(0.35), radius: 24)
            }

            VStack(spacing: 14) {
                Text(page.eyebrow)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.7)
                    .foregroundStyle(page.imageColor)

                Text(page.title)
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(page.description)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 30)
            }

            Spacer()
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(isOnboardingDone: .constant(false))
}
