extends Node
## StatsManager (Singleton)
## Manages entity stats with Rust-backed storage
## Handles combat calculations and stat tracking for ships, NPCs, and structures

# Signals
signal stat_changed(ulid: PackedByteArray, stat_type: int, new_value: float)
signal entity_damaged(ulid: PackedByteArray, damage: float, new_hp: float)
signal entity_healed(ulid: PackedByteArray, heal_amount: float, new_hp: float)
signal entity_died(ulid: PackedByteArray)

# Stat type enum - accessible globally as StatsManager.STAT
enum STAT {
	# Core combat stats
	HP = 0,
	MAX_HP = 1,
	ATTACK = 2,
	DEFENSE = 3,
	SPEED = 4,

	# Resource stats
	ENERGY = 5,
	MAX_ENERGY = 6,

	# Secondary stats
	RANGE = 7,
	MORALE = 8,
	EXPERIENCE = 9,
	LEVEL = 10,

	# Resource production (for structures)
	PRODUCTION_RATE = 11,
	STORAGE_CAPACITY = 12,

	# Special stats
	LUCK = 13,
	EVASION = 14,
}

# Rust bridge
var rust_bridge: StatsManagerBridge

func _ready() -> void:
	# Create Rust bridge
	rust_bridge = StatsManagerBridge.new()
	add_child(rust_bridge)
	rust_bridge.name = "RustBridge"

	# Connect Rust bridge signals to our signals (re-emit for GDScript listeners)
	rust_bridge.stat_changed.connect(_on_rust_stat_changed)
	rust_bridge.entity_damaged.connect(_on_rust_entity_damaged)
	rust_bridge.entity_healed.connect(_on_rust_entity_healed)
	rust_bridge.entity_died.connect(_on_rust_entity_died)

	print("StatsManager: Ready with Rust-backed storage")

func _on_rust_stat_changed(ulid: PackedByteArray, stat_type: int, new_value: float) -> void:
	stat_changed.emit(ulid, stat_type, new_value)

func _on_rust_entity_damaged(ulid: PackedByteArray, damage: float, new_hp: float) -> void:
	entity_damaged.emit(ulid, damage, new_hp)

func _on_rust_entity_healed(ulid: PackedByteArray, heal_amount: float, new_hp: float) -> void:
	entity_healed.emit(ulid, heal_amount, new_hp)

func _on_rust_entity_died(ulid: PackedByteArray) -> void:
	entity_died.emit(ulid)

# ---- Public API ----

## Register entity with default stats based on type
## entity_type: "ship", "npc", or "building"
func register_entity(entity: Node, entity_type: String) -> void:
	# Get or create ULID for entity
	var ulid: PackedByteArray
	if "ulid" in entity and not entity.ulid.is_empty():
		ulid = entity.ulid
	else:
		push_error("StatsManager: Entity must have a ULID before registering stats")
		return

	# Register with Rust
	rust_bridge.register_entity(ulid, entity_type)

## Unregister entity
func unregister_entity(ulid: PackedByteArray) -> bool:
	return rust_bridge.unregister_entity(ulid)

## Get stat value for an entity
func get_stat(ulid: PackedByteArray, stat_type: int) -> float:
	return rust_bridge.get_stat(ulid, stat_type)

## Set stat value for an entity (emits signal)
func set_stat(ulid: PackedByteArray, stat_type: int, value: float) -> bool:
	return rust_bridge.set_stat(ulid, stat_type, value)

## Add to stat value for an entity (emits signal)
func add_stat(ulid: PackedByteArray, stat_type: int, amount: float) -> bool:
	return rust_bridge.add_stat(ulid, stat_type, amount)

## Get all stats for an entity as Dictionary
func get_all_stats(ulid: PackedByteArray) -> Dictionary:
	return rust_bridge.get_all_stats(ulid)

## Entity takes damage (returns actual damage dealt)
func take_damage(ulid: PackedByteArray, damage: float) -> float:
	return rust_bridge.take_damage(ulid, damage)

## Heal entity (returns actual amount healed)
func heal(ulid: PackedByteArray, amount: float) -> float:
	return rust_bridge.heal(ulid, amount)

## Check if entity is alive
func is_alive(ulid: PackedByteArray) -> bool:
	return rust_bridge.is_alive(ulid)

## Get count of registered entities
func count() -> int:
	return rust_bridge.count()

## Print statistics (debugging)
func print_stats() -> void:
	rust_bridge.print_stats()

## Example usage:
## # Register a ship with stats
## var ship = spawn_ship()
## StatsManager.register_entity(ship, "ship")
##
## # Get HP
## var hp = StatsManager.get_stat(ship.ulid, StatsManager.STAT.HP)
##
## # Take damage
## var damage_dealt = StatsManager.take_damage(ship.ulid, 25.0)
##
## # Heal
## var amount_healed = StatsManager.heal(ship.ulid, 10.0)
##
## # Listen for death
## StatsManager.entity_died.connect(func(ulid):
##     if ulid == ship.ulid:
##         ship.queue_free()
## )
