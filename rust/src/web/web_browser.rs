use godot::prelude::*;
use godot::classes::{
  Control,
  IControl,
  Os,
  ProjectSettings,
};

#[cfg(target_os = "macos")]
use crate::macos::macos_wry_browser_options::MacOSWryBrowserOptions;
#[cfg(target_os = "windows")]
use crate::windows::windows_wry_browser_options::WindowsWryBrowserOptions;


#[cfg(any(target_os = "macos", target_os = "windows"))]
use wry::{
  dpi::{ PhysicalPosition, PhysicalSize },
  http::Request,
  WebViewBuilder,
  Rect,
  WebViewAttributes,
};

#[cfg(any(target_os = "macos", target_os = "windows"))]
use std::{ borrow::Cow, fs, path::PathBuf };

#[cfg(any(target_os = "macos", target_os = "windows"))]
use http::{ header::CONTENT_TYPE, Response };

#[derive(GodotClass)]
#[class(base = Control)]
pub struct GodotBrowser {
  base: Base<Control>,

  #[cfg(any(target_os = "macos", target_os = "windows"))]
  webview: Option<wry::WebView>,

  #[export]
  #[var(get, set = set_url)]
  url: GString,

  #[export]
  #[var(get, set = set_html)]
  html: GString,

  #[export]
  transparent: bool,

  #[export]
  devtools: bool,

  #[export]
  user_agent: GString,

  #[export]
  zoom_hotkeys: bool,

  #[export]
  clipboard: bool,

  #[export]
  incognito: bool,

  focused: bool,

  // Track last size to detect changes
  last_size: Vector2,
  last_position: Vector2,
}

#[godot_api]
impl IControl for GodotBrowser {
  fn init(base: Base<Control>) -> Self {
    Self {
      base,

      #[cfg(any(target_os = "macos", target_os = "windows"))]
      webview: None,

      url: "https://kbve.com/".into(),
      html: "".into(),
      transparent: false,
      devtools: true,
      user_agent: "".into(),
      zoom_hotkeys: false,
      clipboard: true,
      incognito: false,
      focused: true,
      last_size: Vector2::ZERO,
      last_position: Vector2::ZERO,
    }
  }

  fn ready(&mut self) {
    #[cfg(any(target_os = "macos", target_os = "windows"))]
    {
      #[cfg(target_os = "macos")]
      let window = MacOSWryBrowserOptions;

      #[cfg(target_os = "windows")]
      let window = WindowsWryBrowserOptions;

      let base = self.base().clone();
      let webview_builder = WebViewBuilder::new_with_attributes(WebViewAttributes {
        url: if self.html.is_empty() {
          Some(self.url.to_string())
        } else {
          None
        },
        html: if self.url.is_empty() {
          Some(self.html.to_string())
        } else {
          None
        },
        transparent: self.transparent,
        devtools: self.devtools,
        user_agent: Some(self.user_agent.to_string()),
        zoom_hotkeys_enabled: self.zoom_hotkeys,
        clipboard: self.clipboard,
        incognito: self.incognito,
        focused: self.focused,
        ..Default::default()
      }).with_ipc_handler(move |req: Request<String>| {
        let body = req.body().as_str();
        base.clone().emit_signal("ipc_message", &[body.to_variant()]);
      });

      if !self.url.is_empty() && !self.html.is_empty() {
        godot_error!(
          "[GodotBrowser] You have entered both a URL and HTML code. Only one can be used."
        );
        return;
      }

      match webview_builder.build_as_child(&window) {
        Ok(webview) => {
          self.webview.replace(webview);
          godot_print!("[GodotBrowser] WebView created successfully");
        }
        Err(e) => {
          godot_error!("[GodotBrowser] Failed to create WebView: {:?}", e);
        }
      }
    }
  }

  fn process(&mut self, _delta: f64) {
    #[cfg(any(target_os = "macos", target_os = "windows"))]
    {
      // Check if size or position changed and resize if needed
      if self.webview.is_some() && self.base().is_visible_in_tree() {
        let current_size = self.base().get_size();
        let current_pos = self.base().get_global_position();

        // Only resize if size or position actually changed
        if current_size != self.last_size || current_pos != self.last_position {
          self.last_size = current_size;
          self.last_position = current_pos;
          self.resize();
        }
      }
    }
  }

  fn on_notification(&mut self, notification: godot::classes::notify::ControlNotification) {
    use godot::classes::notify::ControlNotification;

    #[cfg(any(target_os = "macos", target_os = "windows"))]
    {
      match notification {
        ControlNotification::RESIZED |
        ControlNotification::TRANSFORM_CHANGED |
        ControlNotification::VISIBILITY_CHANGED => {
          if self.webview.is_some() && self.base().is_visible_in_tree() {
            let current_size = self.base().get_size();
            let current_pos = self.base().get_global_position();
            self.last_size = current_size;
            self.last_position = current_pos;
            self.resize();
          }
        }
        _ => {}
      }
    }
  }
}

#[godot_api]
impl GodotBrowser {
  #[signal]
  fn ipc_message(message: GString);

