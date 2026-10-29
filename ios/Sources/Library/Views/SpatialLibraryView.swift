//
//  SpatialLibraryView.swift
//  Trails
//
//  Grid view of spatial captures.
//

import SwiftUI
import SwiftData

struct SpatialLibraryView: View {
    @Query(sort: \Scan.timestamp, order: .reverse) private var scans: [Scan]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var remoteSyncManager: RemoteSyncManager
    
    @State private var isSelectionMode = false
    @State private var selectedScans = Set<UUID>()
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var selectedShareURLs: [URL] = []
    @State private var showingShareSheet = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 156, maximum: 220), spacing: 16)
    ]
    
    @State private var isAnimatingEmptyState = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if scans.isEmpty {
                    emptyState
                } else {
                    libraryHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 8)

                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(scans) { scan in
                            if isSelectionMode {
                                ScanGridItem(scan: scan, isSelected: selectedScans.contains(scan.id))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        toggleSelection(for: scan.id)
                                    }
                            } else {
                                NavigationLink(destination: ScanDetailView(scan: scan)) {
                                    ScanGridItem(scan: scan, isSelected: false)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle(isSelectionMode ? "\(selectedScans.count) Selected" : "Trails Library")
        .background(AppColors.scannerGradient.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !scans.isEmpty {
                    Button(isSelectionMode ? "Done" : "Edit") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isSelectionMode.toggle()
                            if !isSelectionMode {
                                selectedScans.removeAll()
                            }
                        }
                    }
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if isSelectionMode && !selectedScans.isEmpty {
                selectionActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            SelectedScansShareSheet(activityItems: selectedShareURLs)
        }
        .confirmationDialog(
            "Delete \(selectedScans.count) captures?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedScans()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove these captures and their local files from this device.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 118)

            ZStack {
                Circle()
                    .stroke(AppColors.secondary.opacity(0.22), lineWidth: 1)
                    .frame(width: 132, height: 132)
                    .scaleEffect(isAnimatingEmptyState ? 1.22 : 1.0)
                    .opacity(isAnimatingEmptyState ? 0 : 0.72)

                Circle()
                    .fill(AppColors.primary.opacity(0.12))
                    .frame(width: 96, height: 96)

                Image(systemName: "viewfinder.circle")
                    .font(.system(size: 60, weight: .thin))
                    .foregroundStyle(AppColors.secondary)
                    .shadow(color: AppColors.primary.opacity(0.35), radius: 24)
            }
            .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false), value: isAnimatingEmptyState)
            .onAppear { isAnimatingEmptyState = true }

            VStack(spacing: 10) {
                Text("Start your spatial archive")
                    .font(.system(.title2, design: .rounded).weight(.black))
                    .foregroundColor(.white)

                Text("Save a LiDAR scan and it will appear here with point counts, snapshots, export, and sharing.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.66))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 38)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SPATIAL ARCHIVE")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.7)
                .foregroundStyle(AppColors.secondary)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(scans.count) \(scans.count == 1 ? "scan" : "scans")")
                        .font(.system(.title2, design: .rounded).weight(.black))
                        .foregroundStyle(.white)

                    Text("\(formatPointCount(totalPointCount)) captured points")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer()

                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(AppColors.primaryGradient)
            }
        }
        .padding(18)
        .background(AppColors.controlSurface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        }
    }

    private var totalPointCount: Int {
        scans.reduce(0) { $0 + $1.pointCount }
    }

    private func formatPointCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }

        if count >= 10_000 {
            return String(format: "%.1fk", Double(count) / 1_000)
        }

        return count.formatted()
    }

    private var selectionActionBar: some View {
        HStack(spacing: 12) {
            Button(action: shareSelectedScans) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .disabled(isDeleting)

            Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                Label("Delete", systemImage: "trash.fill")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .disabled(isDeleting)
        }
        .font(.system(.body, design: .rounded))
        .foregroundColor(.white)
        .padding(10)
        .background(AppColors.obsidian.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .opacity(isDeleting ? 0.6 : 1.0)
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
    }

    private func shareSelectedScans() {
        let urls = scans
            .filter { selectedScans.contains($0.id) }
            .flatMap { scan in
                scan.plyFileNames.map { ScanFileStore.fileURL(fileName: $0) }
            }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        guard !urls.isEmpty else { return }
        selectedShareURLs = urls
        showingShareSheet = true
        Haptics.selection()
    }

    private func toggleSelection(for id: UUID) {
        if selectedScans.contains(id) {
            selectedScans.remove(id)
        } else {
            selectedScans.insert(id)
        }
        Haptics.selection()
    }

    private func deleteSelectedScans() {
        isDeleting = true
        Task {
            let scansToDelete = scans.filter { selectedScans.contains($0.id) }
            for scan in scansToDelete {
                _ = await remoteSyncManager.delete(scan: scan, modelContext: modelContext)
            }
            
            await MainActor.run {
                withAnimation {
                    isSelectionMode = false
                    selectedScans.removeAll()
                    isDeleting = false
                }
                Haptics.success()
            }
        }
    }
}

