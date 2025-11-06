extends Node
## ResourceLedger (Singleton)
## Manages global resource economy with Rust-backed storage
## Connects to GameTimer and emits signals for UI updates

# Signals
signal resource_changed(kind: int, current: float, cap: float, rate: float)

# Resource enum - accessible globally as ResourceLedger.R
enum R {
	GOLD = 0,
	FOOD = 1,
	LABOR = 2,
	FAITH = 3,
}

# Rust bridge
var rust_bridge: ResourceLedgerBridge

func _ready() -> void:
	# Create Rust bridge (used as CACHE for synchronous queries only)
	rust_bridge = ResourceLedgerBridge.new()
	add_child(rust_bridge)
	rust_bridge.name = "RustBridge"

	# NOTE: rust_bridge.resource_changed is NOT connected anymore
	# GameActor via UnifiedEventBridge is the ONLY source of truth for resource changes

	# Connect to GameActor's resource signals via UnifiedEventBridge
	# This updates our cached values when GameActor changes resources
	if UnifiedEventBridge:
		UnifiedEventBridge.resource_changed.connect(_on_gameactor_resource_changed)
	else:
		push_error("ResourceLedger: UnifiedEventBridge not found!")

	# Connect to GameTimer
	if GameTimer:
		GameTimer.timer_tick.connect(_on_game_timer_tick)
		GameTimer.consume_food.connect(_on_consume_food)
	else:
		push_error("ResourceLedger: GameTimer not found!")

func _on_game_timer_tick(time_left: int) -> void:
	# Forward timer tick to Rust (which will tick economy and emit signals)
	rust_bridge.on_timer_tick(time_left)

func _on_consume_food() -> void:
	# Consume 1 food per turn (every 60 seconds)
	add(R.FOOD, -1.0)

func _on_gameactor_resource_changed(kind: int, current: float, cap: float, rate: float) -> void:
	# GameActor (via UnifiedEventBridge) has updated resources
	# Update our cached rust_bridge values for synchronous queries
	var resource_name = ["GOLD", "FOOD", "LABOR", "FAITH"][kind] if kind < 4 else "UNKNOWN"
	print("ResourceLedger: Received GameActor resource update - %s: current=%.1f, cap=%.1f, rate=%.1f" % [resource_name, current, cap, rate])

	# Update cached values in rust_bridge
	rust_bridge.set_current(kind, current)
	rust_bridge.set_cap(kind, cap)

# ---- Public API ----

## Get current amount of a resource
func get_current(kind: int) -> float:
	return rust_bridge.get_current(kind)

## Get cap of a resource
func get_cap(kind: int) -> float:
	return rust_bridge.get_cap(kind)

## Get net rate of a resource (per second)
func get_rate(kind: int) -> float:
	return rust_bridge.get_rate(kind)

## Set the cap for a resource
func set_cap(kind: int, value: float) -> void:
	rust_bridge.set_cap(kind, value)

## Set current amount (clamped to [0, cap])
func set_current(kind: int, value: float) -> void:
	rust_bridge.set_current(kind, value)

## Add to current amount (clamped to [0, cap])
func add(kind: int, amount: float) -> void:
	# Delegate to GameActor via UnifiedEventBridge (single source of truth)
	var event_bridge = get_node_or_null("/root/UnifiedEventBridge")
	if event_bridge:
		event_bridge.add_resources(kind, amount)
	else:
		push_error("ResourceLedger: UnifiedEventBridge not available!")

## Check if we can spend resources
## cost: Dictionary of {Resource enum -> amount}
## Example: {R.GOLD: 50, R.FOOD: 10}
## NOTE: This is best-effort based on last known values.
## For authoritative check, use spend() which will fail if insufficient.
func can_spend(cost: Dictionary) -> bool:
	# Best-effort check using rust_bridge's cached values
	# GameActor has the authoritative state, so this may be slightly stale
	for resource_type in cost.keys():
		var required = cost[resource_type]
		var current = rust_bridge.get_current(resource_type)
		if current < required:
			return false
	return true

