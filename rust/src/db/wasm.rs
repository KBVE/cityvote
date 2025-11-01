/// WASM platform database implementation using Emscripten's IDBFS
///
/// This implementation uses Emscripten's virtual filesystem backed by IndexedDB (IDBFS).
/// Standard Rust file I/O operations (`std::fs`) work transparently, with Emscripten
/// handling the synchronization between memory and IndexedDB.
///
/// ## Setup Requirements (JavaScript side):
///
/// The `/terrain_cache` directory must be mounted as IDBFS from JavaScript at startup:
///
/// ```javascript
/// // Mount IDBFS with auto-persistence
/// FS.mkdir('/terrain_cache');
/// FS.mount(IDBFS, { autoPersist: true }, '/terrain_cache');
///
/// // Load existing data from IndexedDB to memory on startup
/// FS.syncfs(true, function(err) {
///     if (err) console.error('Failed to load from IndexedDB:', err);
///     else console.log('Loaded terrain cache from IndexedDB');
/// });
///
/// // Optionally: Explicitly save to IndexedDB (if autoPersist is false)
/// // FS.syncfs(false, function(err) {
/// //     if (err) console.error('Failed to save to IndexedDB:', err);
/// // });
/// ```
///
/// ## How It Works:
///
/// 1. **Rust code** uses standard `std::fs::File` operations
/// 2. **Emscripten** intercepts file operations and stores in virtual filesystem (MEMFS)
/// 3. **IDBFS mount** synchronizes virtual filesystem with browser's IndexedDB
/// 4. **autoPersist** automatically saves changes to IndexedDB (or use manual `FS.syncfs()`)
///
/// ## Storage Format:
///
/// Chunks are stored as individual binary files:
/// - `/terrain_cache/chunk_X_Y.bin` where X=chunk_x, Y=chunk_y
/// - File contents are bincode-serialized TerrainChunk data
///
/// ## Performance:
///
/// - **Reads**: Fast (from virtual filesystem in WASM memory)
/// - **Writes**: Fast to virtual filesystem, async to IndexedDB
/// - **Persistence**: Automatic with `autoPersist`, or manual with `FS.syncfs()`

use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::Path;
use super::DbError;

/// IDBFS-backed database for WASM
pub struct TerrainDb {
    /// Base directory for chunk storage (mounted as IDBFS)
    base_dir: &'static str,
}

impl TerrainDb {
    /// Open database (verifies IDBFS mount point exists)
    pub fn open() -> Result<Self, DbError> {
        let base_dir = "/terrain_cache";

        // Create base directory if it doesn't exist
        // (Note: This creates it in MEMFS; IDBFS mount should happen from JavaScript)
        if let Err(e) = fs::create_dir_all(base_dir) {
            // Directory might already exist, which is fine
            if e.kind() != std::io::ErrorKind::AlreadyExists {
                return Err(DbError::OpenFailed(format!(
                    "Failed to create terrain cache directory: {}",
                    e
                )));
            }
        }

        godot::prelude::godot_print!(
            "TerrainDb: Using Emscripten IDBFS for persistent storage (WASM) at {}",
            base_dir
        );

        Ok(Self { base_dir })
    }

    /// Get file path for a chunk
    fn chunk_path(&self, chunk_x: i32, chunk_y: i32) -> String {
        format!("{}/chunk_{}_{}.bin", self.base_dir, chunk_x, chunk_y)
    }

    /// Load chunk data from IDBFS
    pub fn load_chunk(&self, chunk_x: i32, chunk_y: i32) -> Result<Option<Vec<u8>>, DbError> {
        let path = self.chunk_path(chunk_x, chunk_y);

        // Check if file exists
        if !Path::new(&path).exists() {
            return Ok(None);
        }

        // Read file contents
        let mut file = File::open(&path).map_err(|e| {
            DbError::QueryFailed(format!("Failed to open chunk file {}: {}", path, e))
        })?;

        let mut data = Vec::new();
        file.read_to_end(&mut data).map_err(|e| {
            DbError::QueryFailed(format!("Failed to read chunk file {}: {}", path, e))
        })?;

        Ok(Some(data))
    }

    /// Save chunk data to IDBFS
    pub fn save_chunk(&self, chunk_x: i32, chunk_y: i32, data: &[u8]) -> Result<(), DbError> {
        let path = self.chunk_path(chunk_x, chunk_y);

        // Write file contents
        let mut file = File::create(&path).map_err(|e| {
            DbError::ExecuteFailed(format!("Failed to create chunk file {}: {}", path, e))
        })?;

        file.write_all(data).map_err(|e| {
            DbError::ExecuteFailed(format!("Failed to write chunk file {}: {}", path, e))
        })?;

        // Flush to ensure data is written to virtual filesystem
        file.sync_all().map_err(|e| {
            DbError::ExecuteFailed(format!("Failed to sync chunk file {}: {}", path, e))
        })?;

        Ok(())
    }

    /// Clear all terrain data
    pub fn clear(&self) -> Result<(), DbError> {
        // Read directory and remove all chunk files
        let entries = fs::read_dir(self.base_dir).map_err(|e| {
            DbError::ExecuteFailed(format!("Failed to read terrain cache directory: {}", e))
        })?;

        let mut removed_count = 0;
        for entry in entries {
            if let Ok(entry) = entry {
                let path = entry.path();
                if let Some(filename) = path.file_name() {
                    if let Some(name) = filename.to_str() {
                        // Only remove chunk files
                        if name.starts_with("chunk_") && name.ends_with(".bin") {
                            if let Err(e) = fs::remove_file(&path) {
                                godot::prelude::godot_warn!(
                                    "TerrainDb: Failed to remove chunk file {:?}: {}",
                                    path,
                                    e
                                );
                            } else {
                                removed_count += 1;
                            }
                        }
                    }
                }
            }
        }

        godot::prelude::godot_print!(
            "TerrainDb: Cleared {} chunk files from IDBFS",
            removed_count
        );

        Ok(())
    }
}
