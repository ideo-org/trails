import SwiftUI
import SwiftData

struct TrailsLibraryView: View {
    @Query(sort: \TrailsCapture.createdAt, order: .reverse) private var captures: [TrailsCapture]
    @Environment(\.modelContext) private var modelContext

    // MARK: Select-mode state
    @State private var isSelectMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showDeleteConfirm = false

    var body: some View {
        Group {
            if captures.isEmpty {
                emptyState
            } else {
                scrollContent
            }
        }
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { navBarItems }
        .safeAreaInset(edge: .bottom) {
            if isSelectMode {
                deleteBar
            }
        }
        .confirmationDialog(
            "Delete \(selectedIDs.count) scan\(selectedIDs.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the scans and their files from your device.")
        }
        .task {
            Analytics.trackScreenView("TrailsLibraryView")
        }
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(captures) { capture in
                    if isSelectMode {
                        // Tappable row — no NavigationLink in select mode
                        Button {
                            toggleSelection(capture.id)
                        } label: {
                            rowContent(capture: capture)
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        NavigationLink {
                            TrailsCaptureDetailView(capture: capture)
                        } label: {
                            rowContent(capture: capture)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Divider()
                        .background(AppColors.border)
                        .padding(.leading, 16 + 90 + 14)
                }
            }
            .padding(.vertical, 8)
            // Leave space for the fixed delete bar when active
            .padding(.bottom, isSelectMode ? 72 : 0)
        }
    }

    @ViewBuilder
    private func rowContent(capture: TrailsCapture) -> some View {
        HStack(spacing: 0) {
            // Checkmark column (select mode only)
            if isSelectMode {
                checkmark(for: capture.id)
                    .padding(.leading, 16)
                    .padding(.trailing, 10)
            }

            TrailsCaptureRow(capture: capture)
                // Dim slightly when another row in the same group is selected
                .opacity(isSelectMode && !selectedIDs.isEmpty && !selectedIDs.contains(capture.id) ? 0.55 : 1)
                .animation(.easeInOut(duration: 0.15), value: selectedIDs)
        }
        .contentShape(Rectangle())
        .background(
            selectedIDs.contains(capture.id)
                ? AppColors.accent.opacity(0.07)
                : Color.clear
        )
        .animation(.easeInOut(duration: 0.15), value: selectedIDs)
    }

    @ViewBuilder
    private func checkmark(for id: UUID) -> some View {
        let selected = selectedIDs.contains(id)
        ZStack {
            Circle()
                .fill(selected ? AppColors.accent : Color.clear)
                .frame(width: 24, height: 24)
            Circle()
                .stroke(selected ? AppColors.accent : AppColors.textTertiary.opacity(0.5), lineWidth: 1.5)
                .frame(width: 24, height: 24)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: selected)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var navBarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(isSelectMode ? "Done" : "Select") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSelectMode.toggle()
                    if !isSelectMode { selectedIDs.removeAll() }
                }
            }
            .font(AppFonts.subheadline.weight(.semibold))
            .foregroundStyle(AppColors.accent)
        }
    }

    // MARK: - Delete bar

    private var deleteBar: some View {
        HStack {
            Text(selectedIDs.isEmpty ? "Select scans" : "\(selectedIDs.count) selected")
                .font(AppFonts.subheadline)
                .foregroundStyle(selectedIDs.isEmpty ? AppColors.textSecondary : AppColors.textPrimary)
                .animation(.none, value: selectedIDs)

            Spacer()

            Button {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(AppFonts.subheadline.weight(.semibold))
                    .foregroundStyle(selectedIDs.isEmpty ? AppColors.textTertiary : .red)
            }
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ id: UUID) {
        Haptics.triggerHapticFeedback(impactLevel: .light)
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func deleteSelected() {
        let toDelete = captures.filter { selectedIDs.contains($0.id) }

        for capture in toDelete {
            // Remove PLY file
            try? FileManager.default.removeItem(atPath: capture.pointCloudPath)
            // Remove snapshot image files
            for path in capture.snapshotPaths {
                try? FileManager.default.removeItem(atPath: path)
            }
            modelContext.delete(capture)
        }

        try? modelContext.save()
        selectedIDs.removeAll()
        withAnimation { isSelectMode = captures.filter { !toDelete.map(\.id).contains($0.id) }.isEmpty ? false : isSelectMode }
    }

    // MARK: - Empty state

    @State private var isAnimatingEmptyState = false

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 42))
                .foregroundStyle(AppColors.textSecondary)
                .offset(y: isAnimatingEmptyState ? -8 : 0)
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isAnimatingEmptyState)
                .onAppear { isAnimatingEmptyState = true }

            Text("Your local captures live here")
                .font(AppFonts.title2)
                .foregroundStyle(AppColors.textPrimary)

            Text("Scan a space, save the point cloud locally, then reopen it later to revisit snaps and inspect the 3D geometry.")
                .font(AppFonts.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }
}

// MARK: - List Row

private struct TrailsCaptureRow: View {
    let capture: TrailsCapture

    private static let thumbSize = CGSize(width: 90, height: 72)

    var body: some View {
        HStack(spacing: 14) {
            // ── Thumbnail ──────────────────────────────────────────────
            thumbnailView
                .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )

            // ── Text ───────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 5) {
                Text(capture.name)
                    .font(AppFonts.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)

                Text(capture.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(AppFonts.caption)
                    .foregroundStyle(AppColors.textSecondary)

                HStack(spacing: 6) {
                    pointCountBadge
                    if !capture.snapshotPaths.isEmpty {
                        snapCountBadge
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // ── Chevron (hidden in select mode — parent adds checkmark) ────
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        if let firstPath = capture.snapshotPaths.first,
           let uiImage = UIImage(contentsOfFile: firstPath) {
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        } else if let data = capture.thumbnailData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        AppColors.backgroundSecondary,
                        Color(hex: "#0f172a")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 22))
                    .foregroundStyle(AppColors.accent.opacity(0.55))
            }
        }
    }

    // MARK: - Badges

    private var pointCountBadge: some View {
        Text("\(compactCount(capture.pointCount)) pts")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(AppColors.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppColors.glass)
            .clipShape(Capsule())
    }

    private var snapCountBadge: some View {
        Label(
            "\(capture.snapshotPaths.count)",
            systemImage: "camera.fill"
        )
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(AppColors.accent)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(AppColors.accent.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Helpers

    private func compactCount(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.0fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}
