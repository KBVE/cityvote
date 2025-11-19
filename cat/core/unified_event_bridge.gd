extends Node

###
## UnifiedEventBridge - Single Godot autoload for all game events
## Wraps the Rust UnifiedEventBridge class for convenient access

# Reference to Rust UnifiedEventBridge
var event_bridge: Node = null

# Signals matching Rust bridge signals
signal entity_spawned(ulid: PackedByteArray, position_q: int, position_r: int, terrain_type: int, entity_type: String)
signal spawn_failed(entity_type: String, error: String)
signal path_found(ulid: PackedByteArray, path: Array, cost: float)
signal path_failed(ulid: PackedByteArray)
signal random_dest_found(ulid: PackedByteArray, destination_q: int, destination_r: int, found: bool)
signal combat_started(attacker: PackedByteArray, defender: PackedByteArray)
signal damage_dealt(attacker: PackedByteArray, defender: PackedByteArray, damage: int)
signal entity_died(ulid: PackedByteArray)
signal combat_ended(attacker: PackedByteArray, defender: PackedByteArray)
signal spawn_projectile(attacker_ulid: PackedByteArray, attacker_pos_q: int, attacker_pos_r: int, target_ulid: PackedByteArray, target_pos_q: int, target_pos_r: int, projectile_type: int, damage: int)
signal resource_changed(resource_type: int, current: float, cap: float, rate: float)
signal stat_changed(ulid: PackedByteArray, stat_type: int, new_value: float)
signal entity_damaged(ulid: PackedByteArray, damage: float, new_hp: float)
signal entity_healed(ulid: PackedByteArray, heal_amount: float, new_hp: float)
signal combo_detected(hand_rank: int, hand_name: String, positions: Array, bonuses: Array)

# DEPRECATED: IRC Chat Signals removed - now handled by IrcWebSocketClient autoload
# See irc_websocket_client.gd for IRC functionality

func _ready() -> void:
	# Instantiate Rust bridge
	event_bridge = ClassDB.instantiate("UnifiedEventBridge")
	if event_bridge:
		add_child(event_bridge)

		# Connect all Rust signals to GDScript signals (for compatibility)
		event_bridge.entity_spawned.connect(_on_entity_spawned)
		event_bridge.spawn_failed.connect(_on_spawn_failed)
		event_bridge.path_found.connect(_on_path_found)
		event_bridge.path_failed.connect(_on_path_failed)
		event_bridge.random_dest_found.connect(_on_random_dest_found)
		event_bridge.combat_started.connect(_on_combat_started)
		event_bridge.damage_dealt.connect(_on_damage_dealt)
		event_bridge.entity_died.connect(_on_entity_died)
		event_bridge.combat_ended.connect(_on_combat_ended)
		event_bridge.spawn_projectile.connect(_on_spawn_projectile)
		event_bridge.resource_changed.connect(_on_resource_changed)
		event_bridge.stat_changed.connect(_on_stat_changed)
		event_bridge.entity_damaged.connect(_on_entity_damaged)
		event_bridge.entity_healed.connect(_on_entity_healed)
		event_bridge.combo_detected.connect(_on_combo_detected)

		# DEPRECATED: IRC signals removed - now handled by IrcWebSocketClient autoload
	else:
		push_error("UnifiedEventBridge: Failed to instantiate Rust bridge!")

# Note: The Rust UnifiedEventBridge node has its own process() method
# that is called automatically by Godot every frame (set_process(true) in ready())
# No need to manually call it from GDScript

# ============================================================================
# SIGNAL FORWARDERS (Forward Rust signals to GDScript signals)
# ============================================================================

func _on_entity_spawned(ulid: PackedByteArray, position_q: int, position_r: int, terrain_type: int, entity_type: String) -> void:
	entity_spawned.emit(ulid, position_q, position_r, terrain_type, entity_type)

func _on_spawn_failed(entity_type: String, error: String) -> void:
	spawn_failed.emit(entity_type, error)

func _on_path_found(ulid: PackedByteArray, path: Array, cost: float) -> void:
	path_found.emit(ulid, path, cost)

func _on_path_failed(ulid: PackedByteArray) -> void:
	path_failed.emit(ulid)

func _on_random_dest_found(ulid: PackedByteArray, destination_q: int, destination_r: int, found: bool) -> void:
	random_dest_found.emit(ulid, destination_q, destination_r, found)

func _on_combat_started(attacker: PackedByteArray, defender: PackedByteArray) -> void:
	combat_started.emit(attacker, defender)