## Spend resources (GameActor checks and returns true/false)
## cost: Dictionary of {Resource enum -> amount}
## NOTE: This is ASYNCHRONOUS - GameActor will emit resource_changed signals
## when the spend completes. We return true optimistically.
func spend(cost: Dictionary) -> bool:
	# Delegate to GameActor via UnifiedEventBridge (single source of truth)
	var event_bridge = get_node_or_null("/root/UnifiedEventBridge")
	if not event_bridge:
		push_error("ResourceLedger: UnifiedEventBridge not available!")
		return false

	# Serialize cost to PackedByteArray for efficient Rust FFI
	# Format: [resource_type (i64, 8 bytes), amount (f64, 8 bytes)] repeated
	var costs_bytes = PackedByteArray()
	for resource_type in cost.keys():
		var amount = cost[resource_type]

		# Encode resource_type as i64 (8 bytes, little-endian)
		costs_bytes.append((resource_type >> 0) & 0xFF)
		costs_bytes.append((resource_type >> 8) & 0xFF)
		costs_bytes.append((resource_type >> 16) & 0xFF)
		costs_bytes.append((resource_type >> 24) & 0xFF)
		costs_bytes.append((resource_type >> 32) & 0xFF)
		costs_bytes.append((resource_type >> 40) & 0xFF)
		costs_bytes.append((resource_type >> 48) & 0xFF)
		costs_bytes.append((resource_type >> 56) & 0xFF)

		# Encode amount as f64 (8 bytes)
		# Use PackedFloat64Array for proper IEEE 754 f64 encoding
		var temp_array = PackedFloat64Array([amount])
		var float_bytes = temp_array.to_byte_array()
		for i in range(8):
			costs_bytes.append(float_bytes[i])

	event_bridge.spend_resources(costs_bytes)

	# Return true optimistically - GameActor will emit events with actual results
	# TODO: This should be async/await pattern in the future
	return true

## Register a producer
## Returns: the entity's ULID for future reference
func register_producer(entity: Node, resource_type: int, rate_per_sec: float, active := true) -> PackedByteArray:
	# Get or create ULID for entity
	var ulid: PackedByteArray
	if "ulid" in entity and not entity.ulid.is_empty():
		ulid = entity.ulid
	else:
		# Register with UlidManager if not already registered
		ulid = UlidManager.register_entity(entity, UlidManager.TYPE_BUILDING, {
			"producer": true,
			"resource_type": resource_type,
			"rate": rate_per_sec
		})
		if "ulid" in entity:
			entity.ulid = ulid

	# Register with Rust ledger
	rust_bridge.register_producer(ulid, resource_type, rate_per_sec, active)

	return ulid

## Register a consumer
## Returns: the entity's ULID for future reference
func register_consumer(entity: Node, resource_type: int, rate_per_sec: float, active := true) -> PackedByteArray:
	# Get or create ULID for entity
	var ulid: PackedByteArray
	if "ulid" in entity and not entity.ulid.is_empty():
		ulid = entity.ulid
	else:
		# Register with UlidManager if not already registered
		ulid = UlidManager.register_entity(entity, UlidManager.TYPE_BUILDING, {
			"consumer": true,
			"resource_type": resource_type,
			"rate": rate_per_sec
		})
		if "ulid" in entity:
			entity.ulid = ulid

	# Register with Rust ledger
	rust_bridge.register_consumer(ulid, resource_type, rate_per_sec, active)

	return ulid

## Set producer active state
func set_producer_active(ulid: PackedByteArray, active: bool) -> void:
	rust_bridge.set_producer_active(ulid, active)

## Set consumer active state
func set_consumer_active(ulid: PackedByteArray, active: bool) -> void:
	rust_bridge.set_consumer_active(ulid, active)

## Remove a producer (call when entity is destroyed)
func remove_producer(ulid: PackedByteArray) -> void:
	rust_bridge.remove_producer(ulid)

## Remove a consumer (call when entity is destroyed)
func remove_consumer(ulid: PackedByteArray) -> void:
	rust_bridge.remove_consumer(ulid)

## Reset all resources to their initial values (1000 each)
func reset_resources() -> void:
	rust_bridge.reset_resources()

## Print statistics (debugging)
func print_stats() -> void:
	rust_bridge.print_stats()

## Save to dictionary
func to_save_dict() -> Dictionary:
	var save_data = rust_bridge.get_save_data()
	return {"resources": save_data}

## Load from dictionary
func load_from_dict(data: Dictionary) -> void:
	if data.has("resources"):
		rust_bridge.load_save_data(data["resources"])

## Example usage:
## # Spend resources for a building
## var farm_cost = {R.GOLD: 50, R.FOOD: 0}
## if ResourceLedger.spend(farm_cost):
##     var farm = spawn_farm()
##     ResourceLedger.register_producer(farm, R.FOOD, 3.5)
##
## # Add instant resources (from a card effect, quest, etc.)
## ResourceLedger.add(R.GOLD, 100)
