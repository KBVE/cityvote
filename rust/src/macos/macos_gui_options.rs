#[cfg(target_os = "macos")]
use objc2::rc::Retained;
#[cfg(target_os = "macos")]
use objc2::MainThreadMarker;
#[cfg(target_os = "macos")]
use objc2_app_kit::{NSApplication, NSWindow, NSColor, NSWindowStyleMask};
#[cfg(target_os = "macos")]
use godot::prelude::*;
#[cfg(target_os = "macos")]
use godot::classes::{Engine, Window, DisplayServer};
#[cfg(target_os = "macos")]
use godot::classes::window::Flags as WindowFlags;

/// Get the root Godot window
#[cfg(target_os = "macos")]
fn get_root_window() -> Option<Gd<Window>> {
    let engine = Engine::singleton();
    let main_loop = engine.get_main_loop()?;
    let scene_tree = main_loop.cast::<godot::classes::SceneTree>();
    let root = scene_tree.get_root()?;
    root.try_cast::<Window>().ok()
}

/// Get NSWindow using Godot's native window handle
/// This is more reliable than NSApplication.mainWindow()
#[cfg(target_os = "macos")]
fn get_ns_window_from_godot() -> Option<Retained<NSWindow>> {
    // Get Godot's window
    let _godot_window = get_root_window()?;

    // Get the native window handle from DisplayServer
    let display_server = DisplayServer::singleton();
    let window_handle = display_server.window_get_native_handle(
        godot::classes::display_server::HandleType::WINDOW_HANDLE
    );

    if window_handle == 0 {
        godot_warn!("[MacOS] Failed to get native window handle from Godot");
        return None;
    }

    // SAFETY: Godot gives us a valid NSWindow pointer
    // We need to retain it since Godot is giving us a borrowed reference
    unsafe {
        let ns_window_ptr = window_handle as *mut NSWindow;
        if ns_window_ptr.is_null() {
            godot_warn!("[MacOS] NSWindow pointer is null");
            return None;
        }

        // Create a Retained instance from the raw pointer
        // This will properly manage the reference count
        Some(Retained::retain(ns_window_ptr)?)
    }
}

/// Get NSWindow with retry logic - tries Godot's handle first, then fallbacks
#[cfg(target_os = "macos")]
fn get_ns_window_with_retry(max_attempts: u32) -> Option<Retained<NSWindow>> {
    use std::thread;
    use std::time::Duration;

    for attempt in 0..max_attempts {
        // Try 1: Get from Godot's native handle (most reliable)
        if let Some(window) = get_ns_window_from_godot() {
            if attempt > 0 {
                godot_print!("[MacOS] NSWindow found via Godot handle after {} attempts", attempt + 1);
            }
            return Some(window);
        }

        // SAFETY: We're being called from Godot's main thread
        let mtm = unsafe { MainThreadMarker::new_unchecked() };
        let ns_app = NSApplication::sharedApplication(mtm);

        // Try 2: mainWindow
        if let Some(window) = ns_app.mainWindow() {
            godot_print!("[MacOS] NSWindow found via mainWindow (attempt {})", attempt + 1);
            return Some(window);
        }

        // Try 3: keyWindow
        if let Some(window) = ns_app.keyWindow() {
            godot_print!("[MacOS] NSWindow found via keyWindow (attempt {})", attempt + 1);
            return Some(window);
        }

        // Wait a bit before retrying (50ms for better sync with macOS)
        if attempt < max_attempts - 1 {
            thread::sleep(Duration::from_millis(50));
        }
    }

    godot_warn!("[MacOS] NSWindow still null after {} attempts", max_attempts);
    None
}

/// Set window transparency level using Godot Window API + macOS native calls
/// # Arguments
/// * `transparency_value` - Alpha value from 0.0 (fully transparent) to 1.0 (fully opaque)
#[cfg(target_os = "macos")]
pub fn set_window_transparency(transparency_value: f64) -> bool {
    // First, enable transparency in Godot
    if let Some(mut window) = get_root_window() {
        window.set_transparent_background(true);
        window.set_flag(WindowFlags::TRANSPARENT, true);
        godot_print!("[MacOS] Godot window transparency flags set");
    } else {
        godot_error!("[MacOS] Failed to get root window");
        return false;
    }

    // Then apply native macOS transparency
    let Some(window) = get_ns_window_with_retry(5) else {
        godot_error!("[MacOS] No main window found after retries");
        return false;
    };

    // Enable transparency
    unsafe {
        window.setOpaque(false);
    }
    window.setAlphaValue(transparency_value.clamp(0.0, 1.0));

    // Set clear background color
    let clear_color = NSColor::clearColor();
    window.setBackgroundColor(Some(&clear_color));

    godot_print!("[MacOS] Window transparency set to {}", transparency_value);
    true
}

