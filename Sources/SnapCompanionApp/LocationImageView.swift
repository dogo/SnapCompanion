import Kingfisher
import SwiftUI

/// Snap's location frame shape — a vertical hexagon with small flat top/bottom
/// edges and straight sides. Proportions measured from the real location art.
struct LocationHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: w * x, y: h * y) }
        var path = Path()
        path.move(to: p(0.44, 0))
        path.addLine(to: p(0.56, 0))
        path.addLine(to: p(0.91, 0.18))
        path.addLine(to: p(0.91, 0.82))
        path.addLine(to: p(0.56, 1))
        path.addLine(to: p(0.44, 1))
        path.addLine(to: p(0.09, 0.82))
        path.addLine(to: p(0.09, 0.18))
        path.closeSubpath()
        return path
    }
}

struct LocationImageView: View {
    let definitionID: String
    var width: CGFloat = 112
    var height: CGFloat = 66

    // "RevealOnN" is a placeholder the game sends before a location is revealed.
    private var isHidden: Bool { definitionID.hasPrefix("RevealOn") }

    var body: some View {
        KFImage(isHidden ? nil : URL(string: "https://static.marvelsnap.pro/locations/\(definitionID).webp"))
            .placeholder {
                // Only the placeholder gets our shape; the real webp already has
                // its own location frame, so we show it natively.
                ZStack {
                    LinearGradient(colors: [.black.opacity(0.55), .purple.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: isHidden ? "questionmark" : "photo")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .clipShape(LocationHexagon())
                .overlay(LocationHexagon().stroke(.purple.opacity(0.6), lineWidth: 1.5))
                .padding(9) // match the glow margin baked into the real location art
            }
            .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 320, height: 200)))
            .cancelOnDisappear(true)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}
