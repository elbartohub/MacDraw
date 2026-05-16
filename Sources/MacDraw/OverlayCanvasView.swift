import AppKit
import CoreGraphics

final class OverlayCanvasView: NSView {
    weak var delegate: OverlayCanvasViewDelegate?

    var tool: ToolMode = .pen
    var strokeColor: NSColor = defaultStrokeColor
    var lineWidth: CGFloat = 6
    var isDrawingEnabled = false
    var drawingShape: DrawingShape = .rectangle
    var isTrailEffectEnabled = true
    var trailDuration: TimeInterval = 0.5

    private(set) var strokes: [Stroke] = []
    private var activePoints: [CGPoint] = []
    private var trailTimer: Timer?

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let now = Date()

        context.saveGState()
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        for stroke in strokes {
            render(stroke: stroke, in: context, referenceDate: now)
        }

        if !activePoints.isEmpty {
            let previewStroke = Stroke(
                points: activePoints,
                color: strokeColor,
                lineWidth: lineWidth,
                tool: tool,
                shape: drawingShape,
                createdAt: now,
                tailDuration: nil
            )
            render(stroke: previewStroke, in: context, referenceDate: now)
        }

        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        handlePointerDown(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        handlePointerDown(event)
    }

    override func mouseDragged(with event: NSEvent) {
        handlePointerDragged(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        handlePointerDragged(event)
    }

    override func mouseUp(with event: NSEvent) {
        handlePointerUp(event)
    }

    override func rightMouseUp(with event: NSEvent) {
        handlePointerUp(event)
    }

    func removeLastStroke() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
        updateTrailTimerIfNeeded()
        needsDisplay = true
    }

    func clearCanvas() {
        strokes.removeAll()
        activePoints.removeAll()
        stopTrailTimer()
        needsDisplay = true
    }

    func cancelActiveStroke() {
        guard !activePoints.isEmpty else { return }
        activePoints.removeAll()
        needsDisplay = true
    }

    private func handlePointerDown(_ event: NSEvent) {
        guard isDrawingEnabled else { return }
        activePoints = [convert(event.locationInWindow, from: nil)]
        delegate?.canvasViewDidBeginStroke(self)
        needsDisplay = true
    }

    private func handlePointerDragged(_ event: NSEvent) {
        guard isDrawingEnabled, !activePoints.isEmpty else { return }
        let currentPoint = convert(event.locationInWindow, from: nil)

        switch drawingShape {
        case .freehand:
            activePoints.append(currentPoint)
        case .rectangle:
            activePoints = [activePoints[0], currentPoint]
        }

        needsDisplay = true
    }

    private func handlePointerUp(_ event: NSEvent) {
        guard isDrawingEnabled, !activePoints.isEmpty else { return }

        let endPoint = convert(event.locationInWindow, from: nil)
        switch drawingShape {
        case .freehand:
            activePoints.append(endPoint)
        case .rectangle:
            activePoints = [activePoints[0], endPoint]
        }

        let stroke = Stroke(
            points: activePoints,
            color: strokeColor,
            lineWidth: lineWidth,
            tool: tool,
            shape: drawingShape,
            createdAt: Date(),
            tailDuration: isTrailEffectEnabled ? trailDuration : nil
        )
        strokes.append(stroke)
        activePoints.removeAll()
        updateTrailTimerIfNeeded()
        needsDisplay = true
        delegate?.canvasView(self, didFinish: stroke)
        delegate?.canvasViewDidEndStroke(self)
    }

    private func render(stroke: Stroke, in context: CGContext, referenceDate: Date) {
        let disappearanceProgress = disappearanceProgress(for: stroke, referenceDate: referenceDate)
        let drawablePoints = drawablePoints(for: stroke)
        let visiblePoints = visiblePoints(
            for: drawablePoints,
            isTransient: stroke.tailDuration != nil,
            disappearanceProgress: disappearanceProgress
        )
        guard let firstPoint = visiblePoints.first else { return }

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(stroke.lineWidth)
        context.setAlpha(opacity(for: stroke, disappearanceProgress: disappearanceProgress))
        context.setBlendMode(stroke.tool == .eraser ? .clear : .normal)
        context.setStrokeColor(
            stroke.tool == .eraser ? NSColor.clear.cgColor : stroke.color.cgColor
        )

        context.beginPath()
        context.move(to: firstPoint)

        if visiblePoints.count == 1 {
            context.addLine(to: CGPoint(x: firstPoint.x + 0.1, y: firstPoint.y + 0.1))
        } else {
            for point in visiblePoints.dropFirst() {
                context.addLine(to: point)
            }
        }

        context.strokePath()
        context.restoreGState()
    }

