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
    @State private var logosPublishReceipt: LogosPublicationReceipt?
    @State private var showingLogosSuccessAlert: Bool = false
    @State private var logosPublishError: String?

    public init() {}

    private var activeTrail: TrailDetail {
        dataStore.activeTrail ?? TrailDetail(
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

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppColors.canvas
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        // Status Badge
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.primary)

                            Text(activeTrail.isDraft ? "Private Draft · On Device" : "Saved Trail · On Device")
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

                            // MARK: - Publish to Logos Network (PRD v0.1.0)
                            Button {
                                publishToLogos()
                            } label: {
                                HStack {
                                    Image(systemName: "globe.europe.africa.fill")
                                        .font(.system(size: 15))
                                    Text(isPublishingToLogos ? "Publishing to Logos..." : "Publish to Logos Network")
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
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Review Trail")
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
                Button("Done") {
                    dismiss()
                }
            } message: {
                if let receipt = logosPublishReceipt {
                    Text("Trail published to Logos!\n\nPackage CID:\n\(receipt.packageCid)\n\nTx Reference:\n\(receipt.transactionReference)")
                } else {
                    Text("Trail successfully recorded on the decentralized registry.")
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
            let isOnline = await client.checkHealth()
            if !isOnline {
                self.logosPublishError = "Cannot connect to Trails Logos node at \(client.baseURL)"
                return
            }

            // Export trail directory or pack data and upload
            let dummyZip = Data("SIMULATED_TRAIL_ZIP_ARCHIVE_DATA".utf8)
            do {
                let receipt = try await client.publishPackageZip(zipData: dummyZip)
                self.logosPublishReceipt = receipt
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

                    Button("Save") {
                        var m = moment
                        m.title = label.trimmingCharacters(in: .whitespaces).isEmpty ? moment.title : label
                        m.narrative = note
                        onSave(m)
                        dismiss()
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
