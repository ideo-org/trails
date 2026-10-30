//
//  ReviewPublishTrailView.swift
//  Trails
//
//  Screen 4: Review & Save Trail, compliant with PRD v0.1.0 §8.5 & §9.4.
//  Presents the recorded draft summary, sequence editing, local privacy notice, and save action.
//

import SwiftUI

public struct ReviewPublishTrailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var dataStore = TrailsDataStore.shared

    @State private var trailTitle: String = "Untitled Trail"
    @State private var placeName: String = "My Indoor Space"
    @State private var floorTitle: String = "Ground Floor"
    @State private var personalNotes: String = ""
    @State private var selectedVisibility: TrailVisibility = .privateDraft
    @State private var is3DPreview: Bool = true
    @State private var localMoments: [SpatialMoment] = []
    @State private var editingMoment: SpatialMoment?
    @State private var showingEditMomentSheet: Bool = false
    @State private var showingDiscardAlert: Bool = false
    @State private var isPublishingToLogos: Bool = false
    @State private var publishProgressStage: String = "Preparing"
    @State private var logosPublishReceipt: LogosPublicationReceipt?
    @State private var showingLogosSuccessAlert: Bool = false
    @State private var showingPublicDetailAfterPublish: Bool = false
    @State private var logosPublishError: String?

    private let initialTrail: TrailDetail?

    public init(trail: TrailDetail? = nil) {
        self.initialTrail = trail
    }

    private var activeTrail: TrailDetail {
        if let initial = initialTrail {
            return dataStore.savedTrails.first(where: { $0.id == initial.id }) ?? initial
        }
        return dataStore.activeTrail ?? TrailDetail(
            id: UUID().uuidString,
            title: "Untitled Trail",
            subtitle: "Recorded spatial path",
            placeId: "local-place",
            placeName: "My Indoor Space",
            wing: "Ground Floor",
            authorName: dataStore.localProfile.displayName,
            authorRole: "Explorer",
            distanceMeters: 45,
            isDraft: true
        )
    }

    private var effectiveUsername: String {
        if let u = dataStore.localProfile.username?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
            return u.hasPrefix("@") ? String(u.dropFirst()) : u
        }
        return dataStore.localProfile.displayName.lowercased().replacingOccurrences(of: " ", with: "")
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppColors.canvas
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        // Status Badge
                        HStack {
                            let isPub = activeTrail.isPublished || logosPublishReceipt != nil
                            Image(systemName: isPub ? "checkmark.seal.fill" : "checkmark.shield.fill")
                                .font(.system(size: 13))
                                .foregroundColor(isPub ? AppColors.forestGreen : AppColors.primary)

                            Text(activeTrail.isDraft ? "Private Draft · On Device" : (isPub ? "Published to Network · On Device" : "Saved Trail · On Device"))
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.deepInk)

                            Spacer()

                            Text(activeTrail.samplingFrequency)
                                .font(AppFonts.labelSpatial)
                                .foregroundColor(AppColors.outline)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                        // MARK: - 3D/2D Route Preview Card
                        VStack(spacing: 8) {
                            ZStack {
                                Color(hex: "#FAF8F5")

                                // Spatial floor plan preview
                                SpatialFloorPlanView(floorCode: activeTrail.floorCode)
                                    .frame(height: 220)

                                // Overlay Controls
                                VStack {
                                    HStack {
                                        // 3D / 2D toggle
                                        HStack(spacing: 2) {
                                            Button {
                                                is3DPreview = true
                                            } label: {
                                                Text("3D View")
                                                    .font(AppFonts.labelSpatial)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 5)
                                                    .background(is3DPreview ? AppColors.primary : Color.clear)
                                                    .foregroundColor(is3DPreview ? AppColors.onPrimary : AppColors.deepInk)
                                                    .clipShape(Capsule())
                                            }

                                            Button {
                                                is3DPreview = false
                                            } label: {
                                                Text("2D Plan")
                                                    .font(AppFonts.labelSpatial)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 5)
                                                    .background(!is3DPreview ? AppColors.primary : Color.clear)
                                                    .foregroundColor(!is3DPreview ? AppColors.onPrimary : AppColors.deepInk)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        .padding(3)
                                        .background(AppColors.pureWhite.opacity(0.85))
                                        .clipShape(Capsule())

                                        Spacer()

                                        Text("\(max(1, activeTrail.nodeCount)) NODES")
                                            .font(AppFonts.labelSpatial)
                                            .foregroundColor(AppColors.outline)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(AppColors.pureWhite.opacity(0.85))
                                            .clipShape(Capsule())
                                    }
                                    .padding(12)

                                    Spacer()
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )

                            // Telemetry Stats Bar
                            HStack(spacing: 16) {
                                Label("\(activeTrail.distanceMeters) m walked", systemImage: "figure.walk")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.deepInk)

                                Label("\(localMoments.count) moments", systemImage: "flag.fill")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.terracotta)

                                Label(floorTitle, systemImage: "stairs")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.deepInk)
                            }
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, 16)

                        // MARK: - Trail Metadata Form
                        VStack(alignment: .leading, spacing: 16) {
                            // Title Field
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Trail Title")
                                    .font(AppFonts.labelUI)
                                    .foregroundColor(AppColors.onSurfaceVariant)

                                TextField("Trail Title", text: $trailTitle)
                                    .font(AppFonts.headlineMedium)
                                    .foregroundColor(AppColors.deepInk)
                                    .padding(14)
                                    .background(AppColors.pureWhite)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(AppColors.border, lineWidth: 1)
                                    )
                            }

                            // Place & Floor
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Space / Location")
                                        .font(AppFonts.labelUI)
                                        .foregroundColor(AppColors.onSurfaceVariant)

                                    TextField("e.g. Living Room, Courtyard", text: $placeName)
                                        .font(AppFonts.bodyMedium)
                                        .foregroundColor(AppColors.deepInk)
                                        .padding(12)
                                        .background(AppColors.pureWhite)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(AppColors.border, lineWidth: 1)
                                        )
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Floor Level")
                                        .font(AppFonts.labelUI)
                                        .foregroundColor(AppColors.onSurfaceVariant)

                                    TextField("e.g. Ground Floor", text: $floorTitle)
                                        .font(AppFonts.bodyMedium)
                                        .foregroundColor(AppColors.deepInk)
                                        .padding(12)
                                        .background(AppColors.pureWhite)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(AppColors.border, lineWidth: 1)
                                        )
                                }
                            }

                            // Personal Notes
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Personal Introduction & Observations")
                                    .font(AppFonts.labelUI)
                                    .foregroundColor(AppColors.onSurfaceVariant)

                                TextEditor(text: $personalNotes)
                                    .font(AppFonts.bodyMedium)
                                    .foregroundColor(AppColors.deepInk)
                                    .frame(height: 80)
                                    .padding(10)
                                    .background(AppColors.pureWhite)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(AppColors.border, lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.horizontal, 16)

                        // MARK: - Spatial Moments Sequence Section (PRD §8.3 & §9.3)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Spatial Moments (\(localMoments.count))")
                                    .font(AppFonts.headlineSmall)
                                    .foregroundColor(AppColors.deepInk)

                                Spacer()

                                Text("Tap to edit or reorder")
                                    .font(AppFonts.bodySmall)
                                    .foregroundColor(AppColors.outline)
                            }
                            .padding(.horizontal, 16)

                            if localMoments.isEmpty {
                                HStack {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(AppColors.outline)
                                    Text("No moments tagged during recording.")
                                        .font(AppFonts.bodySmall)
                                        .foregroundColor(AppColors.onSurfaceVariant)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppColors.pureWhite)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .padding(.horizontal, 16)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(localMoments) { moment in
                                        HStack(spacing: 12) {
                                            Circle()
                                                .fill(AppColors.terracotta)
                                                .frame(width: 8, height: 8)

                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 6) {
                                                    Text("\(moment.index). \(moment.title)")
                                                        .font(AppFonts.headlineSmall)
                                                        .foregroundColor(AppColors.deepInk)

                                                    if moment.hasVideo || moment.mediaType == "video" {
                                                        Label("Video", systemImage: "video.fill")
                                                            .font(AppFonts.labelSpatial)
                                                            .foregroundColor(AppColors.terracotta)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(AppColors.terracotta.opacity(0.12))
                                                            .clipShape(Capsule())
                                                    } else if moment.hasPhoto {
                                                        Label("Photo", systemImage: "camera.fill")
                                                            .font(AppFonts.labelSpatial)
                                                            .foregroundColor(AppColors.primary)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(AppColors.surfaceContainerHigh)
                                                            .clipShape(Capsule())
                                                    } else if moment.hasAudio {
                                                        Label("Voice", systemImage: "mic.fill")
                                                            .font(AppFonts.labelSpatial)
                                                            .foregroundColor(AppColors.mutedBrass)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(AppColors.surfaceContainerHigh)
                                                            .clipShape(Capsule())
                                                    }
                                                }

                                                Text(moment.narrative.isEmpty ? moment.subtitle : moment.narrative)
                                                    .font(AppFonts.bodySmall)
                                                    .foregroundColor(AppColors.onSurfaceVariant)
                                                    .lineLimit(2)
                                            }

                                            Spacer()

                                            Button {
                                                editingMoment = moment
                                                showingEditMomentSheet = true
                                            } label: {
                                                Image(systemName: "pencil.circle")
                                                    .font(.system(size: 18))
                                                    .foregroundColor(AppColors.outline)
                                            }

                                            Button {
                                                deleteMoment(moment)
                                            } label: {
                                                Image(systemName: "trash")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(AppColors.error.opacity(0.7))
                                            }
                                        }
                                        .padding(14)
                                        .background(AppColors.pureWhite)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(AppColors.border, lineWidth: 0.5)
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        // MARK: - Privacy & Security Notice (PRD §11.3)
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 16))
                                .foregroundColor(AppColors.primary)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Private On-Device Storage")
                                    .font(AppFonts.headlineSmall)
                                    .foregroundColor(AppColors.deepInk)

                                Text("Saved privately on this device. Trails does not upload this capture.")
                                    .font(AppFonts.bodySmall)
                                    .foregroundColor(AppColors.onSurfaceVariant)
                            }
                        }
                        .padding(14)
                        .background(AppColors.surfaceContainerLow)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 16)

                        // MARK: - Action Buttons
                        VStack(spacing: 12) {
                            if activeTrail.isDraft {
                                Button {
                                    saveFinalTrail()
                                } label: {
                                    HStack {
                                        Text("Save Trail to My Trails")
                                            .font(AppFonts.headlineSmall)
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .bold))
                                    }
                                    .foregroundColor(AppColors.onPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .padding(.horizontal, 20)
                                    .background(AppColors.primary)
                                    .clipShape(Capsule())
                                    .shadow(color: AppColors.primaryDark.opacity(0.25), radius: 8, x: 0, y: 4)
                                }
                            } else {
                                Button {
                                    saveFinalTrail()
                                } label: {
                                    HStack {
                                        Text("Save Changes")
                                            .font(AppFonts.headlineSmall)
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .bold))
                                    }
                                    .foregroundColor(AppColors.onPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .padding(.horizontal, 20)
                                    .background(AppColors.primary)
                                    .clipShape(Capsule())
                                    .shadow(color: AppColors.primaryDark.opacity(0.25), radius: 8, x: 0, y: 4)
                                }
                            }

                            // MARK: - Publish to Logos Network (PRD v0.4.0 §17)
                            if activeTrail.isDownloaded {
                                HStack(spacing: 8) {
                                    Image(systemName: "lock.shield.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(AppColors.secondary)
                                    Text("Downloaded community trails cannot be republished as your own original recording.")
                                        .font(AppFonts.caption)
                                        .foregroundColor(AppColors.onSurfaceVariant)
                                }
                                .padding(12)
                                .background(AppColors.surfaceContainerHigh)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else if activeTrail.isPublished || logosPublishReceipt != nil {
                                VStack(spacing: 12) {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundColor(AppColors.forestGreen)
                                        Text("Published to Logos Network")
                                            .font(AppFonts.headlineSmall)
                                            .foregroundColor(AppColors.forestGreen)
                                        Spacer()
                                        Image(systemName: "globe.europe.africa.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(AppColors.forestGreen)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .padding(.horizontal, 20)
                                    .background(AppColors.forestGreen.opacity(0.12))
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(AppColors.forestGreen.opacity(0.35), lineWidth: 1)
                                    )

                                    if let cid = logosPublishReceipt?.packageCid ?? activeTrail.publishedPackageCid {
                                        HStack(spacing: 6) {
                                            Text("CID:")
                                                .font(AppFonts.caption)
                                                .foregroundColor(AppColors.outline)
                                            Text(cid)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(AppColors.onSurfaceVariant)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(AppColors.surfaceContainerLow)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }

                                    Button {
                                        publishToLogos()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 12))
                                            Text(isPublishingToLogos ? "Publishing Update (\(publishProgressStage))..." : "Publish Update (New Revision)")
                                                .font(AppFonts.labelUI)
                                                .foregroundColor(AppColors.secondary)
                                        }
                                        .padding(.top, 2)
                                    }
                                    .disabled(isPublishingToLogos)
                                }
                            } else {
                                Button {
                                    publishToLogos()
                                } label: {
                                    HStack {
                                        Image(systemName: "globe.europe.africa.fill")
                                            .font(.system(size: 15))
                                        Text(isPublishingToLogos ? "Publishing (\(publishProgressStage))..." : "Publish to Logos Network")
                                            .font(AppFonts.headlineSmall)
                                        Spacer()
                                        if isPublishingToLogos {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: AppColors.onPrimary))
                                        } else {
                                            Image(systemName: "arrow.up.circle.fill")
                                                .font(.system(size: 16))
                                        }
                                    }
                                    .foregroundColor(AppColors.onPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .padding(.horizontal, 20)
                                    .background(Color(hex: "#1B2A32"))
                                    .clipShape(Capsule())
                                    .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
                                }
                                .disabled(isPublishingToLogos)
                            }

                            if activeTrail.isDraft {
                                Button {
                                    saveAsDraft()
                                } label: {
                                    Text("Keep on Device as Draft")
                                        .font(AppFonts.labelUI)
                                        .foregroundColor(AppColors.primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(AppColors.pureWhite)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule().stroke(AppColors.border, lineWidth: 1)
                                        )
                                }

                                Button {
                                    showingDiscardAlert = true
                                } label: {
                                    Text("Discard Recording")
                                        .font(AppFonts.labelUI)
                                        .foregroundColor(AppColors.error)
                                        .padding(.top, 4)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle(activeTrail.isDraft ? "Review Trail" : "Trail Details & Publishing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                            Text("Close")
                        }
                        .font(AppFonts.labelUI)
                        .foregroundColor(AppColors.deepInk)
                    }
                }
            }
            .sheet(item: $editingMoment) { moment in
                EditMomentSheet(moment: moment) { updated in
                    if let idx = localMoments.firstIndex(where: { $0.id == updated.id }) {
                        localMoments[idx] = updated
                    }
                    editingMoment = nil
                }
            }
            .alert("Discard Recording?", isPresented: $showingDiscardAlert) {
                Button("Discard", role: .destructive) {
                    dataStore.deleteTrail(id: activeTrail.id)
                    dismiss()
                }
                Button("Keep", role: .cancel) {}
            } message: {
                Text("This will delete the unsaved scan from your device.")
            }
            .alert("Published to Logos", isPresented: $showingLogosSuccessAlert) {
                Button("View public trail") {
                    showingPublicDetailAfterPublish = true
                }
                Button("Done", role: .cancel) {
                    dismiss()
                }
            } message: {
                if let receipt = logosPublishReceipt {
                    Text("Trail published to Logos!\n\nTrail ID:\n\(receipt.trailId)\n\nRevision: \(receipt.revision)\n\nPackage CID:\n\(receipt.packageCid)\n\nTx Reference:\n\(receipt.transactionReference)")
                } else {
                    Text("Trail successfully recorded on the decentralized registry.")
                }
            }
            .sheet(isPresented: $showingPublicDetailAfterPublish) {
                if let receipt = logosPublishReceipt {
                    let disc = DiscoveryRecord(
                        trailId: receipt.trailId,
                        revision: receipt.revision,
                        title: trailTitle,
                        shortDescription: personalNotes,
                        creatorId: "creator-\(dataStore.localProfile.id)",
                        username: effectiveUsername,
                        displayName: dataStore.localProfile.displayName,
                        publisherReference: receipt.transactionReference,
                        recordedAt: ISO8601DateFormatter().string(from: Date()),
                        publishedAt: ISO8601DateFormatter().string(from: Date()),
                        placeLabel: placeName,
                        capabilities: LogosCapabilities(hasPhotos: true, hasGeographicPath: true),
                        packageCid: receipt.packageCid,
                        packageSizeBytes: receipt.packageSizeBytes,
                        listed: true
                    )
                    PublicTrailDetailView(record: disc)
                }
            }
            .onAppear {
                syncWithActiveTrail()
            }
        }
    }

    private func syncWithActiveTrail() {
        let t = activeTrail
        self.trailTitle = t.title
        self.placeName = t.placeName
        self.floorTitle = t.floorTitle
        self.personalNotes = t.personalNotes
        self.selectedVisibility = t.visibility
        self.localMoments = t.moments
    }

    private func saveFinalTrail() {
        var updated = activeTrail
        updated.title = trailTitle.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled Trail" : trailTitle
        updated.placeName = placeName
        updated.floorTitle = floorTitle
        updated.personalNotes = personalNotes
        updated.visibility = selectedVisibility
        updated.moments = localMoments
        dataStore.saveFinalTrail(trail: updated)
        dismiss()
    }

    private func publishToLogos() {
        guard !activeTrail.isDownloaded else {
            self.logosPublishError = "Downloaded community trails cannot be republished as your own original recording."
            return
        }

        var updated = activeTrail
        updated.title = trailTitle.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled Trail" : trailTitle
        updated.placeName = placeName
        updated.floorTitle = floorTitle
        updated.personalNotes = personalNotes
        updated.visibility = selectedVisibility
        updated.moments = localMoments
        dataStore.saveFinalTrail(trail: updated)

        Task {
            isPublishingToLogos = true
            defer { isPublishingToLogos = false }
            let client = TrailsLogosClient.shared

            // Stage 1: Preparing
            publishProgressStage = "Preparing"
            let isOnline = await client.checkHealth()
            if !isOnline {
                self.logosPublishError = "Cannot connect to Trails Logos node at \(client.baseURL)"
                return
            }

            // Construct compliant manifest (PRD §17 & §18)
            let isoNow = ISO8601DateFormatter().string(from: updated.createdAt)
            var placeDict: [String: Any] = [
                "name": updated.placeName,
                "locality": updated.locality
            ]
            if let lat = updated.latitude, let lon = updated.longitude {
                placeDict["geographicAnchor"] = [
                    "latitude": lat,
                    "longitude": lon
                ]
            }
            let manifest: [String: Any] = [
                "schemaVersion": "1.0.0",
                "trailId": updated.id,
                "revision": 1,
                "title": updated.title,
                "introduction": updated.personalNotes.isEmpty ? updated.subtitle : updated.personalNotes,
                "creatorDisplayName": dataStore.localProfile.displayName,
                "creatorUsername": effectiveUsername,
                "creatorId": "creator-\(dataStore.localProfile.id)",
                "recordedAt": isoNow,
                "place": placeDict,
                "capabilities": [
                    "hasPhotos": updated.photoCount > 0,
                    "hasVideos": updated.videoCount > 0,
                    "hasVoice": updated.audioCount > 0,
                    "hasText": true,
                    "hasGeographicPath": updated.hasGeographicTrack,
                    "hasLocalSpatialPath": true,
                    "hasSpatialGeometry": false,
                    "hasPlan": false,
                    "hasAlignmentAssets": false
                ],
                "assets": [],
                "moments": updated.moments.enumerated().map { idx, m in
                    [
                        "id": m.id,
                        "originalOrder": idx + 1,
                        "startedAt": isoNow,
                        "text": m.narrative,
                        "assetIds": []
                    ]
                }
            ]

            guard let manifestJson = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) else {
                self.logosPublishError = "Failed to construct package manifest"
                return
            }

            var entries = [
                TrailZipArchiver.FileEntry(name: "manifest.json", data: manifestJson)
            ]
            let packageDir = TrailPackageStore.shared.trailDirectory(for: updated.id)
            if let momentsData = try? Data(contentsOf: packageDir.appendingPathComponent("moments.json")) {
                entries.append(TrailZipArchiver.FileEntry(name: "moments.json", data: momentsData))
            }
            if let samplesData = try? Data(contentsOf: packageDir.appendingPathComponent("tracking/samples.json")) {
                entries.append(TrailZipArchiver.FileEntry(name: "tracking/samples.json", data: samplesData))
            }
            let packageZip = TrailZipArchiver.createZip(entries: entries)

            do {
                // Stage 2: Uploading
                publishProgressStage = "Uploading"
                try await Task.sleep(nanoseconds: 200_000_000)

                // Stage 3: Verifying storage
                publishProgressStage = "Verifying storage"
                try await Task.sleep(nanoseconds: 200_000_000)

                // Stage 4: Registering on LEZ
                publishProgressStage = "Registering on LEZ"
                let receipt = try await client.publishPackageZip(zipData: packageZip)

                // Stage 5: Confirming
                publishProgressStage = "Confirming"
                try await Task.sleep(nanoseconds: 200_000_000)

                // Stage 6: Published
                publishProgressStage = "Published"
                self.logosPublishReceipt = receipt

                // Update and persist trail publication metadata
                updated.isPublished = true
                updated.publishedAt = Date()
                updated.publishedRevision = receipt.revision
                updated.publishedPackageCid = receipt.packageCid
                updated.publishedTransactionRef = receipt.transactionReference
                dataStore.saveFinalTrail(trail: updated)

                self.showingLogosSuccessAlert = true
            } catch {
                self.logosPublishError = error.localizedDescription
            }
        }
    }

    private func saveAsDraft() {
        var updated = activeTrail
        updated.title = trailTitle.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled Trail" : trailTitle
        updated.placeName = placeName
        updated.floorTitle = floorTitle
        updated.personalNotes = personalNotes
        updated.visibility = selectedVisibility
        updated.moments = localMoments
        dataStore.saveDraft(trail: updated)
        dismiss()
    }

    private func deleteMoment(_ moment: SpatialMoment) {
        localMoments.removeAll { $0.id == moment.id }
        // Re-index remaining moments
        for (i, _) in localMoments.enumerated() {
            localMoments[i].index = i + 1
        }
    }
}

