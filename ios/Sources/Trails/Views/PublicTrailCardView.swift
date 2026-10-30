//
//  PublicTrailCardView.swift
//  Trails
//
//  Reuses the existing Journal card layout for remote/community trails (PRD v0.4.0 §9).
//  Fields: Actual title, cover or neutral placeholder, creator attribution,
//  place label, recording date, content indicators, bookmark control, and downloaded badge.
//

import SwiftUI

public struct PublicTrailCardView: View {
    public let record: DiscoveryRecord
    public let onSelect: () -> Void
    public let onSelectCreator: (String) -> Void

    @ObservedObject private var bookmarksStore = BookmarksStore.shared
    @ObservedObject private var downloadManager = TrailDownloadManager.shared

    public init(
        record: DiscoveryRecord,
        onSelect: @escaping () -> Void,
        onSelectCreator: @escaping (String) -> Void
    ) {
        self.record = record
        self.onSelect = onSelect
        self.onSelectCreator = onSelectCreator
    }

    private var isBookmarked: Bool {
        bookmarksStore.isBookmarked(trailId: record.trailId)
    }

    private var isDownloaded: Bool {
        downloadManager.isLocallyDownloaded(trailId: record.trailId)
    }

    private var downloadStage: TrailDownloadStage {
        downloadManager.stage(for: record.trailId)
    }

    public var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Card Header (Cover Image or Neutral Limestone Placeholder)
                ZStack(alignment: .topTrailing) {
                    // Neutral limestone placeholder (PRD §9 & §20: Missing cover -> Neutral placeholder)
                    ZStack {
                        LinearGradient(
                            colors: [Color(hex: "#EFECE6"), Color(hex: "#E3DFD5")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )

                        VStack(spacing: 8) {
                            Image(systemName: record.discoveryAnchor != nil ? "point.topleft.down.to.point.bottomright.curvepath" : "waveform.path")
                                .font(.system(size: 32))
                                .foregroundColor(AppColors.secondary.opacity(0.85))

                            if let place = record.placeLabel {
                                Text(place.uppercased())
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.primary.opacity(0.7))
                                    .tracking(1.2)
                            }
                        }
                    }
                    .frame(height: 160)

                    // Top Badges & Controls Row
                    HStack {
                        if isDownloaded {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 11))
                                Text("DOWNLOADED")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColors.forestGreen)
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(0.12), radius: 3)
                        } else if downloadStage.isBusy {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.6)
                                Text(downloadStage.displayLabel.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColors.terracotta)
                            .clipShape(Capsule())
                        }

                        Spacer()

                        // Bookmark Control (PRD §11)
                        Button {
                            Haptics.selection()
                            bookmarksStore.toggleBookmark(record: record)
                        } label: {
                            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(isBookmarked ? AppColors.terracotta : AppColors.deepInk)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.92))
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(12)
                }

                // MARK: - Card Content Details
                VStack(alignment: .leading, spacing: 8) {
                    // Title
                    Text(record.title)
                        .font(AppFonts.headlineSmall)
                        .foregroundColor(AppColors.deepInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Creator Attribution (PRD §7 & §9)
                    Button {
                        onSelectCreator(record.creatorId)
                    } label: {
                        HStack(spacing: 4) {
                            Text("By")
                                .font(AppFonts.bodySmall)
                                .foregroundColor(AppColors.onSurfaceVariant)

                            Text("@\(record.username)")
                                .font(AppFonts.bodySmall)
                                .fontWeight(.semibold)
                                .foregroundColor(AppColors.primary)

                            if !record.displayName.isEmpty && record.displayName != record.username {
                                Text("(\(record.displayName))")
                                    .font(AppFonts.caption)
                                    .foregroundColor(AppColors.secondary)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Short Description (if present)
                    if let desc = record.shortDescription, !desc.isEmpty {
                        Text(desc)
                            .font(AppFonts.bodySmall)
                            .foregroundColor(AppColors.onSurfaceVariant)
                            .lineLimit(2)
                    }

                    Divider()
                        .padding(.vertical, 2)

                    // Content Indicators & Package Size (PRD §9)
                    HStack(spacing: 10) {
                        contentIndicators

                        Spacer()

                        Text(formattedPackageSize)
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.outline)
                    }
                }
                .padding(16)
                .background(AppColors.surfaceContainerLow)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
            .padding(.horizontal, 20)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var formattedPackageSize: String {
        let bytes = record.packageSizeBytes
        if bytes > 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
        } else {
            return "\(bytes / 1024) KB"
        }
    }

    private var contentIndicators: some View {
        HStack(spacing: 8) {
            let caps = record.capabilities

            if caps.hasPhotos {
                Image(systemName: "camera.fill")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondary)
            }
            if caps.hasVideos {
                Image(systemName: "video.fill")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondary)
            }
            if caps.hasVoice {
                Image(systemName: "mic.fill")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondary)
            }
            if caps.hasLocalSpatialPath || caps.hasSpatialGeometry {
                Image(systemName: "square.3.layers.3d.down.right")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondary)
            }
            if caps.hasAlignmentAssets {
                Image(systemName: "target")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondary)
            }
        }
    }
}
