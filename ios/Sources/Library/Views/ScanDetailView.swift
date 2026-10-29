//
//  ScanDetailView.swift
//  Trails
//
//  Detail view for a spatial capture, including 3D viewer and snaps.
//

import SwiftUI
import SwiftData
import UIKit

struct ScanDetailView: View {
    private static let tabChromeReason = "scan-detail"

    let scan: Scan
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var remoteSyncManager: RemoteSyncManager
    @EnvironmentObject private var tabChrome: TabChromeModel
    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false
    @State private var exportURLs: [URL] = []
    @State private var showingExportPicker = false
    @State private var isDeleting = false
    @State private var showingExportOptions = false
    @State private var showingInspector = false
    @State private var loadedSnapshots: [String: UIImage] = [:]
    @State private var snapshotBrowser: SnapshotBrowserState?
    @State private var showsGrid = true
    @State private var resetViewToken = 0
    @State private var captureThumbnailToken = 0
    @State private var showingRenamePrompt = false
    @State private var renameDraft = ""
    @State private var isThumbnailCaptureMode = false

    var body: some View {
        ZStack {
            spatialViewer
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.04),
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.42)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if isThumbnailCaptureMode {
                thumbnailCaptureButton
            }
        }
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomActionBar
        }
        .sheet(isPresented: $showingInspector) {
            ScanInspectorSheet(
                scan: scan,
                loadedSnapshots: loadedSnapshots,
                isDeleting: isDeleting,
                onDelete: deleteScan,
                onSelectSnapshot: { snapshot in
                    openSnapshotBrowser(with: gallerySnapshots, initialSelection: snapshot)
                }
            )
        }
        .confirmationDialog("Export Trails Scan", isPresented: $showingExportOptions, titleVisibility: .visible) {
            Button(scanParts.count > 1 ? "Share .PLY files" : "Share .PLY") { sharePLY() }
            Button(scanParts.count > 1 ? "Save PLY files to Files" : "Save to Files") { savePLYToFiles() }
            if scan.hasReadyGaussianAsset {
                Button("Share 3DGS .splat") { shareGaussianSplat() }
                Button("Share 3DGS PLY") { shareGaussianPLY() }
                if scan.gaussianSPZFileName != nil {
                    Button("Share SPZ") { shareGaussianSPZ() }
                }
                Button("Save 3DGS .splat to Files") { saveGaussianSplatToFiles() }
                Button("Save 3DGS PLY to Files") { saveGaussianPLYToFiles() }
                if scan.gaussianSPZFileName != nil {
                    Button("Save SPZ to Files") { saveGaussianSPZToFiles() }
                }
            }
            if !scan.snapFileNames.isEmpty {
                Button("View Details") { showingInspector = true }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if !shareItems.isEmpty {
                ShareSheet(activityItems: shareItems)
            }
        }
        .sheet(isPresented: $showingExportPicker) {
            if !exportURLs.isEmpty {
                DocumentExportSheet(urls: exportURLs)
            }
        }
        .alert("Rename Scan", isPresented: $showingRenamePrompt) {
            TextField("Scan name", text: $renameDraft)
            Button("Save") {
                commitRename()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose the name shown in the viewer, library, and export metadata.")
        }
        .fullScreenCover(item: $snapshotBrowser) { browser in
            SnapshotViewerScreen(
                snapshots: browser.snapshots,
                initialSnapshotID: browser.initialSnapshotID,
                loadedSnapshots: loadedSnapshots
            )
        }
        .onAppear {
            loadSnapshots()
            startGaussianBuildIfNeeded()
            tabChrome.hide(reason: Self.tabChromeReason)
        }
        .onDisappear {
            tabChrome.show(reason: Self.tabChromeReason)
        }
        .onChange(of: scan.snapFileNames, initial: false) { _, _ in
            loadSnapshots()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }

            Spacer(minLength: 8)

            VStack(spacing: 2) {
                Text(displayTitle)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(displayDate)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer(minLength: 8)

            Menu {
                Section {
                    Button("Rename", systemImage: "pencil") {
                        renameDraft = scan.title
                        showingRenamePrompt = true
                    }
                    Button("Reset View", systemImage: "arrow.counterclockwise") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            resetViewToken += 1
                        }
                    }
                    Button("Update Thumbnail", systemImage: "photo") {
                        isThumbnailCaptureMode.toggle()
                    }
                    Button(
                        showsGrid ? "Turn off grid" : "Turn on grid",
                        systemImage: showsGrid ? "square.grid.3x3" : "square.grid.3x3.fill"
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsGrid.toggle()
                        }
                    }
                }

                Section {
                    Button("View Details", systemImage: "info.circle") {
                        showingInspector = true
                    }

                    Button("Share .PLY", systemImage: "square.and.arrow.up") {
                        sharePLY()
                    }
                    if scan.hasReadyGaussianAsset {
                        Button("Share 3DGS .splat", systemImage: "sparkles") {
                            shareGaussianSplat()
                        }
                        Button("Share 3DGS PLY", systemImage: "square.stack.3d.up") {
                            shareGaussianPLY()
                        }
                        if scan.gaussianSPZFileName != nil {
                            Button("Share SPZ", systemImage: "shippingbox") {
                                shareGaussianSPZ()
                            }
                        }
                    }
                    Button("Save to Files", systemImage: "square.and.arrow.down") {
                        savePLYToFiles()
                    }
                    Button("Delete Scan", systemImage: "trash", role: .destructive) {
                        deleteScan()
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background {
            Rectangle()
                .fill(AppColors.graphite.opacity(0.94))
                .overlay(AppColors.primary.opacity(0.08))
                .shadow(color: .black.opacity(0.24), radius: 12, y: 4)
        }
    }

    private var bottomActionBar: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    showingExportOptions = true
                } label: {
                    Text(scanParts.count > 1 ? "Export PLYs" : "Export PLY")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(AppColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(10)
            .background(AppColors.obsidian.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .background(Color.clear)
    }

    private var displayTitle: String {
        scan.title
    }

    private var displayDate: String {
        scan.timestamp.formatted(
            Date.FormatStyle()
                .day(.defaultDigits)
                .month(.abbreviated)
                .year()
        )
    }

    private var scanParts: [ScanPart] {
        scan.scanParts
    }

    @ViewBuilder
    private var spatialViewer: some View {
        if let assetFileName = webSplatAssetFileName {
            TrailsWebSplatView(
                assetFileName: assetFileName,
                showsGrid: showsGrid,
                resetViewToken: resetViewToken,
                captureThumbnailToken: captureThumbnailToken
            ) { image in
                updateThumbnail(from: image)
            }
        } else {
            viewerAssetStatusView
        }
    }

    private var webSplatAssetFileName: String? {
        if let fileName = scan.gaussianSOGFileName,
           FileManager.default.fileExists(atPath: getFilePath(for: fileName)) {
            return fileName
        }

        if let fileName = scan.gaussianPLYFileName,
           FileManager.default.fileExists(atPath: getFilePath(for: fileName)) {
            return fileName
        }

        return nil
    }

    private var viewerAssetStatusView: some View {
        ZStack {
            AppColors.obsidian.ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white.opacity(0.9))
                    .opacity(showsViewerProgress ? 1 : 0)

                Text(viewerAssetStatusText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
    }

    private var viewerAssetStatusText: String {
        switch scan.gaussianStatus {
        case .queued:
            return "Preparing PlayCanvas viewer"
        case .building:
            return "Building PlayCanvas viewer"
        case .failed:
            return scan.gaussianErrorMessage ?? "PlayCanvas viewer failed"
        case .ready:
            return "PlayCanvas asset missing"
        case .none:
            return "PlayCanvas viewer unavailable"
        }
    }

    private var showsViewerProgress: Bool {
        scan.gaussianStatus == .queued || scan.gaussianStatus == .building
    }

    private var thumbnailCaptureButton: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                Button {
                    captureThumbnailToken += 1
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 68, height: 68)
                        .background(
                            Circle()
                                .fill(AppColors.primary)
                        )
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 2)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
                }
                .padding(.trailing, 28)
                .padding(.bottom, 136)
            }
        }
    }

    private func loadSnapshots() {
        Task {
            var newLoadedSnapshots: [String: UIImage] = [:]
            for fileName in snapshotFileNamesToLoad {
                if let imageData = ScanFileStore.loadImageData(fileName: fileName) {
                    if let uiImage = UIImage(data: imageData) {
                        newLoadedSnapshots[fileName] = uiImage
                    }
                }
            }
            await MainActor.run {
                self.loadedSnapshots = newLoadedSnapshots
            }
        }
    }

    private var snapshotFileNamesToLoad: [String] {
        var seen = Set<String>()
        return (scan.snapFileNames + scan.snapshots.map(\.fileName)).filter { fileName in
            seen.insert(fileName).inserted
        }
    }
    
    private func sharePLY() {
        shareItems = scan.plyFileNames.map { ScanFileStore.fileURL(fileName: $0) }
        showingShareSheet = !shareItems.isEmpty
    }

    private func savePLYToFiles() {
        exportURLs = scan.plyFileNames.map { ScanFileStore.fileURL(fileName: $0) }
        showingExportPicker = !exportURLs.isEmpty
    }

    private func shareGaussianSplat() {
        guard let fileName = scan.gaussianSplatFileName else { return }
        shareItems = [ScanFileStore.fileURL(fileName: fileName)]
        showingShareSheet = true
    }

    private func shareGaussianPLY() {
        guard let fileName = scan.gaussianPLYFileName else { return }
        shareItems = [ScanFileStore.fileURL(fileName: fileName)]
        showingShareSheet = true
    }

    private func shareGaussianSPZ() {
        guard let fileName = scan.gaussianSPZFileName else { return }
        shareItems = [ScanFileStore.fileURL(fileName: fileName)]
        showingShareSheet = true
    }

    private func saveGaussianSplatToFiles() {
        guard let fileName = scan.gaussianSplatFileName else { return }
        exportURLs = [ScanFileStore.fileURL(fileName: fileName)]
        showingExportPicker = true
    }

    private func saveGaussianPLYToFiles() {
        guard let fileName = scan.gaussianPLYFileName else { return }
        exportURLs = [ScanFileStore.fileURL(fileName: fileName)]
        showingExportPicker = true
    }

    private func saveGaussianSPZToFiles() {
        guard let fileName = scan.gaussianSPZFileName else { return }
        exportURLs = [ScanFileStore.fileURL(fileName: fileName)]
        showingExportPicker = true
    }

    private func startGaussianBuildIfNeeded() {
        let needsViewerRebuild = scan.needsGaussianAssetRebuild
        if scan.gaussianStatus == .queued || needsViewerRebuild {
            if needsViewerRebuild {
                GaussianAssetBuildCoordinator.shared.enqueueDeferred(
                    scan: scan,
                    modelContext: modelContext,
                    delay: 0
                )
            } else {
                GaussianAssetBuildCoordinator.shared.enqueueDeferred(scan: scan, modelContext: modelContext)
            }
        } else if scan.hasInterruptedGaussianBuild,
                  !GaussianAssetBuildCoordinator.shared.isActive(scan: scan) {
            if !scan.plyFileNames.isEmpty {
                scan.gaussianStatus = .queued
                scan.gaussianErrorMessage = nil
                scan.updatedAt = .now
                try? modelContext.save()
                GaussianAssetBuildCoordinator.shared.enqueueDeferred(
                    scan: scan,
                    modelContext: modelContext,
                    delay: 0
                )
            } else {
                scan.gaussianStatus = .failed
                scan.gaussianErrorMessage = "PlayCanvas viewer build was interrupted."
                scan.updatedAt = .now
                try? modelContext.save()
            }
        }
    }
    
    private func deleteScan() {
        isDeleting = true
        Task {
            let deleted = await remoteSyncManager.delete(scan: scan, modelContext: modelContext)
            await MainActor.run {
                isDeleting = false
                if deleted {
                    dismiss()
                }
            }
        }
    }
    
    private func getFilePath(for fileName: String) -> String {
        ScanFileStore.filePath(fileName: fileName)
    }

    private func commitRename() {
        let trimmedTitle = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, trimmedTitle != scan.title else { return }

        scan.title = trimmedTitle
        scan.updatedAt = .now
        persistScanMetadata(shouldSyncToCloud: true)
    }

    private func updateThumbnail(from image: UIImage) {
        guard let imageData = makeThumbnailData(from: image) else { return }

        scan.thumbnailData = imageData
        isThumbnailCaptureMode = false
        try? modelContext.save()
        Haptics.success()
    }

    private func persistScanMetadata(shouldSyncToCloud: Bool) {
        if shouldSyncToCloud && AppConfiguration.useFirebase && AppConfiguration.enableScanCloudSync {
            remoteSyncManager.enqueue(scan)
            return
        }

        scan.syncStatus = .localOnly
        try? modelContext.save()
    }

    private func makeThumbnailData(from image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1200
        let largestSide = max(image.size.width, image.size.height)
        let scale = largestSide > maxDimension ? (maxDimension / largestSide) : 1
        let targetSize = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )

        let rendered = UIGraphicsImageRenderer(size: targetSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return rendered.jpegData(compressionQuality: 0.82)
    }

    private var gallerySnapshots: [ScanSnapshot] {
        if !scan.snapshots.isEmpty {
            return scan.snapshots
        }

        return scan.snapFileNames.map {
            ScanSnapshot(fileName: $0, position: SIMD3<Float>(0, 0, 0), capturedAt: scan.timestamp)
        }
    }

    private func openSnapshotBrowser(with snapshots: [ScanSnapshot], initialSelection: ScanSnapshot) {
        guard !snapshots.isEmpty else { return }
        snapshotBrowser = SnapshotBrowserState(
            snapshots: snapshots,
            initialSnapshotID: initialSelection.id
        )
    }
}

