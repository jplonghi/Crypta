import SwiftUI

/// Packs tags at their measured width instead of spreading them across grid columns.
struct TagFlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(1, proposal.width ?? .infinity)
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
        return Self.arrange(sizes, width: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = max(1, bounds.width)
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
        let positions = Self.arrange(sizes, width: width).positions
        for index in subviews.indices {
            subviews[index].place(at: CGPoint(x: bounds.minX + positions[index].x,
                                             y: bounds.minY + positions[index].y),
                                  anchor: .topLeading, proposal: ProposedViewSize(sizes[index]))
        }
    }

    static func arrange(_ sizes: [CGSize], width: CGFloat) -> (size: CGSize, positions: [CGPoint]) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        var positions: [CGPoint] = []
        for size in sizes {
            if x > 0, x + size.width > width {
                x = 0; y += rowHeight + 6; rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            usedWidth = max(usedWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + 6
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), positions)
    }
}
