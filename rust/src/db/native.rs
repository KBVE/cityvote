/// Native platform SQLite implementation using rusqlite

use rusqlite::{Connection, params};
use super::DbError;

pub struct TerrainDb {
    conn: Connection,
}

impl TerrainDb {
    /// Open or create a new database
    pub fn open() -> Result<Self, DbError> {
        // Use in-memory database for now (can switch to file later)
        let conn = Connection::open_in_memory()
            .map_err(|e| DbError::OpenFailed(e.to_string()))?;

        // Create terrain_chunks table
        conn.execute(
            "CREATE TABLE IF NOT EXISTS terrain_chunks (
                chunk_x INTEGER NOT NULL,
                chunk_y INTEGER NOT NULL,
                data BLOB NOT NULL,
                PRIMARY KEY (chunk_x, chunk_y)
            )",
            [],
        ).map_err(|e| DbError::ExecuteFailed(e.to_string()))?;

        godot::prelude::godot_print!("TerrainDb: SQLite initialized (in-memory, native)");
        Ok(Self { conn })
    }

    /// Load chunk data from database
    pub fn load_chunk(&self, chunk_x: i32, chunk_y: i32) -> Result<Option<Vec<u8>>, DbError> {
        let result = self.conn.query_row(
            "SELECT data FROM terrain_chunks WHERE chunk_x = ?1 AND chunk_y = ?2",
            params![chunk_x, chunk_y],
            |row| row.get::<_, Vec<u8>>(0),
        );

        match result {
            Ok(blob) => Ok(Some(blob)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(DbError::QueryFailed(e.to_string())),
        }
    }

    /// Save chunk data to database
    pub fn save_chunk(&self, chunk_x: i32, chunk_y: i32, data: &[u8]) -> Result<(), DbError> {
        self.conn.execute(
            "INSERT OR REPLACE INTO terrain_chunks (chunk_x, chunk_y, data) VALUES (?1, ?2, ?3)",
            params![chunk_x, chunk_y, data],
        ).map_err(|e| DbError::ExecuteFailed(e.to_string()))?;

        Ok(())
    }

    /// Clear all terrain data
    pub fn clear(&self) -> Result<(), DbError> {
        self.conn.execute("DELETE FROM terrain_chunks", [])
            .map_err(|e| DbError::ExecuteFailed(e.to_string()))?;
        Ok(())
    }
}
