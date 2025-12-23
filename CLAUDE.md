# Decktty - Claude Code Instructions

This is **Decktty**, a fork of [Ghostty](https://github.com/ghostty-org/ghostty) that adds a visual deck view (tab sidebar with live previews).

## Custom Feature: Tab Sidebar with Live Previews

The main feature of this fork is the **Tab Sidebar** - a visual sidebar that shows live miniature previews of all terminal tabs. This allows users to see what's happening across all terminals at a glance.

### Custom Files (DO NOT OVERWRITE)

These files are **new to this fork** and don't exist in upstream Ghostty:

```
macos/Sources/Features/TabSidebar/TabSidebarView.swift
macos/Sources/Features/TabSidebar/TabPreviewManager.swift
macos/Sources/Helpers/Extensions/NSView+Extension.swift
```

### Modified Files (MERGE CAREFULLY)

These files exist in upstream but have been modified for the tab sidebar feature. When merging from upstream, preserve our changes:

```
macos/Ghostty.xcodeproj/project.pbxproj    # Added TabSidebar files to project
macos/Sources/App/macOS/AppDelegate.swift   # Tab sidebar initialization
macos/Sources/Features/Terminal/TerminalController.swift  # Preview capture hooks
macos/Sources/Features/Terminal/TerminalView.swift        # Preview capture support
macos/Sources/Ghostty/Ghostty.App.swift     # Tab sidebar state management
macos/Sources/Ghostty/Ghostty.Config.swift  # Tab sidebar config options
macos/Sources/Ghostty/Package.swift         # Package dependencies
macos/Sources/Ghostty/Ghostty.Surface.swift # Added isAtPrompt property
macos/Sources/Ghostty/SurfaceView_AppKit.swift # Added isAtPrompt property
src/config/Config.zig                       # Tab sidebar config option
src/apprt/embedded.zig                      # Added ghostty_surface_is_at_prompt() C API
include/ghostty.h                           # Added ghostty_surface_is_at_prompt() declaration
```

## Merging from Upstream Ghostty

When merging updates from the upstream Ghostty repository:

1. **Never force-overwrite** the files listed above
2. **Review conflicts carefully** in modified files - keep our tab sidebar additions
3. **Test the sidebar** after merging to ensure previews still work
4. The upstream remote should be: `https://github.com/ghostty-org/ghostty.git`

### Safe Merge Process

```bash
# Add upstream if not already added
git remote add upstream https://github.com/ghostty-org/ghostty.git

# Fetch upstream changes
git fetch upstream

# Merge with manual conflict resolution
git merge upstream/main

# If conflicts occur in modified files, keep our tab sidebar code
# Look for code related to: TabSidebar, previewManager, sidebar, deck view
```

## Building

Follow the standard Ghostty build instructions in `HACKING.md`. The tab sidebar is built as part of the macOS app.

## Architecture

- `TabSidebarView.swift` - Main SwiftUI view for the sidebar with grid layout
- `TabPreviewManager.swift` - Manages capturing and caching terminal previews
- Modified `TerminalView` and `TerminalController` to support preview capture
- Config option in `Config.zig` to enable/disable the sidebar

## Custom C API Additions

### `ghostty_surface_is_at_prompt(surface)`

Returns `true` if the terminal is waiting at a shell prompt, `false` if a command is running. This is used to show a "busy" pulse animation on tabs when commands are executing.

**Requirements:** Shell integration must be enabled (OSC 133 escape sequences). Without shell integration, this always returns `false`.

**Usage from Swift:**
```swift
let isWaiting = ghostty_surface_is_at_prompt(surface.unsafeCValue)
// isWaiting == true  → shell is idle, waiting for input
// isWaiting == false → command is running
```