private struct SelectedScansShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ScanGridItem: View {
    let scan: Scan
    var isSelected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            thumbnailView

            VStack(alignment: .leading, spacing: 4) {
                Text(scan.title)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.black)
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack {
                    Text(scan.timestamp.formatted(date: .abbreviated, time: .omitted))
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: scan.fileSize, countStyle: .file))
                        .font(.system(size: 10, design: .monospaced))
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.58))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(isSelected ? AppColors.primary.opacity(0.18) : AppColors.glass)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? AppColors.secondary : AppColors.border, lineWidth: isSelected ? 2 : 1)
        }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(AppColors.secondary)
                    .background(Circle().fill(AppColors.obsidian))
                    .offset(x: 6, y: -6)
            }
        }
    }

    private var scanParts: [ScanPart] {
        scan.scanParts
    }

    private var thumbnailView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                mainThumbnail
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Label(formatPointCount(scan.pointCount), systemImage: "dot.viewfinder")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topLeading) {
            if !scan.snapFileNames.isEmpty {
                Label("\(scan.snapFileNames.count)", systemImage: "camera.fill")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.46))
                    .clipShape(Capsule())
                    .padding(10)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            subscanPreviewStrip
                .padding(8)
        }
    }

    @ViewBuilder
    private var mainThumbnail: some View {
        if let data = scan.thumbnailData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else if let firstSnap = scan.snapFileNames.first, let uiImage = loadImage(named: firstSnap) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(AppColors.graphite)
                .overlay(
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(AppColors.secondary)
                )
        }
    }

    @ViewBuilder
    private var subscanPreviewStrip: some View {
        if scanParts.count > 1 {
            HStack(spacing: 4) {
                ForEach(Array(scanParts.prefix(3))) { part in
                    subscanPreview(for: part)
                }

                if scanParts.count > 3 {
                    Text("+\(scanParts.count - 3)")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 34)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(4)
            .background(Color.black.opacity(0.46))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func subscanPreview(for part: ScanPart) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if let thumbnailFileName = part.thumbnailFileName,
               let image = loadImage(named: thumbnailFileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.secondary)
                    }
            }

            Text("\(part.index)")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .frame(width: 14, height: 14)
                .background(Circle().fill(.white))
                .padding(2)
        }
        .frame(width: 28, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        }
    }

    private func loadImage(named fileName: String) -> UIImage? {
        UIImage(contentsOfFile: ScanFileStore.filePath(fileName: fileName))
    }

    private func formatPointCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM pts", Double(count) / 1_000_000)
        }

        if count >= 10_000 {
            return String(format: "%.1fk pts", Double(count) / 1_000)
        }

        return "\(count.formatted()) pts"
    }
}