// MARK: - Edit Moment Quick Sheet (PRD §8.3 & §9.3 MOM-06 & MOM-07)

private struct EditMomentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var note: String
    let moment: SpatialMoment
    let onSave: (SpatialMoment) -> Void

    init(moment: SpatialMoment, onSave: @escaping (SpatialMoment) -> Void) {
        self.moment = moment
        self.onSave = onSave
        _label = State(initialValue: moment.title)
        _note = State(initialValue: moment.narrative)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit Moment \(moment.index)")
                    .font(AppFonts.headlineSmall)
                    .foregroundColor(AppColors.deepInk)

                TextField("Moment label", text: $label)
                    .font(AppFonts.bodyMedium)
                    .padding(12)
                    .background(AppColors.surfaceContainerLow)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                TextField("Observation / note", text: $note)
                    .font(AppFonts.bodyMedium)
                    .padding(12)
                    .background(AppColors.surfaceContainerLow)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer()

                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(AppFonts.labelUI)
                    .foregroundColor(AppColors.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColors.surfaceContainerHigh)
                    .clipShape(Capsule())

                    Button {
                        var m = moment
                        m.title = label.trimmingCharacters(in: .whitespaces).isEmpty ? moment.title : label
                        m.narrative = note
                        onSave(m)
                        dismiss()
                    } label: {
                        Text("Save")
                    }
                    .font(AppFonts.labelUI)
                    .foregroundColor(AppColors.onPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
                }
            }
            .padding(20)
            .background(AppColors.canvas.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .presentationDetents([.height(280)])
    }
}
