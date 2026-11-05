import Foundation
import CoreGraphics

// MARK: - Chat anchoring

/// Which side of its head bubble a chat opens on.
///
/// `automatic` is not "no choice": it is a choice to re-decide on every layout pass, which is what keeps a
/// chat visible when its head is dragged into a corner or onto a screen with less room.
enum ChatAnchor: String, Codable, CaseIterable, Equatable {
    case automatic
    case right
    case left
    case bottom
    case top

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .right: return "Right"
        case .left: return "Left"
        case .bottom: return "Below"
        case .top: return "Above"
        }
    }

    /// Sides a fixed anchor never falls back from, and the order `automatic` tries them in.
    ///
    /// Left before right: a fresh bubble is parked against the right edge of the screen
    /// (`defaultOrigin`), so the right side is usually the one with no room.
    static let automaticOrder: [ChatAnchor] = [.left, .right, .bottom, .top]
}

enum Anchoring {
    /// Space between the head's edge and the chat's edge.
    static let gap: CGFloat = 10

    /// Where a chat of `size` sits relative to `head`.
    ///
    /// Pure geometry so it can be asserted in the self-test: no screens, no windows, no AppKit. `screen` is
    /// the frame the result must fit inside, which the caller supplies — the visible frame of the head's
    /// screen, or a synthetic rectangle in tests.
    ///
    /// A fixed anchor is honoured even when it clips, because the user asked for that side; clamping then
    /// keeps the chat on screen rather than letting it hang off. `automatic` prefers the first side in
    /// `ChatAnchor.automaticOrder` whose rect needs no clamping, and otherwise picks the side with the most
    /// overlap before clamping, so the chat lands where there is actually room.
    static func rect(head: CGRect, size: CGSize, anchor: ChatAnchor, screen: CGRect, gap: CGFloat = gap) -> CGRect {
        // A fixed side is honoured even when it clips: the user picked it, so switching sides would be a
        // surprise. Clamping only slides the chat back onto the screen.
        if anchor != .automatic {
            return clamp(unclamped(head: head, size: size, side: anchor, gap: gap), to: screen)
        }

        let sides: [ChatAnchor] = ChatAnchor.automaticOrder
        // Ranked, not merely measured: a side that needs no sliding wins outright, then a side whose
        // clamped rect still leaves the head uncovered, and only then the one showing the most chat. Covering
        // the head is the one outcome to avoid — it is the thing the user grabs to move the pair.
        var best: CGRect?
        var bestRank: (clear: Bool, visible: CGFloat) = (false, -1)

        for side in sides {
            let candidate = unclamped(head: head, size: size, side: side, gap: gap)
            if candidate.minX >= screen.minX, candidate.maxX <= screen.maxX,
               candidate.minY >= screen.minY, candidate.maxY <= screen.maxY {
                return candidate
            }
            let clamped = clamp(candidate, to: screen)
            let rank = (clear: overlapArea(clamped, head) == 0, visible: overlapArea(clamped, screen))
            if rank.clear != bestRank.clear {
                if rank.clear { best = clamped; bestRank = rank }
            } else if rank.visible > bestRank.visible {
                best = clamped
                bestRank = rank
            }
        }

        if let best { return best }
        return clamp(unclamped(head: head, size: size, side: .left, gap: gap), to: screen)
    }

    /// The rect for one side, centred on the head's perpendicular axis.
    static func unclamped(head: CGRect, size: CGSize, side: ChatAnchor, gap: CGFloat = gap) -> CGRect {
        switch side {
        case .right:
            return CGRect(x: head.maxX + gap, y: head.midY - size.height / 2, width: size.width, height: size.height)
        case .left:
            return CGRect(x: head.minX - gap - size.width, y: head.midY - size.height / 2, width: size.width, height: size.height)
        case .bottom:
            return CGRect(x: head.midX - size.width / 2, y: head.minY - gap - size.height, width: size.width, height: size.height)
        case .top:
            return CGRect(x: head.midX - size.width / 2, y: head.maxY + gap, width: size.width, height: size.height)
        case .automatic:
            return unclamped(head: head, size: size, side: .left, gap: gap)
        }
    }

    /// Slides a rect back inside `screen`, keeping its size. A rect larger than the screen is pinned to the
    /// screen's origin edge rather than being shrunk: the caller owns the size, and shrinking here would
    /// make the chat smaller every time the head moved near a screen edge.
    static func clamp(_ rect: CGRect, to screen: CGRect) -> CGRect {
        var result = rect
        result.origin.x = min(max(rect.minX, screen.minX), max(screen.minX, screen.maxX - rect.width))
        result.origin.y = min(max(rect.minY, screen.minY), max(screen.minY, screen.maxY - rect.height))
        return result
    }

    static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        return intersection.width * intersection.height
    }
}

// MARK: - Edge resizing

/// Which edges of a panel a resize gesture is dragging. The opposite edges stay put.
struct ResizeEdges: OptionSet, Equatable {
    let rawValue: Int
    static let left = ResizeEdges(rawValue: 1 << 0)
    static let right = ResizeEdges(rawValue: 1 << 1)
    static let top = ResizeEdges(rawValue: 1 << 2)
    static let bottom = ResizeEdges(rawValue: 1 << 3)

    static let all: ResizeEdges = [.left, .right, .top, .bottom]

    var isHorizontal: Bool { contains(.left) || contains(.right) }
    var isVertical: Bool { contains(.top) || contains(.bottom) }
}

enum ResizeGeometry {
    /// How close to an edge a press must be to grab it. Wide enough for a trackpad, narrow enough that the
    /// bubble's own buttons keep their clicks.
    static let band: CGFloat = 9

    static func edges(at point: CGPoint, in bounds: CGRect, band: CGFloat = band) -> ResizeEdges {
        var edges: ResizeEdges = []
        if point.x - bounds.minX <= band { edges.insert(.left) }
        if bounds.maxX - point.x <= band { edges.insert(.right) }
        if point.y - bounds.minY <= band { edges.insert(.bottom) }
        if bounds.maxY - point.y <= band { edges.insert(.top) }
        return edges
    }

    /// The frame a drag produces. `frame` is the frame at gesture start, `delta` the pointer's travel since
    /// then, so the result is always computed from the start rather than accumulated — no drift, and
    /// dragging back to the start returns the original frame exactly.
    static func resized(
        _ frame: CGRect,
        edges: ResizeEdges,
        by delta: CGSize,
        min minSize: CGSize,
        max maxSize: CGSize
    ) -> CGRect {
        guard !edges.isEmpty else { return frame }
        var result = frame

        if edges.isHorizontal {
            var width = frame.width
            if edges.contains(.left) { width -= delta.width } else { width += delta.width }
            width = min(max(width, minSize.width), maxSize.width)
            result.size.width = width
            result.origin.x = edges.contains(.left) ? frame.maxX - width : frame.minX
        }

        if edges.isVertical {
            var height = frame.height
            if edges.contains(.bottom) { height -= delta.height } else { height += delta.height }
            height = min(max(height, minSize.height), maxSize.height)
            result.size.height = height
            result.origin.y = edges.contains(.bottom) ? frame.maxY - height : frame.minY
        }

        return result
    }
}
