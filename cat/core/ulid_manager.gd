extends Node

## ULID Manager (Singleton)
## Manages entity ULIDs using Rust's optimized generator and storage
## ULIDs are 128-bit (16 bytes) identifiers: 48-bit timestamp + 80-bit random

# Global storage instance (Rust DashMap for thread-safe access)
var storage: UlidStorage

# Entity type constants (must match Rust EntityType enum)
const TYPE_CARD = 0
const TYPE_SHIP = 1
const TYPE_NPC = 2
const TYPE_BUILDING = 3
const TYPE_RESOURCE = 4

func _ready() -> void:
	# Initialize Rust storage
	storage = UlidStorage.new()
	if not storage:
		push_error("UlidManager: Failed to initialize Rust-backed storage")

## Generate a new ULID
func generate() -> PackedByteArray:
	return UlidGenerator.generate()

## Generate a new ULID and register an entity
## Returns: ULID as PackedByteArray
func register_entity(entity: Node, entity_type: int, metadata: Dictionary = {}) -> PackedByteArray:
	# Ensure storage is initialized
	if not storage:
		storage = UlidStorage.new()
		if not storage:
			push_error("UlidManager: Failed to lazy-initialize storage during register_entity()")

	var ulid = UlidGenerator.generate()
	var instance_id = entity.get_instance_id()

	storage.store(ulid, entity_type, instance_id, metadata)

	return ulid

## Unregister an entity by ULID
func unregister_entity(ulid: PackedByteArray) -> bool:
	return storage.remove(ulid)

## Get entity data by ULID
func get_entity(ulid: PackedByteArray) -> Variant:
	return storage.get(ulid)

## Get instance from ULID
func get_instance(ulid: PackedByteArray) -> Node:
	var instance_id = storage.get_instance_id(ulid)
	if instance_id == -1:
		return null

	var instance = instance_from_id(instance_id)
	return instance as Node

## Check if ULID exists
func has(ulid: PackedByteArray) -> bool:
	return storage.has(ulid)

## Get all ULIDs of a type
## Returns Array of PackedByteArray (each 16 bytes)
func get_by_type(entity_type: int) -> Array:
	var concatenated = storage.get_by_type(entity_type)
	var ulids: Array = []

	# Split concatenated bytes into individual 16-byte ULIDs
	var byte_count = concatenated.size()
	for i in range(0, byte_count, 16):
		if i + 16 <= byte_count:
			var ulid = concatenated.slice(i, i + 16)
			ulids.append(ulid)

	return ulids

## Get all entities of a type as Node instances
func get_entities_by_type(entity_type: int) -> Array[Node]:
	var ulids = get_by_type(entity_type)
	var entities: Array[Node] = []

	for ulid in ulids:
		var instance = get_instance(ulid)
		if instance:
			entities.append(instance)

	return entities

## Update metadata for an entity
func update_metadata(ulid: PackedByteArray, metadata: Dictionary) -> bool:
	return storage.update_metadata(ulid, metadata)

## Get count of entities
func count() -> int:
	return storage.count()

## Get count of entities by type
func count_by_type(entity_type: int) -> int:
	return storage.count_by_type(entity_type)

## Clear all entities
func clear() -> void:
	storage.clear()

## Clear entities of a specific type
func clear_type(entity_type: int) -> void:
	storage.clear_type(entity_type)

## Convert ULID to hex string (for debugging)
func to_hex(ulid: PackedByteArray) -> String:
	return UlidGenerator.to_hex(ulid)

## Get timestamp from ULID
func get_timestamp(ulid: PackedByteArray) -> int:
	return UlidGenerator.get_timestamp(ulid)

## Compare two ULIDs (-1 if a < b, 0 if equal, 1 if a > b)
func compare(a: PackedByteArray, b: PackedByteArray) -> int:
	return UlidGenerator.compare(a, b)

## Check if two ULIDs are equal
func equals(a: PackedByteArray, b: PackedByteArray) -> bool:
	return UlidGenerator.equals(a, b)

## Create a null ULID (all zeros)
func null_ulid() -> PackedByteArray:
	return UlidGenerator.null_ulid()

## Check if ULID is null
func is_null(ulid: PackedByteArray) -> bool:
	return UlidGenerator.is_null(ulid)

## Print storage statistics
func print_stats() -> void:
	storage.print_stats()

## Example usage:
## var ulid = UlidManager.register_entity(card_node, UlidManager.TYPE_CARD, {"suit": 2, "value": 8})
## var card_node = UlidManager.get_instance(ulid)
## var all_cards = UlidManager.get_entities_by_type(UlidManager.TYPE_CARD)