    private func disappearanceProgress(for stroke: Stroke, referenceDate: Date) -> CGFloat {
        guard let tailDuration = stroke.tailDuration else { return 0 }
        let progress = referenceDate.timeIntervalSince(stroke.createdAt) / tailDuration
        return CGFloat(max(0, min(1, progress)))
    }

    private func opacity(for stroke: Stroke, disappearanceProgress: CGFloat) -> CGFloat {
        guard stroke.tailDuration != nil else { return 1 }
        return max(0.2, 1 - disappearanceProgress * 0.8)
    }

    private func drawablePoints(for stroke: Stroke) -> [CGPoint] {
        switch stroke.shape {
        case .freehand:
            return stroke.points
        case .rectangle:
            return roundedRectanglePathPoints(from: stroke.points)
        }
    }

    private func roundedRectanglePathPoints(from points: [CGPoint]) -> [CGPoint] {
        guard let start = points.first else { return [] }
        let end = points.count > 1 ? points[1] : start

        let minX = min(start.x, end.x)
        let maxX = max(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxY = max(start.y, end.y)
        let width = maxX - minX
        let height = maxY - minY

        guard width > 0, height > 0 else {
            return [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: maxY)]
        }

        let radius = min(18, width / 2, height / 2)
        guard radius > 0 else {
            let topLeft = CGPoint(x: minX, y: maxY)
            let topRight = CGPoint(x: maxX, y: maxY)
            let bottomRight = CGPoint(x: maxX, y: minY)
            let bottomLeft = CGPoint(x: minX, y: minY)
            return [topLeft, topRight, bottomRight, bottomLeft, topLeft]
        }

        let topLeftCenter = CGPoint(x: minX + radius, y: maxY - radius)
        let topRightCenter = CGPoint(x: maxX - radius, y: maxY - radius)
        let bottomRightCenter = CGPoint(x: maxX - radius, y: minY + radius)
        let bottomLeftCenter = CGPoint(x: minX + radius, y: minY + radius)

        var pathPoints: [CGPoint] = [
            CGPoint(x: minX + radius, y: maxY),
            CGPoint(x: maxX - radius, y: maxY),
        ]

        pathPoints += arcPoints(
            center: topRightCenter,
            radius: radius,
            startAngle: .pi / 2,
            endAngle: 0
        )
        pathPoints.append(CGPoint(x: maxX, y: minY + radius))
        pathPoints += arcPoints(
            center: bottomRightCenter,
            radius: radius,
            startAngle: 0,
            endAngle: -.pi / 2
        )
        pathPoints.append(CGPoint(x: minX + radius, y: minY))
        pathPoints += arcPoints(
            center: bottomLeftCenter,
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: -.pi
        )
        pathPoints.append(CGPoint(x: minX, y: maxY - radius))
        pathPoints += arcPoints(
            center: topLeftCenter,
            radius: radius,
            startAngle: .pi,
            endAngle: .pi / 2
        )

        if let firstPoint = pathPoints.first {
            pathPoints.append(firstPoint)
        }

        return pathPoints
    }

    private func arcPoints(
        center: CGPoint,
        radius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat,
        steps: Int = 8
    ) -> [CGPoint] {
        (0...steps).map { step in
            let progress = CGFloat(step) / CGFloat(steps)
            let angle = startAngle + ((endAngle - startAngle) * progress)
            return CGPoint(
                x: center.x + (cos(angle) * radius),
                y: center.y + (sin(angle) * radius)
            )
        }
    }

