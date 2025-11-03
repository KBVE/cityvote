extends Node

## Chunk Pool - Manages chunk data and MultiMeshInstance2D reuse
## Implements LRU (Least Recently Used) cache for chunk data

class_name ChunkPool

## Chunk data structure
class ChunkData:
	var chunk_coords: Vector2i
	var terrain_data: Array  # Array of tile dictionaries from Rust
	var multimesh_instances: Array[MultiMeshInstance2D] = []  # One per row
	var last_used_time: int = 0  # For LRU eviction

	func _init(coords: Vector2i):
		chunk_coords = coords
		last_used_time = Time.get_ticks_msec()

	func touch():
		last_used_time = Time.get_ticks_msec()

## Loaded chunks (chunk_coords -> ChunkData)
var loaded_chunks: Dictionary = {}

## Pool of reusable MultiMeshInstance2D nodes
var multimesh_pool: Array[MultiMeshInstance2D] = []

## Maximum number of chunks to keep in memory
var max_cached_chunks: int = MapConfig.CHUNK_CACHE_SIZE

## Statistics
var chunks_loaded_count: int = 0
var chunks_evicted_count: int = 0
var cache_hits: int = 0
var cache_misses: int = 0

## Check if a chunk is loaded
func is_chunk_loaded(chunk_coords: Vector2i) -> bool:
	return chunk_coords in loaded_chunks

## Get chunk data (returns null if not loaded)
func get_chunk(chunk_coords: Vector2i) -> ChunkData:
	if chunk_coords in loaded_chunks:
		var chunk = loaded_chunks[chunk_coords]
		chunk.touch()  # Update LRU timestamp
		cache_hits += 1
		return chunk
	cache_misses += 1
	return null

## Load chunk data into the pool
func load_chunk(chunk_coords: Vector2i, terrain_data: Array) -> ChunkData:
	# Check if already loaded
	if chunk_coords in loaded_chunks:
		return loaded_chunks[chunk_coords]

	# Create new chunk data
	var chunk = ChunkData.new(chunk_coords)
	chunk.terrain_data = terrain_data
	loaded_chunks[chunk_coords] = chunk
	chunks_loaded_count += 1

	# Evict oldest chunks if we exceed cache size
	_evict_old_chunks()

	return chunk

## Unload a chunk and release its resources
func unload_chunk(chunk_coords: Vector2i) -> bool:
	if chunk_coords not in loaded_chunks:
		return false

	var chunk = loaded_chunks[chunk_coords]

	# Return multimesh instances to pool
	for multimesh in chunk.multimesh_instances:
		if multimesh:
			multimesh.queue_free()

	chunk.multimesh_instances.clear()
	chunk.terrain_data.clear()

	loaded_chunks.erase(chunk_coords)
	chunks_evicted_count += 1

	return true

## Acquire a MultiMeshInstance2D from the pool (or create new one)
func acquire_multimesh() -> MultiMeshInstance2D:
	if multimesh_pool.size() > 0:
		return multimesh_pool.pop_back()
	else:
		# Create new instance
		return MultiMeshInstance2D.new()

## Release a MultiMeshInstance2D back to the pool
func release_multimesh(multimesh: MultiMeshInstance2D):
	if multimesh:
		# Clear the multimesh data
		multimesh.multimesh = null
		multimesh.visible = false
		multimesh_pool.append(multimesh)

## Evict old chunks to stay under cache limit (LRU eviction)
func _evict_old_chunks():
	if loaded_chunks.size() <= max_cached_chunks:
		return

	# Sort chunks by last used time (oldest first)
	var chunks_by_age: Array = []
	for coords in loaded_chunks.keys():
		var chunk = loaded_chunks[coords]
		chunks_by_age.append({"coords": coords, "time": chunk.last_used_time})

	chunks_by_age.sort_custom(func(a, b): return a.time < b.time)

	# Evict oldest chunks until we're under the limit
	var chunks_to_evict = loaded_chunks.size() - max_cached_chunks
	for i in range(chunks_to_evict):
		var chunk_info = chunks_by_age[i]
		unload_chunk(chunk_info.coords)

## Get chunks that should be unloaded (outside of render distance)
func get_chunks_to_unload(center_chunk: Vector2i, render_distance: int) -> Array[Vector2i]:
	var chunks_to_unload: Array[Vector2i] = []

	for coords in loaded_chunks.keys():
		var dist_x = abs(coords.x - center_chunk.x)
		var dist_y = abs(coords.y - center_chunk.y)

		# Unload chunks outside render distance (with +1 buffer)
		if dist_x > render_distance + 1 or dist_y > render_distance + 1:
			chunks_to_unload.append(coords)

	return chunks_to_unload

## Get all loaded chunk coordinates
func get_loaded_chunks() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coords in loaded_chunks.keys():
		result.append(coords)
	return result

## Clear all chunks
func clear_all():
	for coords in loaded_chunks.keys():
		unload_chunk(coords)
	loaded_chunks.clear()

	# Clear multimesh pool
	for multimesh in multimesh_pool:
		multimesh.queue_free()
	multimesh_pool.clear()

## Get statistics
func get_stats() -> Dictionary:
	return {
		"loaded_chunks": loaded_chunks.size(),
		"multimesh_pool_size": multimesh_pool.size(),
		"chunks_loaded_total": chunks_loaded_count,
		"chunks_evicted_total": chunks_evicted_count,
		"cache_hits": cache_hits,
		"cache_misses": cache_misses,
		"cache_hit_rate": float(cache_hits) / float(cache_hits + cache_misses) if (cache_hits + cache_misses) > 0 else 0.0
	}

## Print statistics
func print_stats():
	var stats = get_stats()
	print("=== ChunkPool Statistics ===")
	print("Loaded chunks: %d / %d" % [stats.loaded_chunks, max_cached_chunks])
	print("MultiMesh pool size: %d" % stats.multimesh_pool_size)
	print("Total loaded: %d, Total evicted: %d" % [stats.chunks_loaded_total, stats.chunks_evicted_total])
	print("Cache hits: %d, Cache misses: %d (%.1f%% hit rate)" % [stats.cache_hits, stats.cache_misses, stats.cache_hit_rate * 100.0])
