//
//  CapturedMomentsTrayView.swift
//  Trails
//
//  In-capture Moments Tray (PRD v0.2.1 §17).
//  Enables creators to review, caption, preview, and prune moments
//  during an active trail recording without leaving the trail.
//

import SwiftUI
import AVKit

public struct CapturedMomentsTrayView: View {
    public let trailId: String
    @Binding public var moments: [SpatialMoment]
    public let onUpdateMoment: (SpatialMoment) -> Void
    public let onDeleteMoment: (String) -> Void
    public let onDismiss: () -> Void

    @State private var editingMoment: SpatialMoment?
    @State private var previewMoment: SpatialMoment?
    @State private var momentPendingDelete: SpatialMoment?
    @State private var showDeleteConfirm = false

    public var body: some View {
        NavigationStack {
            ZStack {
                AppColors.canvas.ignoresSafeArea()

                if moments.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.macro")
                            .font(.system(size: 36))
                            .foregroundColor(AppColors.secondary)
                        Text("No moments recorded yet")
                            .font(AppFonts.headlineSmall)
                            .foregroundColor(AppColors.primary)
                        Text("Capture a photo, video, voice note, or written thought during your journey.")
                            .font(AppFonts.bodySmall)
                            .foregroundColor(AppColors.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(moments) { moment in
                                momentRow(moment)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Captured Moments (\(moments.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .font(AppFonts.labelUI)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.primary)
                }
            }
            .sheet(item: $editingMoment) { moment in
                EditCaptionSheet(moment: moment) { updated in
                    if let idx = moments.firstIndex(where: { $0.id == updated.id }) {
                        moments[idx] = updated
                        onUpdateMoment(updated)
                    }
                }
            }
            .sheet(item: $previewMoment) { moment in
                MomentPreviewSheet(trailId: trailId, moment: moment)
            }
            .alert("Delete Moment?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let m = momentPendingDelete {
                        moments.removeAll { $0.id == m.id }
                        onDeleteMoment(m.id)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete “\(momentPendingDelete?.title ?? "this moment")”? This cannot be undone.")
            }
        }
    }

    private func momentRow(_ moment: SpatialMoment) -> some View {
        HStack(spacing: 14) {
            // Thumbnail
            thumbnailView(for: moment)
                .frame(width: 72, height: 72)
                .cornerRadius(12)
                .onTapGesture {
                    previewMoment = moment
                }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(moment.index). \(moment.title)")
                        .font(AppFonts.labelUI)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.primary)
                        .lineLimit(1)

                    mediaBadge(for: moment)
                }

                Text(moment.narrative.isEmpty ? moment.subtitle : moment.narrative)
                    .font(AppFonts.bodySmall)
                    .foregroundColor(AppColors.onSurfaceVariant)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(moment.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.outline)

                    if moment.distanceAlongPathMeters > 0 {
                        Text("+\(moment.distanceAlongPathMeters)m")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.secondary)
                    }
                }
            }

            Spacer()

            // Actions Menu
            Menu {
                Button {
                    previewMoment = moment
                } label: {
                    Label("Preview", systemImage: "eye")
                }

                Button {
                    editingMoment = moment
                } label: {
                    Label("Edit Note", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    momentPendingDelete = moment
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .foregroundColor(AppColors.onSurfaceVariant)
                    .frame(width: 36, height: 36)
                    .background(AppColors.surfaceContainerLow)
                    .clipShape(Circle())
            }
        }
        .padding(14)
        .background(AppColors.surfaceContainerLowest)
        .cornerRadius(16)
        .contentShape(Rectangle())
        .onTapGesture {
            previewMoment = moment
        }
    }

    @ViewBuilder
    private func thumbnailView(for moment: SpatialMoment) -> some View {
        if moment.hasPhoto, let photoURL = moment.resolvedPhotoURL(trailId: trailId),
           let uiImage = UIImage(contentsOfFile: photoURL.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipped()
        } else if moment.hasVideo, let thumbURL = moment.resolvedVideoThumbnailURL(trailId: trailId),
                  let uiImage = UIImage(contentsOfFile: thumbURL.path) {
            ZStack {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .clipped()
                Image(systemName: "play.circle.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 18))
            }
        } else if let assetName = moment.photoAssetName {
            Image(assetName)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            ZStack {
                AppColors.surfaceContainerHigh
                Image(systemName: iconName(for: moment))
                    .foregroundColor(AppColors.primary)
                    .font(.system(size: 20))
            }
        }
    }

    private func mediaBadge(for moment: SpatialMoment) -> some View {
        HStack(spacing: 3) {
            Image(systemName: iconName(for: moment))
                .font(.system(size: 8))
            Text(moment.mediaType.capitalized)
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(AppColors.surfaceContainerHigh)
        .clipShape(Capsule())
        .foregroundColor(AppColors.primary)
    }

    private func iconName(for moment: SpatialMoment) -> String {
        switch moment.mediaType {
        case "video": return "video.fill"
        case "photo": return "camera.fill"
        case "voice": return "mic.fill"
        default: return "note.text"
        }
    }
}

// MARK: - Edit Caption Sheet

private struct EditCaptionSheet: View {
    @State var moment: SpatialMoment
    let onSave: (SpatialMoment) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MOMENT TITLE")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.outline)
                    TextField("Title", text: $moment.title)
                        .font(AppFonts.bodyMedium)
                        .padding(12)
                        .background(AppColors.surfaceContainerLow)
                        .cornerRadius(10)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("OBSERVATION / NOTE")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.outline)
                    TextEditor(text: $moment.narrative)
                        .font(AppFonts.bodyMedium)
                        .frame(height: 120)
                        .padding(8)
                        .background(AppColors.surfaceContainerLow)
                        .cornerRadius(10)
                }

                Spacer()
            }
            .padding(20)
            .background(AppColors.canvas.ignoresSafeArea())
            .navigationTitle("Edit Moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(moment)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Moment Preview Sheet

struct MomentPreviewSheet: View {
    let trailId: String
    let moment: SpatialMoment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioManager = AudioManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if moment.hasPhoto, let photoURL = moment.resolvedPhotoURL(trailId: trailId),
                   let uiImage = UIImage(contentsOfFile: photoURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                } else if moment.hasVideo, let videoURL = moment.resolvedVideoURL(trailId: trailId) {
                    VideoPlayer(player: AVPlayer(url: videoURL))
                        .ignoresSafeArea()
                } else if moment.hasAudio, let audioURL = moment.resolvedAudioURL(trailId: trailId) {
                    VStack(spacing: 20) {
                        Image(systemName: "waveform")
                            .font(.system(size: 64))
                            .foregroundColor(AppColors.mutedBrass)
                        Text(moment.title)
                            .font(AppFonts.headlineMedium)
                            .foregroundColor(.white)
                        Text(moment.audioDuration ?? "Audio Moment")
                            .font(AppFonts.labelMetric)
                            .foregroundColor(AppColors.mutedBrass)

                        Button {
                            if audioManager.isPlaying {
                                audioManager.pausePlayback()
                            } else {
                                audioManager.playAudio(url: audioURL)
                            }
                        } label: {
                            Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 56))
                                .foregroundColor(.white)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Text(moment.title)
                            .font(AppFonts.headlineMedium)
                            .foregroundColor(.white)
                        Text("“\(moment.narrative)“")
                            .font(AppFonts.bodyMedium)
                            .foregroundColor(Color.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        audioManager.stopPlayback()
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}
