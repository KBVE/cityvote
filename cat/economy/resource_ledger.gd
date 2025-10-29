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
	# Create Rust bridge
	rust_bridge = ResourceLedgerBridge.new()
	add_child(rust_bridge)
	rust_bridge.name = "RustBridge"

	# Connect Rust bridge signal to our signal (re-emit for GDScript listeners)
	rust_bridge.resource_changed.connect(_on_rust_resource_changed)

	# Connect to GameTimer
	if GameTimer:
		GameTimer.timer_tick.connect(_on_game_timer_tick)
		print("ResourceLedger: Connected to GameTimer")
	else:
		push_error("ResourceLedger: GameTimer not found!")

	print("ResourceLedger: Ready with Rust-backed storage")

func _on_game_timer_tick(time_left: int) -> void:
	# Forward timer tick to Rust (which will tick economy and emit signals)
	rust_bridge.on_timer_tick(time_left)

func _on_rust_resource_changed(kind: int, current: float, cap: float, rate: float) -> void:
	# Re-emit signal for GDScript listeners
	resource_changed.emit(kind, current, cap, rate)

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
	rust_bridge.add(kind, amount)

## Check if we can spend resources
## cost: Dictionary of {Resource enum -> amount}
## Example: {R.GOLD: 50, R.FOOD: 10}
func can_spend(cost: Dictionary) -> bool:
	return rust_bridge.can_spend(cost)

## Spend resources (returns false if not enough)
## cost: Dictionary of {Resource enum -> amount}
func spend(cost: Dictionary) -> bool:
	return rust_bridge.spend(cost)

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
