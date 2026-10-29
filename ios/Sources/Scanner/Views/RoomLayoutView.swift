//
//  RoomLayoutView.swift
//  Trails
//

import SwiftUI
import RoomPlan
import simd

struct RoomLayoutView: View {
    let capturedRoom: CapturedRoom?
    let footsteps: [SIMD3<Float>]
    var moments: [SpatialMoment] = []
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                AppColors.void.ignoresSafeArea()
                
                if let room = capturedRoom {
                    // We need a scale and offset to fit the room in the view
                    let boundingBox = calculateBoundingBox(for: room, footsteps: footsteps)
                    let scale = calculateScale(for: boundingBox, in: geometry.size)
                    let offset = calculateOffset(for: boundingBox, scale: scale, in: geometry.size)
                    
                    // Draw Walls
                    ForEach(room.walls, id: \.identifier) { wall in
                        drawSurface(wall.dimensions, transform: wall.transform, scale: scale, offset: offset, color: .white, lineWidth: 3)
                    }
                    
                    // Draw Objects (Furniture, etc)
                    ForEach(room.objects, id: \.identifier) { object in
                        drawSurface(object.dimensions, transform: object.transform, scale: scale, offset: offset, color: Color.white.opacity(0.3), lineWidth: 1)
                    }
                    
                    // Draw Doors
                    ForEach(room.doors, id: \.identifier) { door in
                        drawSurface(door.dimensions, transform: door.transform, scale: scale, offset: offset, color: AppColors.secondary, lineWidth: 2)
                    }
                    
                    // Draw Windows
                    ForEach(room.windows, id: \.identifier) { window in
                        drawSurface(window.dimensions, transform: window.transform, scale: scale, offset: offset, color: AppColors.secondary, lineWidth: 2)
                    }
                    
                    // Draw Footsteps (Dots style)
                    drawFootsteps(footsteps, scale: scale, offset: offset)

                    // Draw Moments (Numbered Terracotta Pins - PRD §8.3 & §9.3)
                    ForEach(moments) { moment in
                        let pt = projectTo2D(SIMD3<Float>(Float(moment.positionX), 0, Float(moment.positionY)), scale: scale, offset: offset)
                        ZStack {
                            Circle()
                                .fill(AppColors.terracotta)
                                .frame(width: 18, height: 18)
                                .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 1)
                            Text("\(moment.index)")
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .position(pt)
                    }
                }
            }
        }
    }
    
    // MARK: - Drawing Helpers
    
    private func calculateBoundingBox(for room: CapturedRoom, footsteps: [SIMD3<Float>]) -> CGRect {
        var minX: Float = Float.infinity
        var maxX: Float = -Float.infinity
        var minZ: Float = Float.infinity
        var maxZ: Float = -Float.infinity
        
        let processTransform = { (transform: simd_float4x4, dimensions: simd_float3) in
            let position = transform.columns.3
            // Simplified: we assume the object spans around its center
            let halfX = dimensions.x / 2
            let halfZ = dimensions.z / 2
            
            minX = min(minX, position.x - halfX)
            maxX = max(maxX, position.x + halfX)
            minZ = min(minZ, position.z - halfZ)
            maxZ = max(maxZ, position.z + halfZ)
        }
        
        for wall in room.walls { processTransform(wall.transform, wall.dimensions) }
        for obj in room.objects { processTransform(obj.transform, obj.dimensions) }
        
        for step in footsteps {
            minX = min(minX, step.x)
            maxX = max(maxX, step.x)
            minZ = min(minZ, step.z)
            maxZ = max(maxZ, step.z)
        }
        
        if minX == Float.infinity {
            return CGRect(x: -5, y: -5, width: 10, height: 10)
        }
        
        // Add some padding
        let padding: Float = 1.0
        return CGRect(
            x: CGFloat(minX - padding),
            y: CGFloat(minZ - padding), // Map Z to Y in 2D
            width: CGFloat((maxX - minX) + 2 * padding),
            height: CGFloat((maxZ - minZ) + 2 * padding)
        )
    }
    
    private func calculateScale(for boundingBox: CGRect, in size: CGSize) -> CGFloat {
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
        // In ARKit, X is right, Y is up, Z is back.
        // For a top-down floor plan, we map X -> X and Z -> Y
        let x = CGFloat(position.x) * scale + offset.width
        let y = CGFloat(position.z) * scale + offset.height
        return CGPoint(x: x, y: y)
    }
    
    private func drawSurface(_ dimensions: simd_float3, transform: simd_float4x4, scale: CGFloat, offset: CGSize, color: Color, lineWidth: CGFloat) -> some View {
        // Extract position and rotation
        let position = transform.columns.3
        
        // Compute 2D position
        let center = projectTo2D(SIMD3<Float>(position.x, position.y, position.z), scale: scale, offset: offset)
        
        // Calculate rotation around Y axis (top-down view)
        let angle = atan2(transform.columns.0.z, transform.columns.0.x)
        
        // Convert dimensions to screen size
        let width = CGFloat(dimensions.x) * scale
        let depth = CGFloat(dimensions.z) * scale
        
        return Rectangle()
            .strokeBorder(color, lineWidth: lineWidth)
            .background(color.opacity(0.2))
            .frame(width: max(width, 2), height: max(depth, 2))
            .rotationEffect(Angle(radians: Double(angle)))
            .position(center)
    }
    
    private func drawFootsteps(_ footsteps: [SIMD3<Float>], scale: CGFloat, offset: CGSize) -> some View {
        ZStack {
            ForEach(Array(footsteps.enumerated()), id: \.offset) { index, step in
                let point = projectTo2D(step, scale: scale, offset: offset)
                let isLatest = index == footsteps.count - 1
                
                Circle()
                    .fill(isLatest ? AppColors.secondary : AppColors.lidar)
                    .frame(width: isLatest ? 12 : 8, height: isLatest ? 12 : 8)
                    .position(point)
            }
        }
    }
}
