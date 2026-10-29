//
//  FinishTrailReviewSheet.swift
//  Trails
//
//  Celebratory Trail Summary & Finalize Sheet for Trails v0.2.1.
//  Enables the creator to name their trail, add field reflections,
//  inspect captured metrics, and confirm saving with high tactile feedback.
//

import SwiftUI

public struct FinishTrailReviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let trailId: String
    let initialTitle: String
    let elapsedSeconds: Int
    let walkedMeters: Int
    let moments: [SpatialMoment]
    let hasIndoorScan: Bool
    let onSave: (_ title: String, _ personalNotes: String, _ coverMomentId: String?) -> Void
    let onKeepRecording: () -> Void

    @State private var title: String = ""
    @State private var personalNotes: String = ""
    @State private var selectedCoverMomentId: String? = nil

    public init(
        trailId: String,
        initialTitle: String,
        elapsedSeconds: Int,
        walkedMeters: Int,
        moments: [SpatialMoment],
        hasIndoorScan: Bool,
        onSave: @escaping (_ title: String, _ personalNotes: String, _ coverMomentId: String?) -> Void,
        onKeepRecording: @escaping () -> Void
    ) {
        self.trailId = trailId
        self.initialTitle = initialTitle
        self.elapsedSeconds = elapsedSeconds
        self.walkedMeters = walkedMeters
        self.moments = moments
        self.hasIndoorScan = hasIndoorScan
        self.onSave = onSave
        self.onKeepRecording = onKeepRecording
        _title = State(initialValue: initialTitle)
        _selectedCoverMomentId = State(initialValue: moments.first(where: { $0.hasPhoto || $0.hasVideo })?.id)
    }

    private var formattedDuration: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppColors.canvas
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        // MARK: - Header Hero Tag
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("JOURNAL ENTRY")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.secondary)
                                    .tracking(1.5)
                                Text("Name your trail")
                                    .font(AppFonts.headlineMedium)
                                    .foregroundColor(AppColors.primary)
                            }

                            Spacer()

                            Text(formattedDuration)
                                .font(AppFonts.labelMetric)
                                .foregroundColor(AppColors.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AppColors.surfaceContainerLow)
                                .clipShape(Capsule())
                        }
                        .padding(.top, 4)

                        // MARK: - Title Input
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TRAIL TITLE")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.outline)
                                .tracking(1.0)

                            TextField("e.g., Morning Walk through Central Atrium", text: $title)
                                .font(AppFonts.headlineSmall)
                                .foregroundColor(AppColors.primary)
                                .padding(14)
                                .background(AppColors.pureWhite)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(AppColors.outlineVariant.opacity(0.5), lineWidth: 1)
                                )
                        }

                        // MARK: - Journey Metrics Ribbon
                        VStack(alignment: .leading, spacing: 8) {
                            Text("JOURNEY SUMMARY")
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.outline)
                                .tracking(1.0)

                            HStack(spacing: 8) {
                                metricChip(icon: "figure.walk", label: "\(walkedMeters)m", sub: "Walked")
                                metricChip(icon: "photo.stack", label: "\(moments.count)", sub: "Moments")
                                metricChip(
                                    icon: hasIndoorScan ? "cube.transparent" : "location",
                                    label: hasIndoorScan ? "3D Mesh" : "GPS",
                                    sub: hasIndoorScan ? "LiDAR" : "Track"
                                )
                            }
                        }

                        // MARK: - Cover Selection Carousel (if photos exist)
                        let visualMoments = moments.filter { $0.hasPhoto || $0.hasVideo }
                        if !visualMoments.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("SELECT COVER IMAGE")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.outline)
                                    .tracking(1.0)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(visualMoments) { moment in
                                            coverThumbnailButton(for: moment)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        // MARK: - Personal Notes / Reflection
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("FIELD NOTES / REFLECTION")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.outline)
                                    .tracking(1.0)
                                Spacer()
                                Text("Optional")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.outline)
                            }

                            ZStack(alignment: .topLeading) {
                                if personalNotes.isEmpty {
                                    Text("“What would you show someone who wasn’t here?”")
                                        .font(AppFonts.bodyMedium)
                                        .italic()
                                        .foregroundColor(AppColors.outline.opacity(0.7))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                }

                                TextEditor(text: $personalNotes)
                                    .font(AppFonts.bodyMedium)
                                    .foregroundColor(AppColors.deepInk)
                                    .frame(minHeight: 90)
                                    .padding(8)
                                    .background(Color.clear)
                            }
                            .background(AppColors.pureWhite)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(AppColors.outlineVariant.opacity(0.5), lineWidth: 1)
                            )
                        }

                        Spacer(minLength: 80)
                    }
                    .padding(20)
                }

                // MARK: - Bottom Actions Bar
                VStack(spacing: 10) {
                    Button {
                        Haptics.success()
                        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? initialTitle : title
                        onSave(finalTitle, personalNotes, selectedCoverMomentId)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Text("Save to My Trails")
                                .font(AppFonts.headlineSmall)
                                .fontWeight(.semibold)
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppColors.primary)
                        .clipShape(Capsule())
                        .shadow(color: AppColors.primary.opacity(0.25), radius: 8, x: 0, y: 4)
                    }

                    Button {
                        Haptics.light()
                        onKeepRecording()
                        dismiss()
                    } label: {
                        Text("Keep Recording")
                            .font(AppFonts.labelUI)
                            .foregroundColor(AppColors.primary)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .background(
                    LinearGradient(
                        colors: [AppColors.canvas.opacity(0), AppColors.canvas.opacity(0.95), AppColors.canvas],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onKeepRecording()
                        dismiss()
                    }
                    .foregroundColor(AppColors.primary)
                }
            }
        }
    }

    // MARK: - Cover Thumbnail Button

    private func coverThumbnailButton(for moment: SpatialMoment) -> some View {
        let isSelected = (selectedCoverMomentId == moment.id)

        return Button {
            Haptics.selection()
            selectedCoverMomentId = moment.id
        } label: {
            ZStack(alignment: .topTrailing) {
                if let photoURL = moment.resolvedPhotoURL(trailId: trailId),
                   let image = UIImage(contentsOfFile: photoURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipped()
                } else if let thumbURL = moment.resolvedVideoThumbnailURL(trailId: trailId),
                          let thumb = UIImage(contentsOfFile: thumbURL.path) {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(AppColors.surfaceContainer)
                        .frame(width: 80, height: 80)
                }

                if isSelected {
                    Circle()
                        .fill(AppColors.primary)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .padding(4)
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? AppColors.primary : Color.clear, lineWidth: 2.5)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Metric Chip

    private func metricChip(icon: String, label: String, sub: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(AppColors.secondary)
                .frame(width: 36, height: 36)
                .background(AppColors.surfaceContainerLow)
                .clipShape(Circle())

            Text(label)
                .font(AppFonts.labelMetric)
                .fontWeight(.bold)
                .foregroundColor(AppColors.primary)
                .lineLimit(1)

            Text(sub)
                .font(AppFonts.labelSpatial)
                .foregroundColor(AppColors.outline)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(AppColors.pureWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.outlineVariant.opacity(0.3), lineWidth: 1)
        )
    }
}
