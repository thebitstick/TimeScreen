import CoreGraphics

struct PreviewZoom: Equatable {
    static let range: ClosedRange<CGFloat> = 1...6

    private(set) var scale: CGFloat = 1
    private(set) var offset: CGSize = .zero

    var isZoomed: Bool { scale > 1.001 }

    mutating func set(scale proposed: CGFloat, in size: CGSize) {
        scale = min(max(proposed, Self.range.lowerBound), Self.range.upperBound)
        offset = clamped(offset, in: size)
    }

    mutating func zoom(by factor: CGFloat, in size: CGSize) {
        set(scale: scale * factor, in: size)
    }

    mutating func pan(to proposed: CGSize, in size: CGSize) {
        offset = clamped(proposed, in: size)
    }

    mutating func reset() {
        scale = 1
        offset = .zero
    }

    /// The zoomed image never moves far enough to uncover the edge of the view.
    func clamped(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let limitX = (scale - 1) * size.width / 2
        let limitY = (scale - 1) * size.height / 2
        return CGSize(width: min(max(proposed.width, -limitX), limitX), height: min(max(proposed.height, -limitY), limitY))
    }
}
