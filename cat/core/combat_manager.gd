extends Node

# CombatManager - Handles combat signals from Rust bridge
# This manager listens to combat events and triggers appropriate visual/audio feedback
# The actual combat logic runs in a Rust worker thread

# Rust bridge
var combat_bridge: CombatBridge = null

# Signal for when combat starts (can be used by UI/camera)
signal combat_started(attacker_ulid: PackedByteArray, defender_ulid: PackedByteArray)

# Signal for when combat ends
signal combat_ended(attacker_ulid: PackedByteArray, defender_ulid: PackedByteArray, winner_ulid: PackedByteArray)

func _ready() -> void:
	# Create Rust bridge
	combat_bridge = CombatBridge.new()
	add_child(combat_bridge)
	combat_bridge.name = "RustBridge"

	# Connect to combat bridge signals
	combat_bridge.combat_started.connect(_on_combat_started)
	combat_bridge.damage_dealt.connect(_on_damage_dealt)
	combat_bridge.combat_ended.connect(_on_combat_ended)
	combat_bridge.entity_died.connect(_on_entity_died)

## Called when combat starts between two entities
func _on_combat_started(attacker_ulid: PackedByteArray, defender_ulid: PackedByteArray) -> void:
	if attacker_ulid.is_empty() or defender_ulid.is_empty():
		push_error("CombatManager: Invalid ULIDs in combat_started")
		return

	# Set IN_COMBAT flag on both entities (0x40 / 0b1000000)
	_set_combat_flag(attacker_ulid, true)
	_set_combat_flag(defender_ulid, true)

	# Re-emit for other systems (like camera, UI)
	combat_started.emit(attacker_ulid, defender_ulid)

	# Show combat indicator on both entities
	_add_combat_indicator(attacker_ulid)
	_add_combat_indicator(defender_ulid)

## Called when damage is dealt during combat
func _on_damage_dealt(
	attacker_ulid: PackedByteArray,
	defender_ulid: PackedByteArray,
	damage: float,
	new_hp: float
) -> void:
	if defender_ulid.is_empty():
		push_error("CombatManager: Invalid defender ULID in damage_dealt")
		return

	# Apply damage through StatsManager to trigger signals
	# This will emit stat_changed signal for health bars to update
	if StatsManager:
		var _actual_damage = StatsManager.take_damage(defender_ulid, damage)
	else:
		push_error("CombatManager: StatsManager not available to apply damage")

	# CRITICAL: Validate entities using defensive programming helper
	var defender = UlidManager.get_instance(defender_ulid) as Node2D
	defender = EntityManager.get_valid_entity_with_ulid(defender, defender_ulid)
	if not defender:
		# Entity freed, despawned, or ULID mismatch (pooled/reused)
		return

	var attacker = UlidManager.get_instance(attacker_ulid) as Node2D
	attacker = EntityManager.get_valid_entity_with_ulid(attacker, attacker_ulid)
	if not attacker:
		return

	# Check if entity is visible (in viewport)
	var is_visible = _is_entity_visible(defender)

	# Fire projectile - always fire if both entities exist
	_fire_projectile(attacker, defender)

	# Display damage number popup (only if visible)
	if is_visible:
		_show_damage_number(defender, damage)

	# TODO: Screen shake for critical hits

## Called when combat ends
func _on_combat_ended(
	attacker_ulid: PackedByteArray,
	defender_ulid: PackedByteArray,
	winner_ulid: PackedByteArray
) -> void:
	if winner_ulid.is_empty():
		push_error("CombatManager: Invalid winner ULID in combat_ended")
		return

	# Clear IN_COMBAT flag on both entities (allow movement to resume)
	_set_combat_flag(attacker_ulid, false)
	_set_combat_flag(defender_ulid, false)

	# Remove combat indicators
	_remove_combat_indicator(attacker_ulid)
	_remove_combat_indicator(defender_ulid)

	# Re-emit for other systems
	combat_ended.emit(attacker_ulid, defender_ulid, winner_ulid)

	# TODO: Play victory/defeat sound
	# TODO: Award experience/loot

## Called when an entity dies
func _on_entity_died(ulid: PackedByteArray) -> void:
	if ulid.is_empty():
		push_error("CombatManager: Invalid ULID in entity_died")
		return

	var entity = UlidManager.get_instance(ulid)
	if entity == null or not is_instance_valid(entity):
		push_warning("CombatManager: Entity died but instance not found (may have been cleaned up): %s" % UlidManager.to_hex(ulid))
		return

	# Trigger death animation (if visible)
	if _is_entity_visible(entity):
		_trigger_death_animation(entity)

	# Mark entity as dead in combat system
	if combat_bridge:
		combat_bridge.mark_dead(ulid)
	else:
		push_error("CombatManager: Combat bridge not available for marking entity dead")

	# TODO: Drop loot
	# TODO: Update player stats/quest progress

