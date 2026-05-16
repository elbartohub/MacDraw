import AppKit
import CoreGraphics

let defaultStrokeColor = NSColor(
    calibratedRed: 1.0,
    green: 176.0 / 255.0,
    blue: 0.0,
    alpha: 1.0
)

enum ToolMode {
    case pen
    case eraser
}

enum DrawingShape {
    case freehand
    case rectangle
}

struct Stroke {
    let points: [CGPoint]
    let color: NSColor
    let lineWidth: CGFloat
    let tool: ToolMode
    let shape: DrawingShape
    let createdAt: Date
    let tailDuration: TimeInterval?
}

protocol OverlayCanvasViewDelegate: AnyObject {
    func canvasViewDidBeginStroke(_ canvasView: OverlayCanvasView)
    func canvasView(_ canvasView: OverlayCanvasView, didFinish stroke: Stroke)
    func canvasViewDidEndStroke(_ canvasView: OverlayCanvasView)
}
