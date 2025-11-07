# macOS Window Management Module

Platform-specific window management features for macOS builds only.

## Overview

This module provides macOS-specific window management capabilities through Objective-C/Cocoa API bindings using `objc2`. These features are conditionally compiled only for macOS targets.

## Features

### 1. Window Transparency
- Set custom alpha values for the window (0.0 = fully transparent, 1.0 = fully opaque)
- Maintains clear background color for proper transparency rendering

### 2. Always-On-Top Mode
- Enable/disable floating window level
- Keeps game window above other applications

### 3. Focus-Based Transparency
- Automatically adjusts window opacity based on focus state
- **Focused**: Fully opaque (1.0) for active gameplay
- **Unfocused**: Very transparent (0.2 default) to see through the window
- Customizable alpha values for both states

### 4. Dynamic Borderless Window Mode
- **Focused**: Shows title bar and window chrome (normal window)
- **Unfocused**: Removes title bar (borderless window)
- Automatically toggles based on window focus state
- Creates a clean overlay effect when not in focus

## Architecture

```
macos/
├── mod.rs                      # Module exports
├── macos_gui_options.rs        # Hybrid window management (Godot API + Objective-C)
├── macos_window_bridge.rs      # Godot-exposed bridge class
├── macos_wry_browser_options.rs # Browser integration (wry)
└── README.md                   # This file
```

### Hybrid Approach

The implementation uses a **hybrid approach** combining Godot's Window API with native macOS calls:

1. **Godot Window API (Primary)**: Uses `Engine::singleton()` → `MainLoop` → `SceneTree` → `Window` to access Godot's window handle
2. **Native macOS API (Secondary)**: Uses Objective-C `NSApplication` and `NSWindow` for platform-specific features

This approach provides:
- **Earlier initialization**: Godot's window exists before `NSApplication.mainWindow`
- **Better reliability**: Uses Godot's window reference as source of truth
- **Platform features**: Leverages macOS-specific capabilities (alpha values, window levels)

## Usage

### From Rust (lib.rs)

The features are automatically initialized on library load:

```rust
#[cfg(target_os = "macos")]
{
    use crate::macos::macos_gui_options;

    // Enable always-on-top mode
    macos_gui_options::set_always_on_top(true);

    // Enable focus-based transparency (focused=1.0, unfocused=0.8)
    macos_gui_options::setup_focus_based_transparency(1.0, 0.8);
}
```

### From GDScript (via MacOSWindowBridge)

The `MacOSWindowBridge` class is exposed to Godot:

```gdscript
# Check if running on macOS
if ClassDB.class_exists("MacOSWindowBridge"):
    var bridge = ClassDB.instantiate("MacOSWindowBridge")

    # Set custom transparency
    bridge.set_transparency(0.9)

    # Enable always-on-top
    bridge.set_always_on_top(true)

    # Remove title bar (borderless window)
    bridge.set_borderless(true)

    # Enable focus-based transparency
    bridge.enable_focus_based_transparency(1.0, 0.5)

    # Check window focus state
    if bridge.is_window_focused():
        print("Window is focused")
```

### Using MacOSWindowManager Autoload

The GDScript autoload `MacOSWindowManager` handles focus tracking automatically:

```gdscript
# Access via autoload
MacOSWindowManager.configure_focus_transparency(1.0, 0.8)

# Or use defaults
MacOSWindowManager.enable_focus_transparency()

# Manual control
MacOSWindowManager.set_transparency(0.5)
MacOSWindowManager.set_always_on_top(false)
```

## API Reference

### macos_gui_options.rs (Low-level)

| Function | Description | Returns |
|----------|-------------|---------|
| `set_window_transparency(alpha: f64)` | Set window transparency | `bool` |
| `set_always_on_top(enabled: bool)` | Enable/disable always-on-top | `bool` |
| `set_borderless(enabled: bool)` | Remove/restore window title bar | `bool` |
| `is_window_focused()` | Check if window is focused | `bool` |
| `setup_focus_based_transparency(focused: f64, unfocused: f64)` | Enable focus-based transparency | `bool` |
| `update_transparency_for_focus(focused: f64, unfocused: f64)` | Update based on current focus | `void` |

### MacOSWindowBridge (Godot Class)

| Method | Description | Returns |
|--------|-------------|---------|
| `initialize()` | Initialize macOS window features (call after window created) | `bool` |
| `set_transparency(alpha: float)` | Set window transparency | `bool` |
| `set_always_on_top(enabled: bool)` | Enable/disable always-on-top | `bool` |
| `set_borderless(enabled: bool)` | Remove/restore window title bar | `bool` |
| `is_window_focused()` | Check if window is focused | `bool` |
| `enable_focus_based_transparency(focused: float, unfocused: float)` | Enable focus-based transparency | `bool` |
| `disable_focus_based_transparency()` | Disable focus-based transparency | `bool` |
| `update_focus_transparency()` | Update transparency for current focus state | `void` |
| `get_platform()` | Get platform name ("macos" or "other") | `String` |
| `is_macos()` | Check if running on macOS | `bool` |

## Dependencies

- **objc2** (0.6.0): Objective-C runtime bindings
- **godot** (0.3.5+): Godot-rust GDExtension framework

## Conditional Compilation

All code in this module is behind `#[cfg(target_os = "macos")]` gates:
- Only compiles for macOS targets
- No-ops or warnings on other platforms
- Zero overhead on Windows/Linux/WASM builds

## Implementation Details

### Hybrid Window Access

Combines Godot's Window API with Objective-C for robust window management:

```rust
use godot::classes::{Engine, Window};
use godot::classes::window::Flags as WindowFlags;

// 1. Access Godot window first
fn get_root_window() -> Option<Gd<Window>> {
    let mut engine = Engine::singleton();
    let main_loop = engine.get_main_loop()?;
    let scene_tree = main_loop.cast::<godot::classes::SceneTree>();
    let root = scene_tree.get_root()?;
    root.try_cast::<Window>().ok()
}

// 2. Set Godot transparency flags
if let Some(mut window) = get_root_window() {
    window.set_transparent_background(true);
    window.set_flag(WindowFlags::TRANSPARENT, true);
}

// 3. Apply native macOS transparency
unsafe {
    let ns_app: *mut Object = msg_send![class!(NSApplication), sharedApplication];
    let ns_window: *mut Object = msg_send![ns_app, mainWindow];
    let _: () = msg_send![ns_window, setAlphaValue: alpha];
}
```

### Window Levels

- **Normal**: Level 0 (default)
- **Floating**: Level 5 (always-on-top)
- **Status**: Level 25 (highest)

### Focus Detection

Checks `NSApplication.isActive` to determine window focus state.

## Future Improvements

- [ ] Window shadow control
- [ ] Title bar customization
- [ ] Full-screen mode detection
- [ ] Multi-window support
- [ ] Window position/size management
- [ ] Notification center integration

## Platform Support

- ✅ macOS (10.13+)
- ❌ Windows (use separate Windows module)
- ❌ Linux (use separate Linux module)
- ❌ WASM (not applicable)
