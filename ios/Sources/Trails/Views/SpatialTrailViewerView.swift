//
//  SpatialTrailViewerView.swift
//  Trails
//
//  Screen 3: Spatial Trail Viewer, designed in docs/stitch/spatial_viewer_through_the_courtyard.
//  Presents the interactive 3D/2D spatial RoomPlan and LiDAR mesh replay with moment sequence navigation.
//

import SwiftUI

public struct SpatialTrailViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var dataStore = TrailsDataStore.shared

    @State private var is3DMode: Bool = true
    @State private var currentMomentIndex: Int = 1 // 1-based index (0 -> Moment 1, 1 -> Moment 2)
    @State private var isAudioPlaying: Bool = false
    @State private var cameraAngle: Double = 35.0
    @State private var cameraRotation: Double = 0.0

    public init() {}

    private var trail: TrailDetail {
        dataStore.activeTrail ?? TrailDetail(
            id: "fallback",
            title: "Through the Courtyard",
            subtitle: "Morning light & ventilation paths",
            placeId: "dhun-haveli",
            placeName: "Dhun Haveli",
            wing: "Ground Floor",
            authorName: "Hiro",
            authorRole: "Architect & Spatial Explorer",
            distanceMeters: 140
        )
    }

    private var currentMoment: SpatialMoment {
        let moments = trail.moments
        guard !moments.isEmpty else {
            return SpatialMoment(
                id: "m0",
                index: 1,
                title: "Courtyard Portal",
                subtitle: "Threshold",
                narrative: "Standing at the doorway.",
                architecturalNote: "Dry stone joinery.",
                distanceAlongPathMeters: 0
            )
        }
        let safeIndex = max(0, min(currentMomentIndex, moments.count - 1))
        return moments[safeIndex]
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // MARK: - Spatial Canvas (3D RoomPlan / LiDAR Point Cloud)
            ZStack {
                Color(hex: "#1C1C16") // Deep survey dark canvas
                    .ignoresSafeArea()

                SpatialMeshView(
                    is3D: is3DMode,
                    currentMomentIndex: currentMomentIndex,
                    moments: trail.moments,
                    cameraAngle: cameraAngle,
                    cameraRotation: cameraRotation
                )
                .ignoresSafeArea()
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            cameraRotation += Double(value.translation.width) * 0.05
                            cameraAngle = max(10, min(80, cameraAngle - Double(value.translation.height) * 0.05))
                        }
                )
            }

            // MARK: - Top Spatial HUD
            VStack(spacing: 8) {
                // Top Control Bar
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppColors.pureWhite)
                            .frame(width: 38, height: 38)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Circle())
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(trail.placeName) • \(trail.title)")
                            .font(AppFonts.headlineSmall)
                            .foregroundColor(AppColors.pureWhite)
                            .lineLimit(1)

                        Text("Trail by \(trail.authorName)")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.pureWhite.opacity(0.75))
                    }

                    Spacer()

                    // 3D / 2D Switch
                    HStack(spacing: 2) {
                        Button {
                            withAnimation(.spring(response: 0.3)) { is3DMode = true }
                        } label: {
                            Text("3D")
                                .font(AppFonts.labelSpatial)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(is3DMode ? AppColors.terracotta : Color.clear)
                                .foregroundColor(AppColors.pureWhite)
                                .clipShape(Capsule())
                        }

                        Button {
                            withAnimation(.spring(response: 0.3)) { is3DMode = false }
                        } label: {
                            Text("2D")
                                .font(AppFonts.labelSpatial)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(!is3DMode ? AppColors.terracotta : Color.clear)
                                .foregroundColor(AppColors.pureWhite)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(3)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())

                    // Recenter button
                    Button {
                        withAnimation {
                            cameraAngle = 35.0
                            cameraRotation = 0.0
                        }
                    } label: {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppColors.pureWhite)
                            .frame(width: 38, height: 38)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 50)

                // Sub-HUD Status Strip
                HStack(spacing: 8) {
                    Text("N · Ground Floor | 1:50 scale")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.pureWhite.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Capsule())

                    Spacer()

                    Text("Replay · Not live navigation")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.activeTrail)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColors.terracotta.opacity(0.2))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 16)

                // Moment Sequence Breadcrumb Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(trail.moments.enumerated()), id: \.element.id) { index, moment in
                            Button {
                                withAnimation {
                                    currentMomentIndex = index
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if index == currentMomentIndex {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 10))
                                    }
                                    Text("\(moment.index). \(moment.title)")
                                        .font(AppFonts.labelSpatial)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    index == currentMomentIndex
                                        ? AppColors.mutedBrass
                                        : Color.black.opacity(0.5)
                                )
                                .foregroundColor(
                                    index == currentMomentIndex
                                        ? AppColors.deepInk
                                        : AppColors.pureWhite.opacity(0.8)
                                )
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 4)

                Spacer()
            }

            // MARK: - Bottom Floating Spatial Moment Card
            VStack(alignment: .leading, spacing: 14) {
                // Drag handle
                Capsule()
                    .fill(AppColors.deepInk.opacity(0.18))
                    .frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                // Card Header (Moment # & Distance)
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.terracotta)

                        Text("MOMENT \(currentMoment.index) OF \(trail.moments.count)")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.terracotta)
                    }

                    Spacer()

                    Label("\(currentMoment.distanceAlongPathMeters)m along path", systemImage: "figure.walk")
                        .font(AppFonts.labelMetric)
                        .foregroundColor(AppColors.outline)
                }

                // Moment Title & Narrative
                VStack(alignment: .leading, spacing: 6) {
                    Text(currentMoment.title)
                        .font(AppFonts.headlineMedium)
                        .foregroundColor(AppColors.deepInk)

                    Text(currentMoment.narrative)
                        .font(AppFonts.bodyMedium)
                        .foregroundColor(AppColors.deepInk)
                        .lineSpacing(4)
                }

                // Field Note Audio Player (if moment has audio)
                if currentMoment.hasAudio {
                    HStack(spacing: 12) {
                        Button {
                            isAudioPlaying.toggle()
                        } label: {
                            Image(systemName: isAudioPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14))
                                .foregroundColor(AppColors.onPrimary)
                                .frame(width: 34, height: 34)
                                .background(AppColors.primary)
                                .clipShape(Circle())
                        }

                        // Simulated audio waveform
                        HStack(spacing: 3) {
                            ForEach(0..<18) { i in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(i < 6 && isAudioPlaying ? AppColors.terracotta : AppColors.surfaceContainerHigh)
                                    .frame(width: 3, height: CGFloat([12, 22, 16, 28, 14, 20, 24, 18, 10, 26, 14, 20, 16, 24, 12, 18, 22, 14][i]))
                            }
                        }

                        Spacer()

                        Text(currentMoment.audioDuration ?? "0:42")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.outline)
                    }
                    .padding(10)
                    .background(AppColors.surfaceContainerLow)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Architectural Note
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "compass.drawing")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.mutedBrass)
                        .padding(.top, 2)

                    Text(currentMoment.architecturalNote)
                        .font(AppFonts.bodySmall)
                        .foregroundColor(AppColors.onSurfaceVariant)
                }

                // Stepper Action Buttons
                HStack(spacing: 12) {
                    Button {
                        if currentMomentIndex > 0 {
                            withAnimation { currentMomentIndex -= 1 }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left")
                            Text("Prev (\(currentMomentIndex > 0 ? trail.moments[currentMomentIndex - 1].title.prefix(10) : "Start"))")
                        }
                        .font(AppFonts.labelUI)
                        .foregroundColor(currentMomentIndex > 0 ? AppColors.primary : AppColors.outline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.surfaceContainerLow)
                        .clipShape(Capsule())
                    }
                    .disabled(currentMomentIndex == 0)

                    Button {
                        if currentMomentIndex < trail.moments.count - 1 {
                            withAnimation { currentMomentIndex += 1 }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Next: \(currentMomentIndex < trail.moments.count - 1 ? trail.moments[currentMomentIndex + 1].title.prefix(12) : "End")")
                            Image(systemName: "arrow.right")
                        }
                        .font(AppFonts.labelUI)
                        .foregroundColor(AppColors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.primary)
                        .clipShape(Capsule())
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .background(AppColors.elevatedCanvas)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: -6)
        }
        .statusBarHidden()
    }
}

