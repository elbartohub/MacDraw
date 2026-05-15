# MacDraw

MacDraw is a native macOS desktop overlay app that lets you draw directly on top of the screen with a transparent canvas.

Traditional Chinese user manual: [使用手冊_繁體中文.md](/Volumes/SSD_C/AI/Codex/MacDraw/使用手冊_繁體中文.md)

## Features

- Transparent overlay across every connected display
- Freehand pen and eraser tools
- Shape switch for freehand or rectangle drawing
- Brush color and size controls
- Undo and clear actions
- Click-through toggle so you can stop intercepting mouse input
- Escape key instantly disables drawing
- Optional trail effect with adjustable disappear time

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

- The control window stays above the drawing overlay so you can re-enable drawing after switching to click-through mode.
- If your monitor layout changes while the app is open, the overlay windows are rebuilt for the new screen arrangement.
