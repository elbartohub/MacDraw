<p align="center">
  <img src="images/MacDraw_hero_clean_github.png" alt="MacDraw preview" width="800">
</p>

# MacDraw

MacDraw is a native macOS desktop overlay app that lets you draw directly on top of the screen with a transparent canvas.

Traditional Chinese user manual: [使用手冊_繁體中文.md](/Volumes/SSD_C/AI/Codex/MacDraw/使用手冊_繁體中文.md)

## Features

- Native macOS AppKit control panel
- Transparent overlay across every connected display
- Freehand pen and eraser tools
- Shape switch for freehand or rectangle drawing
- Brush color and size controls
- Undo and clear actions
- Standby mode by default
- Hold `Control` and click or drag to draw temporarily
- Escape key instantly disables drawing
- Optional trail effect with adjustable disappear time

## Interaction

- The app starts in standby mode
- Hold `Control` and click or drag to draw temporarily
- Use `Lock Drawing On` if you want persistent drawing mode
- Press `Escape` to return to non-drawing state immediately

## Build

```bash
./scripts/build-app.sh
```

The app bundle will be created at `build/MacDraw.app`.

## Run

```bash
./build/bin/MacDraw
```

If macOS rejects the `.app` bundle in your environment, run the binary directly as shown above. The build still produces `build/MacDraw.app`, but direct binary launch is the reliable path here.

## Notes

- The control window stays above the drawing overlay so you can quickly switch modes.
- If your monitor layout changes while the app is open, the overlay windows are rebuilt for the new screen arrangement.

## Source Layout

- `Shared.swift`: shared drawing types and protocol
- `OverlayCanvasView.swift`: drawing canvas and trail rendering
- `OverlayManager.swift`: overlay windows and drawing state
- `ControlPanelController.swift`: native macOS control panel UI
- `AppDelegate.swift`: app lifecycle and keyboard handling
- `main.swift`: app entry point
