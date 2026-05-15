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
    func canvasView(_ canvasView: OverlayCanvasView, didFinish stroke: Stroke)
}

final class OverlayCanvasView: NSView {
    weak var delegate: OverlayCanvasViewDelegate?

    var tool: ToolMode = .pen
    var strokeColor: NSColor = defaultStrokeColor
    var lineWidth: CGFloat = 6
    var isDrawingEnabled = true
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
        guard isDrawingEnabled else { return }
        activePoints = [convert(event.locationInWindow, from: nil)]
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
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

    override func mouseUp(with event: NSEvent) {
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

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class OverlayWindowController: NSWindowController {
    let canvasView: OverlayCanvasView

    init(screen: NSScreen) {
        canvasView = OverlayCanvasView(frame: NSRect(origin: .zero, size: screen.frame.size))

        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.isMovable = false
        window.acceptsMouseMovedEvents = true
        window.contentView = canvasView

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class OverlayManager: NSObject, OverlayCanvasViewDelegate {
    private(set) var isDrawingEnabled = true
    private(set) var tool: ToolMode = .pen
    private(set) var drawingShape: DrawingShape = .rectangle
    private(set) var strokeColor: NSColor = defaultStrokeColor
    private(set) var lineWidth: CGFloat = 6
    private(set) var isTrailEffectEnabled = true
    private(set) var trailDuration: TimeInterval = 0.5
    var onDrawingStateChanged: ((Bool) -> Void)?

    private var overlayControllers: [OverlayWindowController] = []

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildOverlays),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        rebuildOverlays()
    }

    func setTool(_ tool: ToolMode) {
        self.tool = tool
        syncCanvasSettings()
    }

    func setDrawingShape(_ drawingShape: DrawingShape) {
        self.drawingShape = drawingShape
        syncCanvasSettings()
    }

    func setColor(_ color: NSColor) {
        strokeColor = color
        syncCanvasSettings()
    }

    func setLineWidth(_ width: CGFloat) {
        lineWidth = max(1, width)
        syncCanvasSettings()
    }

    func setTrailEffectEnabled(_ enabled: Bool) {
        isTrailEffectEnabled = enabled
        syncCanvasSettings()
    }

    func setTrailDuration(_ duration: TimeInterval) {
        trailDuration = max(0.25, duration)
        syncCanvasSettings()
    }

    func toggleDrawingEnabled() {
        setDrawingEnabled(!isDrawingEnabled)
    }

    func disableDrawing() {
        setDrawingEnabled(false)
    }

    func setDrawingEnabled(_ enabled: Bool) {
        guard isDrawingEnabled != enabled else { return }

        isDrawingEnabled = enabled
        for controller in overlayControllers {
            controller.canvasView.isDrawingEnabled = isDrawingEnabled
            if !isDrawingEnabled {
                controller.canvasView.cancelActiveStroke()
            }
            controller.window?.ignoresMouseEvents = !isDrawingEnabled
        }
        onDrawingStateChanged?(isDrawingEnabled)
    }

    func clearAll() {
        for controller in overlayControllers {
            controller.canvasView.clearCanvas()
        }
    }

    func undoLastStroke() {
        for controller in overlayControllers.reversed() {
            if !controller.canvasView.strokes.isEmpty {
                controller.canvasView.removeLastStroke()
                return
            }
        }
    }

    @objc
    func rebuildOverlays() {
        for controller in overlayControllers {
            controller.close()
        }
        overlayControllers.removeAll()

        for screen in NSScreen.screens {
            let controller = OverlayWindowController(screen: screen)
            controller.canvasView.delegate = self
            overlayControllers.append(controller)
            syncCanvasSettings(for: controller.canvasView)
            controller.showWindow(nil)
            controller.window?.ignoresMouseEvents = !isDrawingEnabled
            controller.window?.orderFrontRegardless()
        }
    }

    func canvasView(_ canvasView: OverlayCanvasView, didFinish stroke: Stroke) {
        _ = (canvasView, stroke)
    }

    private func syncCanvasSettings() {
        for controller in overlayControllers {
            syncCanvasSettings(for: controller.canvasView)
        }
    }

    private func syncCanvasSettings(for canvasView: OverlayCanvasView) {
        canvasView.tool = tool
        canvasView.drawingShape = drawingShape
        canvasView.strokeColor = strokeColor
        canvasView.lineWidth = lineWidth
        canvasView.isDrawingEnabled = isDrawingEnabled
        canvasView.isTrailEffectEnabled = isTrailEffectEnabled
        canvasView.trailDuration = trailDuration
    }
}

final class ControlPanelController: NSWindowController {
    private let overlayManager: OverlayManager

    private let shapeControl = NSSegmentedControl(
        labels: ["Freehand", "Rectangle"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let modeControl = NSSegmentedControl(
        labels: ["Pen", "Eraser"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let colorWell = NSColorWell()
    private let sizeSlider = NSSlider(value: 6, minValue: 1, maxValue: 32, target: nil, action: nil)
    private let trailToggleButton = NSButton(checkboxWithTitle: "Enable Trail Effect", target: nil, action: nil)
    private let trailTimeLabel = NSTextField(labelWithString: "Trail Disappear Time: 3.0s")
    private let trailTimeSlider = NSSlider(value: 3, minValue: 0.5, maxValue: 10, target: nil, action: nil)
    private let drawingToggleButton = NSButton(title: "Disable Drawing", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let undoButton = NSButton(title: "Undo", target: nil, action: nil)

    init(overlayManager: OverlayManager) {
        self.overlayManager = overlayManager

        let panel = NSPanel(
            contentRect: NSRect(x: 80, y: 120, width: 320, height: 360),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        panel.title = "MacDraw Controls"
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false

        super.init(window: panel)
        panel.contentView = makeContentView()
        configureControls()
        updateDrawingButtonTitle(isEnabled: overlayManager.isDrawingEnabled)
        updateTrailControls()
        overlayManager.onDrawingStateChanged = { [weak self] isEnabled in
            self?.updateDrawingButtonTitle(isEnabled: isEnabled)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeContentView() -> NSView {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 360))

        let shapeLabel = NSTextField(labelWithString: "Shape")
        let toolLabel = NSTextField(labelWithString: "Tool")
        let colorLabel = NSTextField(labelWithString: "Color")
        let sizeLabel = NSTextField(labelWithString: "Brush Size")
        let trailLabel = NSTextField(labelWithString: "Trail Effect")

        let topButtons = NSStackView(views: [undoButton, clearButton])
        topButtons.orientation = .horizontal
        topButtons.distribution = .fillEqually
        topButtons.spacing = 10

        let stack = NSStackView(views: [
            shapeLabel,
            shapeControl,
            toolLabel,
            modeControl,
            colorLabel,
            colorWell,
            sizeLabel,
            sizeSlider,
            trailLabel,
            trailToggleButton,
            trailTimeLabel,
            trailTimeSlider,
            drawingToggleButton,
            topButtons,
        ])

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 80).isActive = true

        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.widthAnchor.constraint(equalToConstant: 180).isActive = true

        shapeControl.translatesAutoresizingMaskIntoConstraints = false
        shapeControl.widthAnchor.constraint(equalToConstant: 220).isActive = true

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16),
            topButtons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sizeSlider.widthAnchor.constraint(equalTo: stack.widthAnchor),
            trailTimeSlider.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        return contentView
    }

    private func configureControls() {
        shapeControl.target = self
        shapeControl.action = #selector(shapeChanged)
        shapeControl.selectedSegment = overlayManager.drawingShape == .freehand ? 0 : 1

        modeControl.target = self
        modeControl.action = #selector(toolModeChanged)
        modeControl.selectedSegment = 0

        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.color = defaultStrokeColor

        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged)

        trailToggleButton.target = self
        trailToggleButton.action = #selector(toggleTrailEffect)
        trailToggleButton.state = overlayManager.isTrailEffectEnabled ? .on : .off

        trailTimeSlider.target = self
        trailTimeSlider.action = #selector(trailDurationChanged)
        trailTimeSlider.doubleValue = overlayManager.trailDuration

        drawingToggleButton.target = self
        drawingToggleButton.action = #selector(toggleDrawing)

        clearButton.target = self
        clearButton.action = #selector(clearCanvas)

        undoButton.target = self
        undoButton.action = #selector(undoLastStroke)
    }

    @objc
    private func toolModeChanged() {
        overlayManager.setTool(modeControl.selectedSegment == 0 ? .pen : .eraser)
    }

    @objc
    private func shapeChanged() {
        overlayManager.setDrawingShape(shapeControl.selectedSegment == 0 ? .freehand : .rectangle)
    }

    @objc
    private func colorChanged() {
        overlayManager.setColor(colorWell.color)
    }

    @objc
    private func sizeChanged() {
        overlayManager.setLineWidth(CGFloat(sizeSlider.doubleValue))
    }

    @objc
    private func toggleTrailEffect() {
        overlayManager.setTrailEffectEnabled(trailToggleButton.state == .on)
        updateTrailControls()
    }

    @objc
    private func trailDurationChanged() {
        overlayManager.setTrailDuration(trailTimeSlider.doubleValue)
        updateTrailControls()
    }

    @objc
    private func toggleDrawing() {
        overlayManager.toggleDrawingEnabled()
    }

    @objc
    private func clearCanvas() {
        overlayManager.clearAll()
    }

    @objc
    private func undoLastStroke() {
        overlayManager.undoLastStroke()
    }

    private func updateDrawingButtonTitle(isEnabled: Bool) {
        drawingToggleButton.title = isEnabled ? "Disable Drawing" : "Enable Drawing"
    }

    private func updateTrailControls() {
        let isEnabled = overlayManager.isTrailEffectEnabled
        trailToggleButton.state = isEnabled ? .on : .off
        trailTimeSlider.doubleValue = overlayManager.trailDuration
        trailTimeSlider.isEnabled = isEnabled
        trailTimeLabel.stringValue = String(
            format: "Trail Disappear Time: %.1fs",
            overlayManager.trailDuration
        )
        trailTimeLabel.textColor = isEnabled ? .labelColor : .secondaryLabelColor
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlayManager = OverlayManager()
    private var controlPanelController: ControlPanelController?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        installKeyMonitor()

        overlayManager.start()

        let controlPanelController = ControlPanelController(overlayManager: overlayManager)
        self.controlPanelController = controlPanelController
        controlPanelController.showWindow(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit MacDraw",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.overlayManager.disableDrawing()
            return nil
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
