import Foundation
import CoreGraphics

enum AnnotationTool: String, CaseIterable {
    case select = "Select"
    case rectangle = "Rectangle"
    case arrow = "Arrow"

    var shortcut: String {
        switch self {
        case .select: return "V"
        case .rectangle: return "R"
        case .arrow: return "A"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .select: return 9      // V
        case .rectangle: return 15  // R
        case .arrow: return 0       // A
        }
    }
}

protocol Annotation: AnyObject {
    var id: UUID { get }
    var bounds: CGRect { get set }
    var color: CGColor { get set }
    var strokeWidth: CGFloat { get set }

    func draw(in context: CGContext)
    func contains(point: CGPoint) -> Bool
    func hitTest(point: CGPoint) -> AnnotationHandle?
}

enum AnnotationHandle {
    case body
    case topLeft, topRight, bottomLeft, bottomRight
    case top, bottom, left, right
    case startPoint, endPoint  // For arrows
}

extension Annotation {
    func contains(point: CGPoint) -> Bool {
        return bounds.contains(point)
    }

    func hitTest(point: CGPoint) -> AnnotationHandle? {
        let handleSize: CGFloat = 10

        // Check corners
        let blRect = CGRect(
            x: bounds.minX - handleSize/2, y: bounds.minY - handleSize/2,
            width: handleSize, height: handleSize
        )
        if blRect.contains(point) {
            return .bottomLeft
        }
        let brRect = CGRect(
            x: bounds.maxX - handleSize/2, y: bounds.minY - handleSize/2,
            width: handleSize, height: handleSize
        )
        if brRect.contains(point) {
            return .bottomRight
        }
        let tlRect = CGRect(
            x: bounds.minX - handleSize/2, y: bounds.maxY - handleSize/2,
            width: handleSize, height: handleSize
        )
        if tlRect.contains(point) {
            return .topLeft
        }
        let trRect = CGRect(
            x: bounds.maxX - handleSize/2, y: bounds.maxY - handleSize/2,
            width: handleSize, height: handleSize
        )
        if trRect.contains(point) {
            return .topRight
        }

        // Check body
        if bounds.contains(point) {
            return .body
        }

        return nil
    }
}