func _on_damage_dealt(attacker: PackedByteArray, defender: PackedByteArray, damage: int) -> void:
	damage_dealt.emit(attacker, defender, damage)

func _on_entity_died(ulid: PackedByteArray) -> void:
	entity_died.emit(ulid)

func _on_combat_ended(attacker: PackedByteArray, defender: PackedByteArray) -> void:
	combat_ended.emit(attacker, defender)

func _on_spawn_projectile(attacker_ulid: PackedByteArray, attacker_pos_q: int, attacker_pos_r: int, target_ulid: PackedByteArray, target_pos_q: int, target_pos_r: int, projectile_type: int, damage: int) -> void:
	spawn_projectile.emit(attacker_ulid, attacker_pos_q, attacker_pos_r, target_ulid, target_pos_q, target_pos_r, projectile_type, damage)

func _on_resource_changed(resource_type: int, current: float, cap: float, rate: float) -> void:
	resource_changed.emit(resource_type, current, cap, rate)

func _on_stat_changed(ulid: PackedByteArray, stat_type: int, new_value: float) -> void:
	stat_changed.emit(ulid, stat_type, new_value)

func _on_entity_damaged(ulid: PackedByteArray, damage: float, new_hp: float) -> void:
	entity_damaged.emit(ulid, damage, new_hp)

func _on_entity_healed(ulid: PackedByteArray, heal_amount: float, new_hp: float) -> void:
	entity_healed.emit(ulid, heal_amount, new_hp)

func _on_combo_detected(hand_rank: int, hand_name: String, positions: Array, bonuses: Array) -> void:
	combo_detected.emit(hand_rank, hand_name, positions, bonuses)

# ============================================================================
# SPAWN API (Compatible with EntitySpawnBridge)
# ============================================================================

## Spawn an entity at a preferred location with terrain type
func spawn_entity(entity_type: String, terrain_type: int, preferred_q: int, preferred_r: int, search_radius: int = 10) -> void:
	if not event_bridge:
		push_error("UnifiedEventBridge: Rust bridge not initialized!")
		return

	event_bridge.spawn_entity(entity_type, terrain_type, preferred_q, preferred_r, search_radius)

# ============================================================================
# PATHFINDING API (Compatible with UnifiedPathfindingBridge)
# ============================================================================

## Request pathfinding for an entity
func request_path(ulid: PackedByteArray, terrain_type: int, start_q: int, start_r: int, goal_q: int, goal_r: int, avoid_entities: bool = true) -> void:
	if not event_bridge:
		push_error("UnifiedEventBridge: Rust bridge not initialized!")
		return

	event_bridge.request_path(ulid, terrain_type, start_q, start_r, goal_q, goal_r, avoid_entities)

## Request random destination for an entity
func request_random_destination(ulid: PackedByteArray, terrain_type: int, start_q: int, start_r: int, min_distance: int, max_distance: int) -> void:
	if not event_bridge:
		push_error("UnifiedEventBridge: Rust bridge not initialized!")
		return

	event_bridge.request_random_destination(ulid, terrain_type, start_q, start_r, min_distance, max_distance)

# ============================================================================
# ENTITY STATE API
# ============================================================================

## Update entity position (notify Rust of position changes)
func update_entity_position(ulid: PackedByteArray, q: int, r: int) -> void:
	if not event_bridge:
		return

	event_bridge.update_entity_position(ulid, q, r)

## Update entity state flags
func set_entity_state(ulid: PackedByteArray, state: int) -> void:
	if not event_bridge:
		return

	event_bridge.set_entity_state(ulid, state)

## Remove entity from tracking
func remove_entity(ulid: PackedByteArray) -> void:
	if not event_bridge:
		return

	event_bridge.remove_entity(ulid)

# ============================================================================
# ECONOMY API (Compatible with ResourceLedger)
# ============================================================================

## Register a resource producer
func register_producer(ulid: PackedByteArray, resource_type: int, rate_per_sec: float, active: bool = true) -> void:
	if not event_bridge:
		return

	event_bridge.register_producer(ulid, resource_type, rate_per_sec, active)

## Register a resource consumer
func register_consumer(ulid: PackedByteArray, resource_type: int, rate_per_sec: float, active: bool = true) -> void:
	if not event_bridge:
		return

	event_bridge.register_consumer(ulid, resource_type, rate_per_sec, active)

## Remove a producer
func remove_producer(ulid: PackedByteArray) -> void:
	if not event_bridge:
		return

	event_bridge.remove_producer(ulid)

