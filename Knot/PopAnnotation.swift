import SwiftUI
import CoreGraphics

/// Annotation tool kinds.
enum AnnoKind: String, CaseIterable, Identifiable {
    // `move` is not a drawing tool: it pans the whole frozen capture so an off-center
    // selection can be dragged to the middle of the screen.
    case move, arrow, line, rect, ellipse, pen, text, blur
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .move:    return "arrow.up.and.down.and.arrow.left.and.right"
        case .arrow:   return "arrow.up.right"
        case .line:    return "line.diagonal"
        case .rect:    return "rectangle"
        case .ellipse: return "circle"
        case .pen:     return "scribble.variable"
        case .text:    return "character"
        case .blur:    return "mosaic"
        }
    }

    /// Localized tooltip label.
    var label: String {
        switch self {
        case .move:    return String(localized: "移动")
        case .arrow:   return String(localized: "箭头")
        case .line:    return String(localized: "直线")
        case .rect:    return String(localized: "方框")
        case .ellipse: return String(localized: "圆圈")
        case .pen:     return String(localized: "画笔")
        case .text:    return String(localized: "文字")
        case .blur:    return String(localized: "马赛克")
        }
    }
}

/// A single annotation. Geometry is stored in normalized [0,1] coordinates relative
/// to the original image, so it survives any preview scaling. Line width / font size
/// are in original-image points and get scaled at render time.
struct Annotation: Identifiable {
    var id = UUID()
    var kind: AnnoKind
    var color: Color
    var lineWidth: CGFloat = 4        // original-image points
    var fontSize: CGFloat = 22        // original-image points (text only)

    var start: CGPoint = .zero        // normalized
    var end: CGPoint = .zero          // normalized
    var points: [CGPoint] = []        // normalized (pen)
    var text: String = ""

    /// Whether this annotation is worth keeping (filters out accidental taps).
    var isMeaningful: Bool {
        switch kind {
        case .pen:  return points.count > 2
        case .text: return !text.isEmpty
        default:    return hypot(end.x - start.x, end.y - start.y) > 0.008
        }
    }
}

/// Annotation color palette.
enum Palette {
    static let red = Color(red: 0.95, green: 0.23, blue: 0.19)
    static let orange = Color(red: 1.0, green: 0.58, blue: 0.0)
    static let yellow = Brand.cornYellow
    static let green = Brand.leafGreen
    static let blue = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let charcoal = Brand.charcoal
    static let white = Color.white

    static let all: [Color] = [red, orange, yellow, green, blue, charcoal, white]
}
