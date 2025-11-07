#[cfg(target_os = "windows")]
use std::ptr::NonNull;
#[cfg(target_os = "windows")]
use std::ffi::c_void;
#[cfg(target_os = "windows")]
use std::mem::transmute;
#[cfg(target_os = "windows")]
use godot::prelude::*;
#[cfg(target_os = "windows")]
use godot::classes::DisplayServer;
#[cfg(target_os = "windows")]
use godot::classes::display_server::HandleType;
#[cfg(target_os = "windows")]
use raw_window_handle::{
  Win32WindowHandle,
  WindowHandle,
  RawWindowHandle,
  HasWindowHandle,
  HandleError,
};

#[cfg(target_os = "windows")]
pub struct WindowsWryBrowserOptions;

#[cfg(target_os = "windows")]
impl WindowsWryBrowserOptions {
  pub fn get_window_handle(&self) -> Result<WindowHandle<'_>, HandleError> {
    let display_server = DisplayServer::singleton();
    let window_handle = display_server.window_get_native_handle(HandleType::WINDOW_HANDLE);
    unsafe {
      Ok(
        WindowHandle::borrow_raw(
          RawWindowHandle::Win32(
            Win32WindowHandle::new({
              let ptr: *mut c_void = transmute(window_handle);
              NonNull::new(ptr).expect("HWND should never be null")
            })
          )
        )
      )
    }
  }

  pub fn resize_window(&self, width: i32, height: i32) {
    let mut display_server = DisplayServer::singleton();
    display_server.window_set_size(Vector2i::new(width, height));
    godot_print!("[WindowsWryBrowserOptions] Window resized to {}x{}", width, height);
  }
}

#[cfg(target_os = "windows")]
impl HasWindowHandle for WindowsWryBrowserOptions {
  fn window_handle(&self) -> Result<WindowHandle<'_>, HandleError> {
    godot_print!("[BrowserManager] -> [WindowsWryBrowserOptions] Window Handle");
    self.get_window_handle()
  }
}