## Remove a consumer
func remove_consumer(ulid: PackedByteArray) -> void:
	if not event_bridge:
		return

	event_bridge.remove_consumer(ulid)

# ============================================================================
# STATS API (Compatible with EntityManagerBridge/StatsManager)
# ============================================================================

## Register entity stats (called when entity spawns)
func register_entity_stats(ulid: PackedByteArray, player_ulid: PackedByteArray, entity_type: String, terrain_type: int, q: int, r: int, combat_type: int, projectile_type: int, combat_range: int, aggro_range: int) -> void:
	if not event_bridge:
		return

	event_bridge.register_entity_stats(ulid, player_ulid, entity_type, terrain_type, q, r, combat_type, projectile_type, combat_range, aggro_range)

## Set a stat value for an entity
func set_stat(ulid: PackedByteArray, stat_type: int, value: float) -> void:
	if not event_bridge:
		return

	event_bridge.set_stat(ulid, stat_type, value)

## Entity takes damage
func take_damage(ulid: PackedByteArray, damage: float) -> void:
	if not event_bridge:
		return

	event_bridge.take_damage(ulid, damage)

## Heal entity
func heal(ulid: PackedByteArray, amount: float) -> void:
	if not event_bridge:
		return

	event_bridge.heal(ulid, amount)

## Called by projectile when it hits target
## This applies the damage for ranged/bow/magic combat
func projectile_hit(attacker_ulid: PackedByteArray, defender_ulid: PackedByteArray, damage: int, projectile_type: int) -> void:
	if not event_bridge:
		return

	event_bridge.projectile_hit(attacker_ulid, defender_ulid, damage, projectile_type)

# ============================================================================
# RESOURCE API (Compatible with ResourceLedger)
# ============================================================================

## Add resources (called by combo system, building rewards, etc.)
func add_resources(resource_type: int, amount: float) -> void:
	if not event_bridge:
		return

	event_bridge.add_resources(resource_type, amount)

## Spend resources (called by building costs, unit spawning, etc.)
## Accepts PackedByteArray with serialized cost data
func spend_resources(costs_bytes: PackedByteArray) -> void:
	if not event_bridge:
		push_error("UnifiedEventBridge: event_bridge not initialized!")
		return

	# Debug: Log what we're sending
	print("UnifiedEventBridge.spend_resources() called with %d bytes" % costs_bytes.size())

	event_bridge.spend_resources(costs_bytes)

## Process turn-based resource consumption (called by GameTimer on turn end)
## Consumes 1 food per active entity
func process_turn_consumption() -> void:
	if not event_bridge:
		return

	event_bridge.process_turn_consumption()

## Get a single stat value for an entity (synchronous query)
func get_stat(ulid: PackedByteArray, stat_type: int) -> float:
	if not event_bridge:
		return 0.0

	return event_bridge.get_stat(ulid, stat_type)

## Get all stats for an entity as a Dictionary (synchronous query)
func get_all_stats(ulid: PackedByteArray) -> Dictionary:
	if not event_bridge:
		return {}

	return event_bridge.get_all_stats(ulid)

# ============================================================================
# CARD API (Single Source of Truth via Actor's CardRegistry)
# ============================================================================

## Place a card on the board at specific hex coordinates
## Actor's CardRegistry is the single source of truth for card placement
func place_card(x: int, y: int, ulid: PackedByteArray, suit: int, value: int, card_id: int, is_custom: bool) -> void:
	if not event_bridge:
		push_error("UnifiedEventBridge: Rust bridge not initialized!")
		return

	event_bridge.place_card(x, y, ulid, suit, value, card_id, is_custom)

## Remove a card from the board by position
func remove_card_at(x: int, y: int) -> void:
	if not event_bridge:
		return

	event_bridge.remove_card_at(x, y)

## Remove a card from the board by ULID
func remove_card_by_ulid(ulid: PackedByteArray) -> void:
	if not event_bridge:
		return

	event_bridge.remove_card_by_ulid(ulid)

## Request combo detection at a specific position
## Actor will check cards in radius and emit combo event if found
func detect_combo(center_x: int, center_y: int, radius: int) -> void:
	if not event_bridge:
		return

	event_bridge.detect_combo(center_x, center_y, radius)

# ============================================================================
# IRC CHAT API - DEPRECATED
# ============================================================================
# IRC functionality has been moved to IrcWebSocketClient autoload
# See /root/IrcWebSocketClient for IRC connection and messaging
# Methods kept as stubs for backward compatibility but will warn if called