// MARK: - Spatial Mesh Canvas View

struct SpatialMeshView: View {
    let is3D: Bool
    let currentMomentIndex: Int
    let moments: [SpatialMoment]
    let cameraAngle: Double
    let cameraRotation: Double

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // Background subtle grid lines
            for i in stride(from: 0, to: Int(w), by: 40) {
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: CGFloat(i), y: 0))
                gridLine.addLine(to: CGPoint(x: CGFloat(i), y: h))
                context.stroke(gridLine, with: .color(Color.white.opacity(0.04)), lineWidth: 0.5)
            }
            for j in stride(from: 0, to: Int(h), by: 40) {
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: 0, y: CGFloat(j)))
                gridLine.addLine(to: CGPoint(x: w, y: CGFloat(j)))
                context.stroke(gridLine, with: .color(Color.white.opacity(0.04)), lineWidth: 0.5)
            }

            // RoomPlan Wall Wireframes (3D Perspective Projection Simulation)
            let pitch = cameraAngle * .pi / 180.0
            let yaw = cameraRotation * .pi / 180.0
            let cy = h * 0.45
            let cx = w * 0.5

            // Perspective transform helper
            func project(_ px: Double, _ py: Double, _ pz: Double) -> CGPoint {
                let rx = px * cos(yaw) - py * sin(yaw)
                let ry = px * sin(yaw) + py * cos(yaw)
                let rz = pz

                let screenX = cx + rx
                let screenY = cy + (ry * sin(pitch) - rz * cos(pitch))
                return CGPoint(x: screenX, y: screenY)
            }

            // Draw architectural footprint (Courtyard walls)
            let boxPoints = [
                (-120.0, -140.0, 0.0),
                (120.0, -140.0, 0.0),
                (120.0, 140.0, 0.0),
                (-120.0, 140.0, 0.0)
            ]

            var floorPath = Path()
            let pt0 = project(boxPoints[0].0, boxPoints[0].1, boxPoints[0].2)
            floorPath.move(to: pt0)
            for pt in boxPoints.dropFirst() {
                floorPath.addLine(to: project(pt.0, pt.1, pt.2))
            }
            floorPath.closeSubpath()
            context.stroke(floorPath, with: .color(Color(hex: "#173E35").opacity(0.8)), lineWidth: 2)
            context.fill(floorPath, with: .color(Color(hex: "#173E35").opacity(0.12)))

            // Inner light well bounds
            let wellPoints = [
                (-40.0, -50.0, 0.0),
                (40.0, -50.0, 0.0),
                (40.0, 50.0, 0.0),
                (-40.0, 50.0, 0.0)
            ]
            var wellPath = Path()
            wellPath.move(to: project(wellPoints[0].0, wellPoints[0].1, wellPoints[0].2))
            for pt in wellPoints.dropFirst() {
                wellPath.addLine(to: project(pt.0, pt.1, pt.2))
            }
            wellPath.closeSubpath()
            context.stroke(wellPath, with: .color(Color(hex: "#81A99D").opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

            // Vertical 3D wall pillars if in 3D mode
            if is3D {
                for pt in boxPoints {
                    let base = project(pt.0, pt.1, 0.0)
                    let top = project(pt.0, pt.1, 60.0)
                    var wallEdge = Path()
                    wallEdge.move(to: base)
                    wallEdge.addLine(to: top)
                    context.stroke(wallEdge, with: .color(Color(hex: "#81A99D").opacity(0.4)), lineWidth: 1)
                }
            }

            // Terracotta Trail Vector Path
            let pathNodes = [
                (-90.0, 100.0, 0.0),
                (-30.0, 30.0, 0.0),
                (10.0, -20.0, 5.0),
                (70.0, -80.0, 12.0)
            ]

            var vectorPath = Path()
            if let first = pathNodes.first {
                vectorPath.move(to: project(first.0, first.1, first.2))
                for pt in pathNodes.dropFirst() {
                    vectorPath.addLine(to: project(pt.0, pt.1, pt.2))
                }
                // Glowing stroke
                context.stroke(vectorPath, with: .color(AppColors.terracotta.opacity(0.35)), lineWidth: 7)
                context.stroke(vectorPath, with: .color(AppColors.terracotta), lineWidth: 3.5)
            }

            // Spatial Waypoint Nodes
            for (idx, pt) in pathNodes.enumerated() {
                let screenPt = project(pt.0, pt.1, pt.2)
                let isCurrent = idx == currentMomentIndex

                // Pin concentric halo
                let haloRadius: CGFloat = isCurrent ? 14 : 9
                let haloRect = CGRect(x: screenPt.x - haloRadius, y: screenPt.y - haloRadius, width: haloRadius * 2, height: haloRadius * 2)
                context.fill(Path(ellipseIn: haloRect), with: .color(isCurrent ? AppColors.terracotta.opacity(0.4) : AppColors.mutedBrass.opacity(0.2)))

                // Pin core
                let pinRadius: CGFloat = isCurrent ? 7 : 4.5
                let pinRect = CGRect(x: screenPt.x - pinRadius, y: screenPt.y - pinRadius, width: pinRadius * 2, height: pinRadius * 2)
                context.fill(Path(ellipseIn: pinRect), with: .color(isCurrent ? AppColors.terracotta : AppColors.mutedBrass))
            }
        }
    }
}