## Set or clear IN_COMBAT flag on an entity
func _set_combat_flag(ulid: PackedByteArray, enable: bool) -> void:
	var entity = UlidManager.get_instance(ulid)
	if entity == null or not is_instance_valid(entity):
		return

	if not "current_state" in entity:
		return  # Entity doesn't have state system

	const IN_COMBAT = 0x40  # 0b1000000

	if enable:
		entity.current_state |= IN_COMBAT  # Set flag
	else:
		entity.current_state &= ~IN_COMBAT  # Clear flag

## Check if entity is visible in viewport
func _is_entity_visible(entity: Node2D) -> bool:
	# Simple check - can be improved with proper camera bounds check
	if not entity.visible:
		return false

	# Check if entity has a VisibleOnScreenNotifier2D
	for child in entity.get_children():
		if child is VisibleOnScreenNotifier2D:
			return child.is_on_screen()

	# Default to true if no notifier (always show feedback)
	return true

## Display floating damage number
func _show_damage_number(entity: Node2D, damage: float) -> void:
	# Create damage label
	var label = Label.new()
	label.text = "-%d" % int(damage)
	label.modulate = Color.RED

	# Add to entity (will move with it)
	entity.add_child(label)
	label.position = Vector2(0, -30)  # Above entity

	# Animate upward and fade out
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40, 1.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.finished.connect(func(): label.queue_free())

## Trigger death animation on entity
func _trigger_death_animation(entity: Node) -> void:
	# Check if entity has death animation method
	if entity.has_method("play_death_animation"):
		entity.play_death_animation()
	else:
		# Default fade out
		var tween = create_tween()
		tween.tween_property(entity, "modulate:a", 0.0, 0.5)
		tween.finished.connect(func(): entity.queue_free())

## Fire a projectile from attacker to defender
func _fire_projectile(attacker: Node2D, defender: Node2D) -> void:
	if not Cluster:
		push_warning("CombatManager: Cluster not available for projectile")
		return

	# Acquire projectile from pool
	var projectile = Cluster.acquire("projectile") as Projectile
	if not projectile:
		push_warning("CombatManager: Failed to acquire projectile from pool")
		return

	# Add to scene tree (same parent as attacker)
	var parent = attacker.get_parent()
	if not parent:
		push_error("CombatManager: Attacker has no parent node")
		Cluster.release("projectile", projectile)
		return

	parent.add_child(projectile)

	# Set z-index high enough to render above tiles and ships (using Cache constants)
	# Projectiles should be above entities (500) but below UI overlays
	projectile.z_index = Cache.Z_INDEX_WAYPOINTS  # 3000

	# Determine projectile type based on attacker
	var projectile_type = Projectile.Type.SPEAR  # Default
	if attacker.has_method("get_class"):
		var entity_class = attacker.call("get_class")
		if entity_class != null and typeof(entity_class) == TYPE_STRING:
			var class_lower = entity_class.to_lower()
			if "viking" in class_lower:
				projectile_type = Projectile.Type.SPEAR
			elif "jezza" in class_lower:
				projectile_type = Projectile.Type.GLAIVE

	# Setup return callback
	projectile.on_return_to_pool = func(proj):
		if proj.is_inside_tree():
			proj.get_parent().remove_child(proj)
		Cluster.release("projectile", proj)

	# Fire!
	projectile.fire(
		attacker.global_position,
		defender.global_position,
		projectile_type,
		300.0,  # Speed (pixels per second) - slower to be more visible
		30.0,   # Arc height (pixels)
		8       # Max range (tiles) - projectile will "miss" after 8 tiles
	)

## Add combat indicator to entity (red outline/glow)
func _add_combat_indicator(ulid: PackedByteArray) -> void:
	var entity = UlidManager.get_instance(ulid) as Node2D
	if entity == null or not is_instance_valid(entity):
		return

	# Check if indicator already exists
	if entity.has_node("CombatIndicator"):
		return

	# Create a ColorRect as combat indicator (red outline effect)
	var indicator = ColorRect.new()
	indicator.name = "CombatIndicator"
	indicator.color = Color(1.0, 0.0, 0.0, 0.3)  # Semi-transparent red
	indicator.size = Vector2(48, 48)  # Adjust based on entity size
	indicator.position = Vector2(-24, -24)  # Center on entity
	indicator.z_index = -1  # Behind entity

	# Add pulsing animation
	entity.add_child(indicator)

	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(indicator, "modulate:a", 0.5, 0.5)
	tween.tween_property(indicator, "modulate:a", 1.0, 0.5)

## Remove combat indicator from entity
func _remove_combat_indicator(ulid: PackedByteArray) -> void:
	var entity = UlidManager.get_instance(ulid) as Node2D
	if entity == null or not is_instance_valid(entity):
		return

	# Find and remove indicator
	var indicator = entity.get_node_or_null("CombatIndicator")
	if indicator:
		indicator.queue_free()
