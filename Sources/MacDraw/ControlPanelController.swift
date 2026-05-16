import AppKit

final class ControlPanelController: NSWindowController, NSWindowDelegate {
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
    private let trailToggleSwitch = NSSwitch()
    private let trailToggleLabel = NSTextField(labelWithString: "Enable Trail Effect")
    private let trailTimeLabel = NSTextField(labelWithString: "Trail Disappear Time: 0.5s")
    private let trailTimeSlider = NSSlider(value: 3, minValue: 0.5, maxValue: 10, target: nil, action: nil)
    private let drawingToggleButton = NSButton(title: "Lock Drawing On", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let undoButton = NSButton(title: "Undo", target: nil, action: nil)

    init(overlayManager: OverlayManager) {
        self.overlayManager = overlayManager

        let panel = NSWindow(
            contentRect: NSRect(x: 80, y: 120, width: 235, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        panel.title = "MacDraw Controls"
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .visible

        super.init(window: panel)
        panel.delegate = self
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

    func windowWillMiniaturize(_ notification: Notification) {
        overlayManager.hideOverlays()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        overlayManager.showOverlays()
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
        overlayManager.setTrailEffectEnabled(trailToggleSwitch.state == .on)
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
        sizeSlider.isContinuous = true

        trailToggleSwitch.target = self
        trailToggleSwitch.action = #selector(toggleTrailEffect)
        trailToggleSwitch.state = overlayManager.isTrailEffectEnabled ? .on : .off

        trailTimeSlider.target = self
        trailTimeSlider.action = #selector(trailDurationChanged)
        trailTimeSlider.doubleValue = overlayManager.trailDuration
        trailTimeSlider.isContinuous = true

        drawingToggleButton.target = self
        drawingToggleButton.action = #selector(toggleDrawing)
        drawingToggleButton.bezelStyle = .rounded

        clearButton.target = self
        clearButton.action = #selector(clearCanvas)
        clearButton.bezelStyle = .rounded

        undoButton.target = self
        undoButton.action = #selector(undoLastStroke)
        undoButton.bezelStyle = .rounded
    }

    private func updateDrawingButtonTitle(isEnabled: Bool) {
        drawingToggleButton.title = isEnabled ? "Return to Standby" : "Lock Drawing On"
    }

    private func updateTrailControls() {
        let isEnabled = overlayManager.isTrailEffectEnabled
        trailToggleSwitch.state = isEnabled ? .on : .off
        trailTimeSlider.doubleValue = overlayManager.trailDuration
        trailTimeSlider.isEnabled = isEnabled
        trailTimeLabel.stringValue = String(
            format: "Trail Disappear Time: %.1fs",
            overlayManager.trailDuration
        )
        trailTimeLabel.textColor = isEnabled ? .labelColor : .secondaryLabelColor
    }

    private func makeContentView() -> NSView {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 235, height: 360))

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.spacing = 12
        rootStack.alignment = .leading
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        rootStack.addArrangedSubview(makeVerticalField(title: "Shape", control: shapeControl))
        rootStack.addArrangedSubview(makeVerticalField(title: "Tool", control: modeControl))
        rootStack.addArrangedSubview(makeVerticalField(title: "Color", control: colorWell))
        rootStack.addArrangedSubview(makeVerticalField(title: "Brush Size", control: sizeSlider))
        rootStack.addArrangedSubview(makeVerticalField(title: "Trail", control: makeTrailToggleRow()))
        rootStack.addArrangedSubview(trailTimeLabel)
        rootStack.addArrangedSubview(trailTimeSlider)
        rootStack.addArrangedSubview(makeVerticalField(title: "Actions", control: makeActionsRow()))
        rootStack.addArrangedSubview(drawingToggleButton)

        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),

            shapeControl.widthAnchor.constraint(equalToConstant: 170),
            modeControl.widthAnchor.constraint(equalToConstant: 140),
            colorWell.widthAnchor.constraint(equalToConstant: 96),
            sizeSlider.widthAnchor.constraint(equalToConstant: 170),
            trailTimeSlider.widthAnchor.constraint(equalToConstant: 170),
            drawingToggleButton.widthAnchor.constraint(equalToConstant: 150),
        ])

        return contentView
    }

    private func makeFieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func makeTrailToggleRow() -> NSView {
        let stack = NSStackView(views: [trailToggleSwitch, trailToggleLabel])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        return stack
    }

    private func makeActionsRow() -> NSView {
        let stack = NSStackView(views: [undoButton, clearButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        return stack
    }

    private func makeVerticalField(title: String, control: NSView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        stack.addArrangedSubview(makeFieldLabel(title))
        stack.addArrangedSubview(control)
        return stack
    }
}