private struct ScanInspectorSheet: View {
    let scan: Scan
    let loadedSnapshots: [String: UIImage]
    let isDeleting: Bool
    let onDelete: () -> Void
    let onSelectSnapshot: (ScanSnapshot) -> Void

    private var gallerySnapshots: [ScanSnapshot] {
        if !scan.snapshots.isEmpty {
            return scan.snapshots
        }

        return scan.snapFileNames.map {
            ScanSnapshot(fileName: $0, position: SIMD3<Float>(0, 0, 0), capturedAt: scan.timestamp)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(scan.title)
                        .font(.system(.title2, design: .rounded).weight(.bold))

                    Text(scan.timestamp.formatted(date: .complete, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    DetailStat(label: "Points", value: scan.pointCount.formatted())
                    DetailStat(label: "File Size", value: ByteCountFormatter.string(fromByteCount: scan.fileSize, countStyle: .file))
                    DetailStat(label: "Snaps", value: scan.snapFileNames.count.formatted())
                }

                if let lat = scan.latitude, let lon = scan.longitude {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Location")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(String(format: "%.4f, %.4f", lat, lon))
                            .font(.body.weight(.medium))
                    }
                }

                if !scan.snapFileNames.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Snapshots")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(gallerySnapshots) { snapshot in
                                    if let uiImage = loadedSnapshots[snapshot.fileName] {
                                        Button {
                                            onSelectSnapshot(snapshot)
                                        } label: {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 148, height: 204)
                                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }

                VStack(spacing: 12) {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete Scan", systemImage: "trash")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .disabled(isDeleting)
                }
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct SnapshotBrowserState: Identifiable {
    let snapshots: [ScanSnapshot]
    let initialSnapshotID: String

    var id: String {
        snapshots.map(\.fileName).joined(separator: "|") + "::" + initialSnapshotID
    }
}

private struct SnapshotViewerScreen: View {
    let snapshots: [ScanSnapshot]
    let loadedSnapshots: [String: UIImage]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSnapshotID: String
    @State private var shareURL: URL?
    @State private var showingShareSheet = false

    init(
        snapshots: [ScanSnapshot],
        initialSnapshotID: String,
        loadedSnapshots: [String: UIImage]
    ) {
        let orderedSnapshots = snapshots.sorted {
            if $0.capturedAt == $1.capturedAt {
                return $0.fileName < $1.fileName
            }
            return $0.capturedAt < $1.capturedAt
        }

        self.snapshots = orderedSnapshots
        self.loadedSnapshots = loadedSnapshots
        _selectedSnapshotID = State(
            initialValue: orderedSnapshots.contains(where: { $0.id == initialSnapshotID })
                ? initialSnapshotID
                : (orderedSnapshots.last?.id ?? "")
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedSnapshotID) {
                ForEach(snapshots) { snapshot in
                    snapshotPage(for: snapshot)
                        .tag(snapshot.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .sheet(isPresented: $showingShareSheet) {
            if let shareURL {
                ShareSheet(activityItems: [shareURL])
            }
        }
    }

    private var selectedSnapshot: ScanSnapshot? {
        snapshots.first(where: { $0.id == selectedSnapshotID }) ?? snapshots.last
    }

    private var selectedIndex: Int {
        max(0, snapshots.firstIndex(where: { $0.id == selectedSnapshotID }) ?? (snapshots.count - 1))
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(selectedDayLabel)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Text(selectedTimeLabel)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
            }

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .background(Color.black.opacity(0.96))
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            thumbnailStrip

            HStack {
                Button {
                    shareCurrentSnapshot()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .disabled(selectedSnapshot == nil)

                Spacer()

                Text("\(selectedIndex + 1) of \(snapshots.count)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.76))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(Color.black.opacity(0.96))
    }

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(snapshots) { snapshot in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedSnapshotID = snapshot.id
                            }
                        } label: {
                            Group {
                                if let image = loadedSnapshots[snapshot.fileName] {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.white.opacity(0.08))
                                        Image(systemName: "photo")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.55))
                                    }
                                }
                            }
                            .frame(width: 72, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        snapshot.id == selectedSnapshotID
                                            ? Color.white
                                            : Color.white.opacity(0.12),
                                        lineWidth: snapshot.id == selectedSnapshotID ? 2 : 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .id(snapshot.id)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 100)
            .onAppear {
                proxy.scrollTo(selectedSnapshotID, anchor: .center)
            }
            .onChange(of: selectedSnapshotID) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func snapshotPage(for snapshot: ScanSnapshot) -> some View {
        GeometryReader { geometry in
            Group {
                if let image = loadedSnapshots[snapshot.fileName] {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            maxWidth: geometry.size.width - 24,
                            maxHeight: geometry.size.height - 24
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                        Text("Snapshot unavailable")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .padding(.vertical, 12)
        }
    }

    private var selectedDayLabel: String {
        guard let selectedSnapshot else { return "" }
        if Calendar.current.isDateInToday(selectedSnapshot.capturedAt) {
            return "Today"
        }
        return selectedSnapshot.capturedAt.formatted(
            Date.FormatStyle()
                .month(.wide)
                .day()
        )
    }

    private var selectedTimeLabel: String {
        guard let selectedSnapshot else { return "" }
        return selectedSnapshot.capturedAt.formatted(
            Date.FormatStyle()
                .hour(.defaultDigits(amPM: .omitted))
                .minute(.twoDigits)
                .second(.twoDigits)
        )
    }

    private func shareCurrentSnapshot() {
        guard let selectedSnapshot else { return }
        shareURL = ScanFileStore.fileURL(fileName: selectedSnapshot.fileName)
        showingShareSheet = shareURL != nil
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct DocumentExportSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: urls, asCopy: true)
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

struct DetailStat: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
