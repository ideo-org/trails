import SwiftUI

struct TrailsCaptureDetailView: View {
    let capture: TrailsCapture

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TrailsPointCloudView(filePath: capture.pointCloudPath)
                        .frame(height: pointCloudHeight(for: proxy.size))
                        .clipShape(RoundedRectangle(cornerRadius: 24))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(capture.name)
                            .font(AppFonts.title)
                            .foregroundStyle(AppColors.textPrimary)

                        Text(capture.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(AppFonts.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metricCard(title: "Point count", value: capture.pointCount.formatted())
                        metricCard(title: "Duration", value: capture.formattedDuration)
                        metricCard(title: "File size", value: capture.formattedFileSize)
                        metricCard(title: "Snaps", value: capture.snapshotPaths.count.formatted())
                    }

                    if !capture.snapshotPaths.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Snaps")
                                .font(AppFonts.title3)
                                .foregroundStyle(AppColors.textPrimary)

                            TabView {
                                ForEach(capture.snapshotPaths, id: \.self) { path in
                                    TrailsSnapshotView(path: path)
                                        .padding(.horizontal, 2)
                                }
                            }
                            .frame(height: 240)
                            .tabViewStyle(.page)
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pointCloudHeight(for containerSize: CGSize) -> CGFloat {
        min(360, max(280, containerSize.height * 0.45))
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppFonts.caption)
                .foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(AppFonts.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.glass)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }
}

private struct TrailsSnapshotView: View {
    let path: String

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(AppColors.backgroundSecondary)
                    Text("Snapshot unavailable")
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
