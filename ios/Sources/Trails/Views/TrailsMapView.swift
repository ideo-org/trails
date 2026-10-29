import SwiftUI
import SwiftData
import MapKit

struct TrailsMapView: View {
    @Query(sort: \TrailsCapture.createdAt, order: .reverse) private var captures: [TrailsCapture]
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                ForEach(captures.filter { $0.coordinate != nil }) { capture in
                    Annotation(capture.name, coordinate: capture.coordinate!) {
                        NavigationLink {
                            TrailsCaptureDetailView(capture: capture)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(AppColors.primary)
                                    .frame(width: 18, height: 18)
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                                    .frame(width: 24, height: 24)
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()

            if captures.isEmpty {
                emptyOverlay
            } else {
                recentOverlay
            }
        }
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            focusMapIfNeeded()
            Analytics.trackScreenView("TrailsMapView")
        }
    }

    private var emptyOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 36))
                .foregroundStyle(AppColors.textSecondary)
            Text("No mapped captures yet")
                .font(AppFonts.title3)
                .foregroundStyle(AppColors.textPrimary)
            Text("Start a LiDAR scan and Trails will pin the capture here when GPS is available.")
                .font(AppFonts.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(AppColors.glass)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }

    private var recentOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent local captures")
                .font(AppFonts.title3)
                .foregroundStyle(AppColors.textPrimary)

            ForEach(captures.prefix(3)) { capture in
                NavigationLink {
                    TrailsCaptureDetailView(capture: capture)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(capture.name)
                                .font(AppFonts.subheadline.weight(.semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                            Text("\(capture.pointCount.formatted()) points · \(capture.formattedDuration)")
                                .font(AppFonts.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundPrimary.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    private func focusMapIfNeeded() {
        guard let coordinate = captures.compactMap(\.coordinate).first else { return }
        position = .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        )
    }
}
