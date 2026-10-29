import SwiftUI

struct LootHighlightView: View {
    let id: UUID
    let boundingBox: CGRect
    let isCaptured: Bool
    
    @State private var isPulsing = false
    
    // We need to convert normalized bounding box (0,0 to 1,1) to screen coordinates
    // Assuming the parent view provides geometry size
    let screenSize: CGSize
    
    var body: some View {
        let rect = convertToScreen(boundingBox: boundingBox, screenSize: screenSize)
        
        ZStack {
            if !isCaptured {
                // Outer Glow
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.yellow.opacity(0.8), lineWidth: 4)
                    .blur(radius: isPulsing ? 8 : 2)
                    .scaleEffect(isPulsing ? 1.05 : 1.0)
                
                // Inner Border
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white, lineWidth: 2)
                
                // Loot Icon at top right
                Image(systemName: "diamond.fill")
                    .foregroundColor(.cyan)
                    .shadow(color: .cyan.opacity(0.8), radius: 4, x: 0, y: 0)
                    .offset(x: rect.width / 2, y: -rect.height / 2)
                    .scaleEffect(isPulsing ? 1.2 : 1.0)
            } else {
                // Captured state (handled by transition/animation in parent ideally, but we can do a scale down here)
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.yellow)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
        .onAppear {
            isPulsing = true
        }
    }
    
    private func convertToScreen(boundingBox: CGRect, screenSize: CGSize) -> CGRect {
        // Vision bounding box is origin at bottom-left, normalized.
        // We need to flip Y for SwiftUI (origin top-left).
        let x = boundingBox.minX * screenSize.width
        let y = (1 - boundingBox.maxY) * screenSize.height
        let width = boundingBox.width * screenSize.width
        let height = boundingBox.height * screenSize.height
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