/// Enable or disable always-on-top mode
#[cfg(target_os = "macos")]
pub fn set_always_on_top(enabled: bool) -> bool {
    // First verify Godot window exists
    if get_root_window().is_none() {
        godot_error!("[MacOS] Failed to get root window for always-on-top");
        return false;
    }

    let Some(window) = get_ns_window_with_retry(5) else {
        godot_error!("[MacOS] No main window found after retries");
        return false;
    };

    // NSWindowLevel values:
    // NSNormalWindowLevel = 0
    // NSFloatingWindowLevel = 5
    // NSStatusWindowLevel = 25
    let level: isize = if enabled { 5 } else { 0 };
    unsafe {
        window.setLevel(level);
    }

    godot_print!("[MacOS] Window always-on-top: {}", enabled);
    true
}

/// Check if window is currently focused/active
#[cfg(target_os = "macos")]
pub fn is_window_focused() -> bool {
    // SAFETY: We're being called from Godot's main thread
    let mtm = unsafe { MainThreadMarker::new_unchecked() };
    let ns_app = NSApplication::sharedApplication(mtm);
    ns_app.isActive()
}

/// Configure window with focus-based transparency
/// When focused: full opacity, when unfocused: semi-transparent
#[cfg(target_os = "macos")]
pub fn setup_focus_based_transparency(focused_alpha: f64, unfocused_alpha: f64) -> bool {
    // First, enable transparency in Godot
    if let Some(mut window) = get_root_window() {
        window.set_transparent_background(true);
        window.set_flag(WindowFlags::TRANSPARENT, true);
        godot_print!("[MacOS] Godot window transparency flags set for focus-based transparency");
    } else {
        godot_error!("[MacOS] Failed to get root window for focus-based transparency");
        return false;
    }

    let Some(window) = get_ns_window_with_retry(5) else {
        godot_error!("[MacOS] No main window found after retries");
        return false;
    };

    unsafe {
        // SAFETY: We're being called from Godot's main thread
        let mtm = MainThreadMarker::new_unchecked();
        let ns_app = NSApplication::sharedApplication(mtm);

        // Enable transparency first
        window.setOpaque(false);

        let clear_color = NSColor::clearColor();
        window.setBackgroundColor(Some(&clear_color));

        // Set initial alpha based on current focus state
        let is_active = ns_app.isActive();
        let initial_alpha = if is_active { focused_alpha } else { unfocused_alpha };
        window.setAlphaValue(initial_alpha.clamp(0.0, 1.0));

        godot_print!("[MacOS] Focus-based transparency enabled (focused: {}, unfocused: {})", focused_alpha, unfocused_alpha);
        true
    }
}

/// Update transparency based on current focus state
/// Should be called when window focus changes
#[cfg(target_os = "macos")]
pub fn update_transparency_for_focus(focused_alpha: f64, unfocused_alpha: f64) {
    let Some(window) = get_ns_window_with_retry(2) else {
        return;
    };

    unsafe {
        // SAFETY: We're being called from Godot's main thread
        let mtm = MainThreadMarker::new_unchecked();
        let ns_app = NSApplication::sharedApplication(mtm);
        let is_active = ns_app.isActive();
        let alpha = if is_active { focused_alpha } else { unfocused_alpha };
        window.setAlphaValue(alpha.clamp(0.0, 1.0));
    }
}

/// Remove the window title bar and make it borderless
/// This creates a cleaner, frameless window appearance
#[cfg(target_os = "macos")]
pub fn set_borderless(enabled: bool) -> bool {
    let Some(window) = get_ns_window_with_retry(5) else {
        godot_error!("[MacOS] No main window found after retries");
        return false;
    };

    if enabled {
        // Set to borderless (empty mask)
        window.setStyleMask(NSWindowStyleMask::empty());
        godot_print!("[MacOS] Window title bar removed (borderless)");
    } else {
        // Restore default style: titled + closable + miniaturizable + resizable
        let default_mask = NSWindowStyleMask::Titled
            | NSWindowStyleMask::Closable
            | NSWindowStyleMask::Miniaturizable
            | NSWindowStyleMask::Resizable;
        window.setStyleMask(default_mask);
        godot_print!("[MacOS] Window title bar restored");
    }

    true
}