    private func visiblePoints(
        for points: [CGPoint],
        isTransient: Bool,
        disappearanceProgress: CGFloat
    ) -> [CGPoint] {
        guard isTransient else { return points }
        guard disappearanceProgress > 0 else { return points }
        guard disappearanceProgress < 1 else { return [] }
        guard points.count > 1 else { return points }

        let totalLength = pathLength(for: points)
        guard totalLength > 0 else { return points }

        let keepLength = totalLength * (1 - disappearanceProgress)
        let trimLengthPerSide = (totalLength - keepLength) / 2
        guard keepLength > 0 else { return [] }

        return trimPath(points: points, startTrim: trimLengthPerSide, endTrim: trimLengthPerSide)
    }

    private func trimPath(points: [CGPoint], startTrim: CGFloat, endTrim: CGFloat) -> [CGPoint] {
        guard points.count > 1 else { return points }

        let totalLength = pathLength(for: points)
        let startDistance = max(0, min(totalLength, startTrim))
        let endDistance = max(startDistance, min(totalLength, totalLength - endTrim))

        guard endDistance > startDistance else { return [] }

        return subpath(points: points, from: startDistance, to: endDistance)
    }

    private func subpath(points: [CGPoint], from startDistance: CGFloat, to endDistance: CGFloat) -> [CGPoint] {
        guard points.count > 1 else { return points }

        var result: [CGPoint] = []
        var traversed: CGFloat = 0

        for index in 1..<points.count {
            let segmentStart = points[index - 1]
            let segmentEnd = points[index]
            let segmentLength = distance(from: segmentStart, to: segmentEnd)
            let segmentRangeStart = traversed
            let segmentRangeEnd = traversed + segmentLength

            if segmentLength == 0 {
                traversed = segmentRangeEnd
                continue
            }

            if segmentRangeEnd < startDistance {
                traversed = segmentRangeEnd
                continue
            }

            if segmentRangeStart > endDistance {
                break
            }

            let localStart = max(startDistance, segmentRangeStart)
            let localEnd = min(endDistance, segmentRangeEnd)

            if localEnd < localStart {
                traversed = segmentRangeEnd
                continue
            }

            let startProgress = (localStart - segmentRangeStart) / segmentLength
            let endProgress = (localEnd - segmentRangeStart) / segmentLength

            let trimmedStart = interpolate(from: segmentStart, to: segmentEnd, progress: startProgress)
            let trimmedEnd = interpolate(from: segmentStart, to: segmentEnd, progress: endProgress)

            if result.isEmpty || distance(from: result[result.count - 1], to: trimmedStart) > 0.01 {
                result.append(trimmedStart)
            }

            if distance(from: result[result.count - 1], to: trimmedEnd) > 0.01 {
                result.append(trimmedEnd)
            }

            traversed = segmentRangeEnd

            if segmentRangeEnd >= endDistance {
                break
            }
        }

        return result
    }

    private func pathLength(for points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }

        var total: CGFloat = 0
        for index in 1..<points.count {
            total += distance(from: points[index - 1], to: points[index])
        }
        return total
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func interpolate(from start: CGPoint, to end: CGPoint, progress: CGFloat) -> CGPoint {
        CGPoint(
            x: start.x + ((end.x - start.x) * progress),
            y: start.y + ((end.y - start.y) * progress)
        )
    }

    private func updateTrailTimerIfNeeded() {
        let hasTransientStrokes = strokes.contains { $0.tailDuration != nil }
        if hasTransientStrokes, trailTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.refreshTrailStrokes()
            }
            trailTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            return
        }

        if !hasTransientStrokes {
            stopTrailTimer()
        }
    }

    private func stopTrailTimer() {
        trailTimer?.invalidate()
        trailTimer = nil
    }

    private func refreshTrailStrokes() {
        let now = Date()
        let beforeCount = strokes.count
        strokes.removeAll { stroke in
            guard let tailDuration = stroke.tailDuration else { return false }
            return now.timeIntervalSince(stroke.createdAt) >= tailDuration
        }

        if strokes.count != beforeCount || strokes.contains(where: { $0.tailDuration != nil }) {
            needsDisplay = true
        }

        updateTrailTimerIfNeeded()
    }
}