  #[func]
  pub fn is_initialized(&self) -> bool {
    #[cfg(any(target_os = "macos", target_os = "windows"))]
    {
      self.webview.is_some()
    }
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
      false
    }
  }

  #[func]
  fn set_url(&mut self, url: GString) {
    self.url = url.clone();
    #[cfg(any(target_os = "macos", target_os = "windows"))]
    if let Some(webview) = &self.webview {
      let _ = webview.load_url(&url.to_string());
    }
  }

  #[func]
  fn set_html(&mut self, html: GString) {
    self.html = html.clone();
    #[cfg(any(target_os = "macos", target_os = "windows"))]
    if let Some(webview) = &self.webview {
      let _ = webview.load_html(&html.to_string());
    }
  }

  #[func]
  fn post_message(&self, message: GString) {
    #[cfg(any(target_os = "macos", target_os = "windows"))]
    if let Some(webview) = &self.webview {
      let escaped_message = message.to_string().replace("'", "\\'");
      let script =
        format!("document.dispatchEvent(new CustomEvent('message', {{ detail: '{}' }}))", escaped_message);
      let _ = webview.evaluate_script(&script);
    }
  }

  #[func]
  pub fn resize(&self) {
    #[cfg(target_os = "macos")]
    {
      if let Some(webview) = &self.webview {
        // Get the Control's actual size and global position
        let control_size = self.base().get_size();
        let global_pos = self.base().get_global_position();

        // Get viewport and calculate scale factor (DPI scaling)
        let viewport = self.base().get_viewport();
        if let Some(vp) = viewport {
          let viewport_size = vp.get_visible_rect().size;

          // Get the window to access the screen's scale factor
          let window = vp.get_window();
          let scale_factor = if let Some(win) = window {
            // Get content scale hint which represents DPI scaling (e.g., 2.0 for Retina)
            win.get_content_scale_factor() as f32
          } else {
            1.0
          };

          godot_print!(
            "[GodotBrowser::resize] Scale factor: {}, Godot reports - pos: ({}, {}), size: ({}, {})",
            scale_factor, global_pos.x, global_pos.y, control_size.x, control_size.y
          );

          // Apply scale factor to convert logical pixels to physical pixels
          let physical_x = (global_pos.x * scale_factor) as i32;
          let physical_width = (control_size.x * scale_factor) as u32;
          let physical_height = (control_size.y * scale_factor) as u32;

          // macOS NSView uses bottom-left origin, so flip Y coordinate
          // Formula: flipped_y = viewport_height - (y + height)
          let logical_flipped_y = viewport_size.y - (global_pos.y + control_size.y);
          let physical_flipped_y = (logical_flipped_y * scale_factor) as i32;

          godot_print!(
            "[GodotBrowser::resize] Physical - pos: ({}, {}), size: ({}x{})",
            physical_x, physical_flipped_y, physical_width, physical_height
          );

          let rect = Rect {
            position: PhysicalPosition::new(physical_x, physical_flipped_y).into(),
            size: PhysicalSize::new(physical_width, physical_height).into(),
          };

          if let Err(e) = webview.set_bounds(rect) {
            godot_error!("[GodotBrowser] Failed to resize WebView: {:?}", e);
          } else {
            godot_print!("[GodotBrowser] WebView bounds set successfully");
          }
        }
      }
    }

    #[cfg(target_os = "windows")]
    {
      if let Some(webview) = &self.webview {
        let control_size = self.base().get_size();
        let global_pos = self.base().get_global_position();

        // Get viewport and calculate scale factor (DPI scaling)
        let viewport = self.base().get_viewport();
        if let Some(vp) = viewport {
          // Get the window to access the screen's scale factor
          let window = vp.get_window();
          let scale_factor = if let Some(win) = window {
            win.get_content_scale_factor() as f32
          } else {
            1.0
          };

          // Apply scale factor to convert logical pixels to physical pixels
          let physical_x = (global_pos.x * scale_factor) as i32;
          let physical_y = (global_pos.y * scale_factor) as i32;
          let physical_width = (control_size.x * scale_factor) as u32;
          let physical_height = (control_size.y * scale_factor) as u32;

          let rect = Rect {
            position: PhysicalPosition::new(physical_x, physical_y).into(),
            size: PhysicalSize::new(physical_width, physical_height).into(),
          };

          if let Err(e) = webview.set_bounds(rect) {
            godot_error!("[GodotBrowser] Failed to resize WebView: {:?}", e);
          }
        }
      }
    }
  }

  #[func]
  pub fn set_browser_visible(&self, visible: bool) {
    #[cfg(any(target_os = "macos", target_os = "windows"))]
    if let Some(webview) = &self.webview {
      if visible {
        // Show browser at current position
        self.resize();
      } else {
        // Hide browser by moving it off-screen with 0 size
        let rect = Rect {
          position: PhysicalPosition::new(-10000, -10000).into(),
          size: PhysicalSize::new(0, 0).into(),
        };
        let _ = webview.set_bounds(rect);
      }
    }
  }
}

#[cfg(any(target_os = "macos", target_os = "windows"))]
pub fn get_res_response(request: Request<Vec<u8>>) -> Response<Cow<'static, [u8]>> {
  let os = Os::singleton();
  let root = if os.has_feature("editor") {
    let project_settings = ProjectSettings::singleton();
    PathBuf::from(String::from(project_settings.globalize_path("res://")))
  } else {
    let mut dir = PathBuf::from(String::from(os.get_executable_path()));
    dir.pop();
    dir
  };

  let path = format!("{}{}", request.uri().host().unwrap_or_default(), request.uri().path());
  let full_path = root.join(path);
  if full_path.exists() && full_path.is_file() {
    let content = fs::read(full_path).expect("Failed to read file");
    let mime = infer::get(&content).expect("File type is unknown");
    return http::Response
      ::builder()
      .header(CONTENT_TYPE, mime.to_string())
      .status(200)
      .body(content)
      .unwrap()
      .map(Into::into);
  }

  http::Response
    ::builder()
    .header(CONTENT_TYPE, "text/plain")
    .status(404)
    .body(format!("Could not find file at {:?}", full_path).as_bytes().to_vec())
    .unwrap()
    .map(Into::into)
}