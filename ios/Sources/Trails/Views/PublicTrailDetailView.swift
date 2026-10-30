//
//  PublicTrailDetailView.swift
//  Trails
//
//  Remote trail detail sheet & action state machine compliant with PRD v0.4.0 §12, §13, §14, §15, §16.
//

import SwiftUI

public struct PublicTrailDetailView: View {
    @Environment(\.dismiss) private var dismiss
    public let record: DiscoveryRecord

    @ObservedObject private var downloadManager = TrailDownloadManager.shared
    @ObservedObject private var bookmarksStore = BookmarksStore.shared
    @ObservedObject private var dataStore = TrailsDataStore.shared

    @State private var showingSecondaryDetails: Bool = false
    @State private var showingOpenTrailViewer: Bool = false
    @State private var showingPerspectiveScanner: Bool = false

    public init(record: DiscoveryRecord) {
        self.record = record
    }

    private var downloadStage: TrailDownloadStage {
        downloadManager.stage(for: record.trailId)
    }

    private var isBookmarked: Bool {
        bookmarksStore.isBookmarked(trailId: record.trailId)
    }

    private var downloadedLocalTrail: TrailDetail? {
        dataStore.savedTrails.first { $0.id == record.trailId }
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppColors.canvas
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        // MARK: - Hero Placeholder Header
                        heroHeaderView

                        // MARK: - Trail Metadata Summary
                        VStack(alignment: .leading, spacing: 12) {
                            Text(record.title)
                                .font(AppFonts.headlineLarge)
                                .foregroundColor(AppColors.deepInk)

                            // Creator Attribution (PRD §7)
                            HStack(spacing: 6) {
                                Text("Shared by")
                                    .font(AppFonts.bodyMedium)
                                    .foregroundColor(AppColors.onSurfaceVariant)

                                Text("@\(record.username)")
                                    .font(AppFonts.bodyMedium)
                                    .fontWeight(.bold)
                                    .foregroundColor(AppColors.primary)

                                if !record.displayName.isEmpty && record.displayName != record.username {
                                    Text("(\(record.displayName))")
                                        .font(AppFonts.bodySmall)
                                        .foregroundColor(AppColors.secondary)
                                }
                            }

                            // Place and Recording Date
                            HStack(spacing: 8) {
                                if let place = record.placeLabel {
                                    Label(place, systemImage: "mappin.circle.fill")
                                        .font(AppFonts.labelSpatial)
                                        .foregroundColor(AppColors.terracotta)
                                }

                                Text("·")
                                    .foregroundColor(AppColors.outline)

                                Text(formattedDate(record.recordedAt))
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.outline)
                            }

                            Divider()
                                .padding(.vertical, 4)

                            // Introduction
                            let cleanIntro: String? = {
                                if let intro = record.shortDescription,
                                   !intro.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                   !intro.contains("Saved privately on this") {
                                    return intro
                                }
                                if let local = downloadedLocalTrail, !local.subtitle.isEmpty {
                                    return local.subtitle
                                }
                                return nil
                            }()

                            if let intro = cleanIntro {
                                Text(intro)
                                    .font(AppFonts.bodyLarge)
                                    .foregroundColor(AppColors.deepInk.opacity(0.88))
                                    .lineSpacing(4)
                            }

                            // Contents and Capability Summary (PRD §15)
                            capabilitiesSection

                            // Package Size & Status
                            HStack {
                                Label("Package Size: \(formattedBytes(record.packageSizeBytes))", systemImage: "doc.zipper")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.outline)

                                Spacer()

                                if downloadStage == .ready {
                                    Label("Ready for Offline Playback", systemImage: "checkmark.seal.fill")
                                        .font(AppFonts.labelSpatial)
                                        .foregroundColor(AppColors.forestGreen)
                                }
                            }
                            .padding(.top, 4)

                            // MARK: - Secondary Publication Details (PRD §12 & §18)
                            secondaryDetailsSection

