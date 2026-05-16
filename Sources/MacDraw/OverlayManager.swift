import AppKit

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
    private(set) var isDrawingEnabled = false
    private(set) var tool: ToolMode = .pen
    private(set) var drawingShape: DrawingShape = .rectangle
    private(set) var strokeColor: NSColor = defaultStrokeColor
    private(set) var lineWidth: CGFloat = 6
    private(set) var isTrailEffectEnabled = true
    private(set) var trailDuration: TimeInterval = 0.5
    private(set) var areOverlaysVisible = true

    private var isTemporaryDrawingEnabled = false
    private var isStrokeInProgress = false
    private var overlayControllers: [OverlayWindowController] = []

    var onDrawingStateChanged: ((Bool) -> Void)?

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

    func setTemporaryDrawingEnabled(_ enabled: Bool) {
        guard isTemporaryDrawingEnabled != enabled else { return }
        isTemporaryDrawingEnabled = enabled
        syncCanvasSettings()
    }

    func toggleDrawingEnabled() {
        setDrawingEnabled(!isDrawingEnabled)
    }

    func disableDrawing() {
        isTemporaryDrawingEnabled = false
        isStrokeInProgress = false
        setDrawingEnabled(false)
    }

    func setDrawingEnabled(_ enabled: Bool) {
        guard isDrawingEnabled != enabled else { return }

        isDrawingEnabled = enabled
        if !currentDrawingInputEnabled {
            for controller in overlayControllers {
                controller.canvasView.cancelActiveStroke()
            }
        }
        syncCanvasSettings()
        onDrawingStateChanged?(isDrawingEnabled)
    }

    func clearAll() {
        for controller in overlayControllers {
            controller.canvasView.clearCanvas()
        }
    }

    func hideOverlays() {
        guard areOverlaysVisible else { return }
        areOverlaysVisible = false
        for controller in overlayControllers {
            controller.window?.orderOut(nil)
        }
    }

    func showOverlays() {
        guard !areOverlaysVisible else { return }
        areOverlaysVisible = true
        for controller in overlayControllers {
            controller.showWindow(nil)
            controller.window?.orderFrontRegardless()
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

    func canvasViewDidBeginStroke(_ canvasView: OverlayCanvasView) {
        _ = canvasView
        isStrokeInProgress = true
        syncCanvasSettings()
    }

    func canvasView(_ canvasView: OverlayCanvasView, didFinish stroke: Stroke) {
        _ = (canvasView, stroke)
    }

    func canvasViewDidEndStroke(_ canvasView: OverlayCanvasView) {
        _ = canvasView
        isStrokeInProgress = false
        syncCanvasSettings()
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
            if areOverlaysVisible {
                controller.showWindow(nil)
                controller.window?.orderFrontRegardless()
            }
        }
    }

    private func syncCanvasSettings() {
        for controller in overlayControllers {
            syncCanvasSettings(for: controller.canvasView)
        }
    }

    private func syncCanvasSettings(for canvasView: OverlayCanvasView) {
        let drawingInputEnabled = currentDrawingInputEnabled
        canvasView.tool = tool
        canvasView.drawingShape = drawingShape
        canvasView.strokeColor = strokeColor
        canvasView.lineWidth = lineWidth
        canvasView.isDrawingEnabled = drawingInputEnabled
        canvasView.isTrailEffectEnabled = isTrailEffectEnabled
        canvasView.trailDuration = trailDuration
        canvasView.window?.ignoresMouseEvents = !drawingInputEnabled
    }

    private var currentDrawingInputEnabled: Bool {
        isDrawingEnabled || isTemporaryDrawingEnabled || isStrokeInProgress
    }
}
