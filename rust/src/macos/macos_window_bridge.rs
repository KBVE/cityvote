// MacOS Window Bridge - Godot-exposed class for macOS window management
// Provides window transparency, always-on-top, and focus-based transparency

use godot::prelude::*;
use godot::classes::INode;

#[cfg(target_os = "macos")]
use super::macos_gui_options;

/// Godot bridge for macOS window management
/// Exposes macOS-specific window features to GDScript
#[derive(GodotClass)]
#[class(base=Node)]
pub struct MacOSWindowBridge {
    base: Base<Node>,
    #[cfg(target_os = "macos")]
    focused_alpha: f64,
    #[cfg(target_os = "macos")]
    unfocused_alpha: f64,
    #[cfg(target_os = "macos")]
    focus_based_enabled: bool,
}

#[godot_api]
impl INode for MacOSWindowBridge {
    fn init(base: Base<Node>) -> Self {
        Self {
            base,
            #[cfg(target_os = "macos")]
            focused_alpha: 1.0,
            #[cfg(target_os = "macos")]
            unfocused_alpha: 0.2,
            #[cfg(target_os = "macos")]
            focus_based_enabled: false,
        }
    }

    // Note: ready() removed - window doesn't exist yet at this point
    // Use manual initialization from GDScript after window is created
}

#[godot_api]
impl MacOSWindowBridge {
    /// Initialize macOS window features (call this after window is created)
    /// Returns true if initialization succeeded
    #[func]
    fn initialize(&mut self) -> bool {
        #[cfg(target_os = "macos")]
        {
            godot_print!("[MacOSWindowBridge] Initializing macOS window features...");

            let mut success = true;

            // Remove title bar for borderless window
            if macos_gui_options::set_borderless(true) {
                godot_print!("[MacOSWindowBridge] Title bar removed");
            } else {
                godot_warn!("[MacOSWindowBridge] Failed to remove title bar");
                success = false;
            }

            // Enable always-on-top mode
            if macos_gui_options::set_always_on_top(true) {
                godot_print!("[MacOSWindowBridge] Always-on-top enabled");
            } else {
                godot_warn!("[MacOSWindowBridge] Failed to enable always-on-top");
                success = false;
            }

            // Enable focus-based transparency (fully opaque when focused, 20% when unfocused)
            if macos_gui_options::setup_focus_based_transparency(1.0, 0.2) {
                self.focused_alpha = 1.0;
                self.unfocused_alpha = 0.2;
                self.focus_based_enabled = true;
                godot_print!("[MacOSWindowBridge] Focus-based transparency enabled");
            } else {
                godot_warn!("[MacOSWindowBridge] Failed to enable focus-based transparency");
                success = false;
            }

            success
        }
        #[cfg(not(target_os = "macos"))]
        {
            false
        }
    }

    /// Set window transparency (0.0 = fully transparent, 1.0 = fully opaque)
    #[func]
    fn set_transparency(&mut self, alpha: f64) -> bool {
        #[cfg(target_os = "macos")]
        {
            macos_gui_options::set_window_transparency(alpha)
        }
        #[cfg(not(target_os = "macos"))]
        {
            godot_warn!("[MacOSWindowBridge] set_transparency called on non-macOS platform");
            false
        }
    }

    /// Enable or disable always-on-top mode
    #[func]
    fn set_always_on_top(&mut self, enabled: bool) -> bool {
        #[cfg(target_os = "macos")]
        {
            macos_gui_options::set_always_on_top(enabled)
        }
        #[cfg(not(target_os = "macos"))]
        {
            godot_warn!("[MacOSWindowBridge] set_always_on_top called on non-macOS platform");
            false
        }
    }

    /// Check if window is currently focused
    #[func]
    fn is_window_focused(&self) -> bool {
        #[cfg(target_os = "macos")]
        {
            macos_gui_options::is_window_focused()
        }
        #[cfg(not(target_os = "macos"))]
        {
            false
        }
    }

    /// Enable focus-based transparency
    /// Window will be fully opaque when focused, semi-transparent when unfocused
    #[func]
    fn enable_focus_based_transparency(&mut self, focused_alpha: f64, unfocused_alpha: f64) -> bool {
        #[cfg(target_os = "macos")]
        {
            self.focused_alpha = focused_alpha;
            self.unfocused_alpha = unfocused_alpha;
            self.focus_based_enabled = true;
            macos_gui_options::setup_focus_based_transparency(focused_alpha, unfocused_alpha)
        }
        #[cfg(not(target_os = "macos"))]
        {
            godot_warn!("[MacOSWindowBridge] enable_focus_based_transparency called on non-macOS platform");
            false
        }
    }

    /// Disable focus-based transparency and restore full opacity
    #[func]
    fn disable_focus_based_transparency(&mut self) -> bool {
        #[cfg(target_os = "macos")]
        {
            self.focus_based_enabled = false;
            macos_gui_options::set_window_transparency(1.0)
        }
        #[cfg(not(target_os = "macos"))]
        {
            false
        }
    }

    /// Update transparency based on current focus state
    /// Should be called from _process() or when window focus changes
    #[func]
    fn update_focus_transparency(&mut self) {
        #[cfg(target_os = "macos")]
        {
            if self.focus_based_enabled {
                macos_gui_options::update_transparency_for_focus(self.focused_alpha, self.unfocused_alpha);
            }
        }
    }

    /// Get the platform name (returns "macos" on macOS, "other" otherwise)
    #[func]
    fn get_platform() -> GString {
        #[cfg(target_os = "macos")]
        {
            "macos".into()
        }
        #[cfg(not(target_os = "macos"))]
        {
            "other".into()
        }
    }

    /// Check if running on macOS
    #[func]
    fn is_macos() -> bool {
        cfg!(target_os = "macos")
    }

    /// Set borderless window mode (removes title bar)
    #[func]
    fn set_borderless(&mut self, enabled: bool) -> bool {
        #[cfg(target_os = "macos")]
        {
            macos_gui_options::set_borderless(enabled)
        }
        #[cfg(not(target_os = "macos"))]
        {
            godot_warn!("[MacOSWindowBridge] set_borderless called on non-macOS platform");
            false
        }
    }
}