                            Spacer(minLength: 120)
                        }
                        .padding(.horizontal, 20)
                    }
                }

                // MARK: - Bottom Primary Action Floating Bar (PRD §12)
                bottomActionBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(AppFonts.labelUI)
                    .foregroundColor(AppColors.deepInk)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Haptics.selection()
                        bookmarksStore.toggleBookmark(record: record)
                    } label: {
                        Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                            .foregroundColor(isBookmarked ? AppColors.terracotta : AppColors.deepInk)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingOpenTrailViewer) {
                if let trail = downloadedLocalTrail {
                    TrailJournalDetailView(trail: trail)
                }
            }
            .fullScreenCover(isPresented: $showingPerspectiveScanner) {
                ScannerView()
            }
        }
    }

    // MARK: - Hero Header View

    private var heroHeaderView: some View {
        ZStack(alignment: .bottomLeading) {
            if let cover = record.resolvedCoverImage(savedTrails: dataStore.savedTrails) {
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 240)
                    .clipped()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(hex: "#1A222D"), Color(hex: "#0F161E")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 80))
                        .foregroundColor(Color.white.opacity(0.06))
                        .offset(x: 60, y: -20)
                }
                .frame(height: 240)
            }

            // Dark gradient scrim for legibility
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.35), Color.black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 240)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 13))
                    Text("COMMUNITY DISCOVERY")
                        .font(AppFonts.labelSpatial)
                        .tracking(1.5)
                }
                .foregroundColor(AppColors.pureWhite.opacity(0.9))

                HStack(spacing: 8) {
                    Text("Revision \(record.revision)")
                        .font(AppFonts.headlineSmall)
                        .foregroundColor(AppColors.pureWhite)

                    if let place = record.placeLabel, !place.isEmpty {
                        Text("·")
                            .foregroundColor(Color.white.opacity(0.6))
                        Text(place)
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.mutedBrass)
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Capabilities Section (PRD §15)

    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Included Capabilities")
                .font(AppFonts.headlineSmall)
                .foregroundColor(AppColors.deepInk)

            let caps = record.capabilities
            VStack(alignment: .leading, spacing: 6) {
                if caps.hasGeographicPath {
                    capabilityRow(title: "Recorded outdoor path", icon: "point.topleft.down.to.point.bottomright.curvepath")
                }
                if caps.hasPlan {
                    capabilityRow(title: "Indoor plan included", icon: "square.split.diagonal.2x2")
                }
                if caps.hasAlignmentAssets {
                    capabilityRow(title: "Indoor alignment data included", icon: "target")
                }
                if caps.hasPhotos {
                    capabilityRow(title: "Spatial photographs", icon: "camera.fill")
                }
                if caps.hasVideos {
                    capabilityRow(title: "360° Video panorama", icon: "video.fill")
                }
                if caps.hasVoice {
                    capabilityRow(title: "Spatial ambient audio memos", icon: "mic.fill")
                }
                capabilityRow(title: "Manual follow-along available", icon: "figure.walk")
            }
        }
        .padding(14)
        .background(AppColors.surfaceContainerHigh)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func capabilityRow(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(AppColors.primary)
                .frame(width: 20)

            Text(title)
                .font(AppFonts.bodySmall)
                .foregroundColor(AppColors.deepInk)
        }
    }

    // MARK: - Secondary Details Section (PRD §12)

    private var secondaryDetailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showingSecondaryDetails.toggle()
                }
            } label: {
                HStack {
                    Text("Publication & Registry Provenance")
                        .font(AppFonts.labelUI)
                        .foregroundColor(AppColors.outline)

                    Spacer()

                    Image(systemName: showingSecondaryDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.outline)
                }
            }

            if showingSecondaryDetails {
                VStack(alignment: .leading, spacing: 6) {
                    provenanceRow(label: "Trail ID", value: record.trailId)
                    provenanceRow(label: "Revision", value: "\(record.revision)")
                    provenanceRow(label: "Package CID", value: record.packageCid)
                    provenanceRow(label: "Publisher Reference", value: record.publisherReference)
                    provenanceRow(label: "Network", value: "Logos / LEZ Decentralized Registry")
                    provenanceRow(label: "Published At", value: formattedDate(record.publishedAt))
                }
                .padding(12)
                .background(AppColors.surfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.top, 6)
    }

    private func provenanceRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(AppColors.outline)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AppColors.deepInk)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Bottom Primary Action Bar

    private var bottomActionBar: some View {
        VStack(spacing: 8) {
            switch downloadStage {
            case .notDownloaded:
                Button {
                    Haptics.medium()
                    downloadManager.startDownload(record: record)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 17))
                        Text("Download trail")
                            .font(AppFonts.labelUI)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColors.primary)
                    .foregroundColor(AppColors.onPrimary)
                    .clipShape(Capsule())
                }

            case .queued, .validating, .importing:
                HStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppColors.primary))
                    Text(downloadStage.displayLabel)
                        .font(AppFonts.labelUI)
                        .foregroundColor(AppColors.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColors.surfaceContainerHigh)
                .clipShape(Capsule())

            case .downloading:
                HStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppColors.primary))
                    Text(downloadStage.displayLabel)
                        .font(AppFonts.labelUI)
                        .foregroundColor(AppColors.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColors.surfaceContainerHigh)
                .clipShape(Capsule())

            case .ready:
                VStack(spacing: 8) {
                    Button {
                        Haptics.medium()
                        showingOpenTrailViewer = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 17))
                            Text("Open trail")
                                .font(AppFonts.labelUI)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.forestGreen)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }

                    // Secondary Action: Record your perspective (PRD §16)
                    Button {
                        recordPerspective()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.metering.matrix")
                            Text("Record your perspective")
                                .font(AppFonts.labelSpatial)
                        }
                        .foregroundColor(AppColors.primary)
                        .padding(.vertical, 4)
                    }

                    Button {
                        downloadManager.removeDownloadedTrail(trailId: record.trailId)
                    } label: {
                        Text("Remove Download")
                            .font(AppFonts.caption)
                            .foregroundColor(AppColors.error)
                    }
                }

            case .failed(let reason):
                VStack(spacing: 6) {
                    Text(reason)
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.error)
                        .multilineTextAlignment(.center)

                    Button {
                        downloadManager.startDownload(record: record)
                    } label: {
                        Text("Try again")
                            .font(AppFonts.labelUI)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(AppColors.primary)
                            .foregroundColor(AppColors.onPrimary)
                            .clipShape(Capsule())
                    }
                }

            case .updateAvailable:
                Button {
                    downloadManager.startDownload(record: record)
                } label: {
                    Text("Update available")
                        .font(AppFonts.labelUI)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.terracotta)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .padding(.top, 10)
        .background(
            AppColors.canvas
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: -4)
        )
    }

    // MARK: - Record Your Perspective Action (PRD §16)

    private func recordPerspective() {
        // Start a new personal trail linked to source trail
        let perspective = TrailDetail(
            id: UUID().uuidString,
            title: "Perspective on \(record.title)",
            subtitle: "Inspired by @\(record.username)",
            placeId: record.placeLabel ?? "shared-place",
            placeName: record.placeLabel ?? "Shared Territory",
            locality: record.placeLabel ?? "Community Discovery",
            wing: "Perspective Recording",
            authorName: dataStore.localProfile.displayName,
            authorRole: "Explorer",
            distanceMeters: 0,
            floorCode: "LVL 00",
            floorTitle: "Ground Floor",
            meshDensity: "LiDAR Route",
            samplingFrequency: "24.6 kHz",
            nodeCount: 0,
            personalNotes: "",
            moments: [],
            visibility: .privateDraft,
            isDraft: true,
            inspiredByTrailId: record.trailId,
            inspiredByNote: "Perspective recorded from public trail “\(record.title)” by @\(record.username)",
            createdAt: Date(),
            updatedAt: Date()
        )
        dataStore.saveDraft(trail: perspective)
        dataStore.activeTrail = perspective
        showingPerspectiveScanner = true
    }

    private func formattedDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return isoString }
        let display = DateFormatter()
        display.dateStyle = .medium
        return display.string(from: date)
    }

    private func formattedBytes(_ bytes: Int) -> String {
        if bytes > 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
        } else {
            return "\(bytes / 1024) KB"
        }
    }
}
