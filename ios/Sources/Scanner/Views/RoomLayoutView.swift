//
//  RoomLayoutView.swift
//  Trails
//
//  Real-time 2D architectural minimap displaying detected room bounds,
//  the continuous terracotta walking path, and spatial moment pins.
//

import SwiftUI
import RoomPlan
import simd

struct RoomLayoutView: View {
    let capturedRoom: CapturedRoom?
    let footsteps: [SIMD3<Float>]
    var moments: [SpatialMoment] = []

    // Live Companion & Trail Follower Support
    var liveFollowerFootsteps: [SIMD3<Float>] = []
    var liveFollowerPosition: SIMD3<Float>? = nil
    var activeCheckpointIndex: Int? = nil

    var body: some View {
        GeometryReader { geometry in
            let boundingBox = calculateBoundingBox(for: capturedRoom, footsteps: footsteps)
            let scale = calculateScale(for: boundingBox, in: geometry.size)
            let offset = calculateOffset(for: boundingBox, scale: scale, in: geometry.size)

            ZStack {
                // Background & Architectural Grid
                Color(hex: "#0A0E14")
                    .ignoresSafeArea()

                ArchitecturalGridPattern()
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)

                // When room is recognized, render walls and structures
                if let room = capturedRoom {
                    // Draw Objects (Furniture, etc)
                    ForEach(room.objects, id: \.identifier) { object in
                        drawSurface(object.dimensions, transform: object.transform, scale: scale, offset: offset, color: Color.white.opacity(0.2), lineWidth: 1)
                    }

                    // Draw Walls
                    ForEach(room.walls, id: \.identifier) { wall in
                        drawSurface(wall.dimensions, transform: wall.transform, scale: scale, offset: offset, color: .white, lineWidth: 2.5)
                    }

                    // Draw Doors
                    ForEach(room.doors, id: \.identifier) { door in
                        drawSurface(door.dimensions, transform: door.transform, scale: scale, offset: offset, color: AppColors.mutedBrass, lineWidth: 2)
                    }

                    // Draw Windows
                    ForEach(room.windows, id: \.identifier) { window in
                        drawSurface(window.dimensions, transform: window.transform, scale: scale, offset: offset, color: AppColors.mutedBrass.opacity(0.7), lineWidth: 1.5)
                    }
                } else if footsteps.isEmpty {
                    // Initial Scan Guidance when empty
                    VStack(spacing: 8) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 28, weight: .light))
                            .foregroundColor(AppColors.terracotta.opacity(0.8))

                        Text("Move camera naturally to begin spatial mapping")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(Color.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                }

                // Continuous Walking Vector (Terracotta recorded path)
                drawPathVector(footsteps, scale: scale, offset: offset, color: AppColors.terracotta)

                // Footstep nodes
                drawFootstepNodes(footsteps, scale: scale, offset: offset)

                // Live Follower Walking Path (Electric Cyan)
                if !liveFollowerFootsteps.isEmpty {
                    drawPathVector(liveFollowerFootsteps, scale: scale, offset: offset, color: Color(hex: "#00D4FF"))
                }

                // Moments (Numbered Terracotta Pins - PRD §8.3 & §9.3)
                ForEach(moments) { moment in
                    let pt = projectTo2D(SIMD3<Float>(Float(moment.positionX), 0, Float(moment.positionY)), scale: scale, offset: offset)
                    let isActive = (moment.index == activeCheckpointIndex)

                    ZStack {
                        if isActive {
                            Circle()
                                .stroke(Color(hex: "#00D4FF"), lineWidth: 2)
                                .frame(width: 36, height: 36)
                        }

                        Circle()
                            .fill(isActive ? Color(hex: "#00D4FF").opacity(0.35) : AppColors.mutedBrass.opacity(0.3))
                            .frame(width: 26, height: 26)

                        Circle()
                            .fill(isActive ? Color(hex: "#00D4FF") : AppColors.terracotta)
                            .frame(width: 18, height: 18)
                            .shadow(color: Color.black.opacity(0.5), radius: 3, x: 0, y: 1)

                        Text("\(moment.index)")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .position(pt)
                }

                // Live Follower Current Position Beacon
                if let livePos = liveFollowerPosition {
                    let livePt = projectTo2D(livePos, scale: scale, offset: offset)
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#00D4FF").opacity(0.25))
                            .frame(width: 38, height: 38)

                        Circle()
                            .stroke(Color(hex: "#00D4FF"), lineWidth: 2)
                            .frame(width: 24, height: 24)

                        Circle()
                            .fill(Color(hex: "#00D4FF"))
                            .frame(width: 12, height: 12)
                            .shadow(color: Color(hex: "#00D4FF").opacity(0.8), radius: 6)
                    }
                    .position(livePt)
                }

                // Coordinate Origin Indicator (Center 0,0)
                let originPt = projectTo2D(SIMD3<Float>(0, 0, 0), scale: scale, offset: offset)
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    .frame(width: 12, height: 12)
                    .position(originPt)
            }
        }
    }

    // MARK: - Drawing Helpers

    private func calculateBoundingBox(for room: CapturedRoom?, footsteps: [SIMD3<Float>]) -> CGRect {
        var minX: Float = -2.5
        var maxX: Float = 2.5
        var minZ: Float = -2.5
        var maxZ: Float = 2.5

        if let room = room {
            let processTransform = { (transform: simd_float4x4, dimensions: simd_float3) in
                let position = transform.columns.3
                let halfX = dimensions.x / 2
                let halfZ = dimensions.z / 2
                minX = min(minX, position.x - halfX)
                maxX = max(maxX, position.x + halfX)
                minZ = min(minZ, position.z - halfZ)
                maxZ = max(maxZ, position.z + halfZ)
            }

            for wall in room.walls { processTransform(wall.transform, wall.dimensions) }
            for obj in room.objects { processTransform(obj.transform, obj.dimensions) }
        }

        for step in footsteps {
            minX = min(minX, step.x)
            maxX = max(maxX, step.x)
            minZ = min(minZ, step.z)
            maxZ = max(maxZ, step.z)
        }

        let padding: Float = 1.2
        return CGRect(
            x: CGFloat(minX - padding),
            y: CGFloat(minZ - padding),
            width: CGFloat((maxX - minX) + 2 * padding),
            height: CGFloat((maxZ - minZ) + 2 * padding)
        )
    }

    private func calculateScale(for boundingBox: CGRect, in size: CGSize) -> CGFloat {
        guard boundingBox.width > 0, boundingBox.height > 0 else { return 30 }
        let scaleX = size.width / boundingBox.width
        let scaleY = size.height / boundingBox.height
        return min(scaleX, scaleY)
    }

    private func calculateOffset(for boundingBox: CGRect, scale: CGFloat, in size: CGSize) -> CGSize {
        let scaledWidth = boundingBox.width * scale
        let scaledHeight = boundingBox.height * scale
        let offsetX = (size.width - scaledWidth) / 2.0 - (boundingBox.minX * scale)
        let offsetY = (size.height - scaledHeight) / 2.0 - (boundingBox.minY * scale)
        return CGSize(width: offsetX, height: offsetY)
    }

    private func projectTo2D(_ position: SIMD3<Float>, scale: CGFloat, offset: CGSize) -> CGPoint {
        let x = CGFloat(position.x) * scale + offset.width
        let y = CGFloat(position.z) * scale + offset.height
        return CGPoint(x: x, y: y)
    }

    private func drawSurface(_ dimensions: simd_float3, transform: simd_float4x4, scale: CGFloat, offset: CGSize, color: Color, lineWidth: CGFloat) -> some View {
        let position = transform.columns.3
        let center = projectTo2D(SIMD3<Float>(position.x, position.y, position.z), scale: scale, offset: offset)
        let angle = atan2(transform.columns.0.z, transform.columns.0.x)
        let width = CGFloat(dimensions.x) * scale
        let depth = CGFloat(dimensions.z) * scale

        return Rectangle()
            .strokeBorder(color, lineWidth: lineWidth)
            .background(color.opacity(0.15))
            .frame(width: max(width, 2), height: max(depth, 2))
            .rotationEffect(Angle(radians: Double(angle)))
            .position(center)
    }

    private func drawPathVector(_ footsteps: [SIMD3<Float>], scale: CGFloat, offset: CGSize, color: Color = AppColors.terracotta) -> some View {
        Path { path in
            guard footsteps.count > 1 else { return }
            let points = footsteps.map { projectTo2D($0, scale: scale, offset: offset) }
            path.move(to: points[0])
            for pt in points.dropFirst() {
                path.addLine(to: pt)
            }
        }
        .stroke(
            color,
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawFootstepNodes(_ footsteps: [SIMD3<Float>], scale: CGFloat, offset: CGSize) -> some View {
        ZStack {
            ForEach(Array(footsteps.enumerated()), id: \.offset) { index, step in
                let point = projectTo2D(step, scale: scale, offset: offset)
                let isLatest = index == footsteps.count - 1

                if isLatest {
                    Circle()
                        .stroke(AppColors.terracotta.opacity(0.4), lineWidth: 4)
                        .frame(width: 20, height: 20)
                        .position(point)

                    Circle()
                        .fill(AppColors.terracotta)
                        .frame(width: 10, height: 10)
                        .position(point)
                } else if index % 3 == 0 {
                    Circle()
                        .fill(AppColors.terracotta.opacity(0.45))
                        .frame(width: 5, height: 5)
                        .position(point)
                }
            }
        }
    }
}

// MARK: - Architectural Grid Background

private struct ArchitecturalGridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 30
        var x: CGFloat = 0
        while x <= rect.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            x += step
        }
        var y: CGFloat = 0
        while y <= rect.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
            y += step
        }
        return path
    }
}
