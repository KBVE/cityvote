extends CanvasLayer
class_name PlayHand

# === Signals ===
signal card_picked_up()  # Emitted when player picks up a card
signal card_placed()     # Emitted when card is placed on tile
signal card_cancelled()  # Emitted when card placement is cancelled

@onready var card_container: Control = $HandPanel/MarginContainer/VBoxContainer/CardContainer
@onready var hand_panel: PanelContainer = $HandPanel
@onready var card_count_label: Label = $HandPanel/MarginContainer/VBoxContainer/CardCountLabel

# Reference to the hex map (set from main scene)
var hex_map = null

# Reference to camera for auto-follow
var camera: Camera2D = null

# Camera bounds (set from main scene)
var camera_min_bounds: Vector2 = Vector2.ZERO
var camera_max_bounds: Vector2 = Vector2.ZERO

# Camera auto-follow settings
var camera_follow_enabled: bool = true
var camera_follow_speed: float = 3.0  # How fast camera follows cursor (lower = smoother)
var camera_edge_threshold: float = 250.0  # Distance from center before camera starts following (larger = more flexible)

# Current hand of cards
var hand: Array[Dictionary] = []

# Card size
var card_width: float = 64.0
var card_height: float = 90.0

# Card fanning settings (spreading cards in an arc)
var card_spacing: float = 35.0  # Reduced from 50 for more overlap
var arc_height: float = 15.0  # Height of the arc curve (concave up)
var fan_rotation: float = 8.0  # Degrees per card from center for fanning

# === Card State Machine ===
enum CardState { IDLE, HOVER, HELD, PREVIEW, PLACED, CANCELED }
var card_state: CardState = CardState.IDLE

# === Held Card (Game Logic) ===
var held_card: Control = null  # Authoritative game state
var held_card_data: Dictionary = {}  # Card suit/value
var held_card_source_position: Vector2 = Vector2.ZERO  # Origin in fan
var held_card_source_rotation: float = 0.0
var held_card_source_scale: Vector2 = Vector2.ONE
var held_card_source_index: int = -1

# === Card Preview Ghost (Visual) ===
var preview_ghost: Sprite2D = null  # Visual proxy that follows cursor
var preview_ghost_target_tile: Vector2i = Vector2i(-1, -1)  # Current tile under ghost
var ghost_scale: float = 0.8  # Ghost is slightly transparent/smaller
var ghost_alpha_moving: float = 0.15  # Super transparent while moving
var ghost_alpha_snapped: float = 0.85  # More visible when snapped to tile
var ghost_fade_speed: float = 8.0  # How fast the ghost fades in/out

# Hand panel opacity settings
var panel_opacity_idle: float = 0.3  # Low opacity when idle
var panel_opacity_active: float = 1.0  # Full opacity on hover
var panel_fade_speed: float = 6.0  # How fast panel fades in/out

func _ready() -> void:
	# Defer to ensure all autoloads are ready
	call_deferred("_initialize")

func _initialize() -> void:
	draw_initial_hand()

	# Set initial panel opacity to low
	hand_panel.modulate.a = panel_opacity_idle

	# Connect hover signals for panel
	hand_panel.mouse_entered.connect(_on_hand_panel_mouse_entered)
	hand_panel.mouse_exited.connect(_on_hand_panel_mouse_exited)

	# Apply Alagard font to card count label
	var font = Cache.get_font("alagard")
	if font:
		card_count_label.add_theme_font_override("font", font)
	else:
		push_warning("PlayHand: Could not load Alagard font from Cache")

	# Update card count
	_update_card_count()

# Draw 7 random cards from the deck (guaranteed unique)
func draw_initial_hand() -> void:
	hand.clear()
	clear_hand_display()

	# Draw 7 unique cards from CardDeck
	var card_deck = get_node("/root/CardDeck")
	for i in range(7):
		var card_data = card_deck.draw_card()
		if card_data.is_empty():
			push_warning("PlayHand: Failed to draw card %d" % i)
			continue

		hand.append(card_data)
		display_card(card_data, i)

	# Refresh fan layout after all cards are loaded (deferred to ensure container is sized)
	call_deferred("_refresh_card_positions")

# Update card count label
func _update_card_count() -> void:
	if card_count_label:
		card_count_label.text = "Cards: %d" % hand.size()

# Add a card to the hand
func add_card_to_hand(suit: int, value: int) -> void:
	var card_data = {
		"suit": suit,
		"value": value
	}
	hand.append(card_data)
	display_card(card_data, hand.size() - 1)
	_update_card_count()

# Refresh all card positions to match current fan layout
func _refresh_card_positions() -> void:
	var total_cards = card_container.get_child_count()
	if total_cards == 0:
		return

	var center_index = (total_cards - 1) / 2.0

	# Calculate container center for positioning
	var container_width = card_container.size.x
	var container_center_x = container_width / 2.0

	for i in range(total_cards):
		var card_wrapper = card_container.get_child(i)
		var offset_from_center = i - center_index

		# Set pivot point to bottom center of card for rotation
		card_wrapper.pivot_offset = Vector2(card_width / 2.0, card_height)

		# Calculate horizontal position (spread cards with card_spacing)
		var base_x = container_center_x + (offset_from_center * card_spacing) - (card_width / 2.0)
		card_wrapper.position.x = base_x

		# Rotate card for fanning effect
		card_wrapper.rotation_degrees = offset_from_center * fan_rotation

		# Adjust vertical position to create arc curve (concave up - cards dip toward center)
		var arc_offset = abs(offset_from_center) * arc_height
		card_wrapper.position.y = arc_offset  # Positive y to create concave up arc

# Reorganize hand with smooth animation after card is removed/added
func _reorganize_hand() -> void:
	var total_cards = card_container.get_child_count()
	if total_cards == 0:
		return

	var center_index = (total_cards - 1) / 2.0

	# Calculate container center for positioning
	var container_width = card_container.size.x
	var container_center_x = container_width / 2.0

	for i in range(total_cards):
		var card_wrapper = card_container.get_child(i)
		var offset_from_center = i - center_index

		# Set pivot point to bottom center of card for rotation
		card_wrapper.pivot_offset = Vector2(card_width / 2.0, card_height)

		# Calculate new positions
		var target_x = container_center_x + (offset_from_center * card_spacing) - (card_width / 2.0)
		var target_rotation = offset_from_center * fan_rotation
		var arc_offset = abs(offset_from_center) * arc_height

		# Animate to new position smoothly
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(card_wrapper, "position:x", target_x, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(card_wrapper, "position:y", arc_offset, 0.4).set_ease(Tween.EASE_OUT)
		tween.tween_property(card_wrapper, "rotation_degrees", target_rotation, 0.4).set_ease(Tween.EASE_OUT)
		tween.tween_property(card_wrapper, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT)
		tween.tween_property(card_wrapper, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.3)

# Display a single card in the hand
func display_card(card_data: Dictionary, index: int) -> void:
	# Create a control wrapper for each card to handle rotation and hover
	var card_wrapper = Control.new()
	card_wrapper.name = "Card_%d" % index
	card_wrapper.custom_minimum_size = Vector2(card_width, card_height)
	card_wrapper.mouse_filter = Control.MOUSE_FILTER_PASS

	# Get the pooled sprite from CardDeck
	var card_deck = get_node("/root/CardDeck")
	var card_sprite = card_deck.get_card_sprite(card_data.suit, card_data.value)

	if card_sprite == null:
		push_error("PlayHand: Failed to get sprite for card %s_%d" % [card_data.suit, card_data.value])
		return

	# Reparent sprite to wrapper
	if card_sprite.get_parent():
		card_sprite.get_parent().remove_child(card_sprite)
	card_wrapper.add_child(card_sprite)

	# Position sprite within wrapper (centered)
	card_sprite.position = Vector2(card_width / 2.0, card_height / 2.0)

	# Fan the cards - rotate based on position from center
	var total_cards = 7
	var center_index = (total_cards - 1) / 2.0
	var offset_from_center = index - center_index

	# Set pivot point to bottom center of card for rotation
	card_wrapper.pivot_offset = Vector2(card_width / 2.0, card_height)

	# Rotate card for fanning effect
	card_wrapper.rotation_degrees = offset_from_center * fan_rotation

	# Adjust vertical position to create arc curve (concave up - cards dip toward center)
	var arc_offset = abs(offset_from_center) * arc_height
	card_wrapper.position.y = arc_offset  # Positive y to create concave up arc

	# Connect hover and input signals
	card_wrapper.mouse_entered.connect(_on_card_mouse_entered.bind(card_wrapper))
	card_wrapper.mouse_exited.connect(_on_card_mouse_exited.bind(card_wrapper))
	card_wrapper.gui_input.connect(_on_card_gui_input.bind(card_wrapper))

	# Add to container
	card_container.add_child(card_wrapper)

# Card hover effects
func _on_card_mouse_entered(card: Control) -> void:
	if card_state != CardState.IDLE:
		return  # Don't hover effect while card is held

	# Lift card up and make it slightly larger
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "position:y", card.position.y - 20, 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2(1.1, 1.1), 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate", Color(1.2, 1.2, 1.2, 1.0), 0.2)

func _on_card_mouse_exited(card: Control) -> void:
	if held_card == card:
		return  # Don't reset while this card is held

	# Return card to original position
	var original_y = 0.0
	# Calculate arc offset based on card index (concave up)
	var card_index = card.get_index()
	var total_cards = 7
	var center_index = (total_cards - 1) / 2.0
	var offset_from_center = card_index - center_index
	var arc_offset = abs(offset_from_center) * arc_height
	original_y = arc_offset  # Positive for concave up

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "position:y", original_y, 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2(1.0, 1.0), 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.2)

# Hand panel hover effects
func _on_hand_panel_mouse_entered() -> void:
	# Fade in panel to full opacity
	var tween = create_tween()
	tween.tween_property(hand_panel, "modulate:a", panel_opacity_active, 0.3).set_ease(Tween.EASE_OUT)

func _on_hand_panel_mouse_exited() -> void:
	# Fade out panel to low opacity
	var tween = create_tween()
	tween.tween_property(hand_panel, "modulate:a", panel_opacity_idle, 0.3).set_ease(Tween.EASE_OUT)

# === EVENT: Pick Card ===
func _on_card_gui_input(event: InputEvent, card: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_event_pick_card(card)

func _process(delta: float) -> void:
	if card_state == CardState.HELD or card_state == CardState.PREVIEW:
		_update_preview_ghost(delta)
		_update_camera_follow(delta)

func _input(event: InputEvent) -> void:
	if card_state == CardState.IDLE or card_state == CardState.HOVER:
		return

	# === EVENT: Confirm Place (Double-Click) ===
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		_event_confirm_place()
		get_viewport().set_input_as_handled()

	# === EVENT: Cancel (Right-Click) ===
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_event_cancel()
		get_viewport().set_input_as_handled()

	# === EVENT: Cancel (ESC Key) ===
	elif event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		_event_cancel()
		get_viewport().set_input_as_handled()

# ===================================================================
# STATE MACHINE EVENTS
# ===================================================================

# EVENT: Pick Card - Transition IDLE → HELD
func _event_pick_card(card: Control) -> void:
	held_card = card
	held_card_source_index = card.get_index()
	held_card_source_position = card.position
	held_card_source_rotation = card.rotation_degrees
	held_card_source_scale = card.scale

	# Get card data from hand array
	if held_card_source_index < hand.size():
		held_card_data = hand[held_card_source_index]

	# Create preview ghost
	_create_preview_ghost()

	# Hide source card in hand
	held_card.modulate = Color(1, 1, 1, 0.3)  # Make semi-transparent

	# Transition to HELD state
	card_state = CardState.HELD

	# Emit signal (for future use if needed)
	card_picked_up.emit()

	print("State: IDLE → HELD")

# EVENT: Confirm Place - Transition PREVIEW → PLACED
func _event_confirm_place() -> void:
	if card_state != CardState.PREVIEW:
		return  # Can only place from PREVIEW state

	if preview_ghost_target_tile != Vector2i(-1, -1):
		_place_card_on_tile(preview_ghost_target_tile)
		card_state = CardState.PLACED

		# Emit signal to re-enable manual camera panning
		card_placed.emit()

		print("State: PREVIEW → PLACED")

# EVENT: Cancel - Transition * → CANCELED → IDLE
func _event_cancel() -> void:
	_return_card_to_source()
	card_state = CardState.IDLE

	# Emit signal to re-enable manual camera panning
	card_cancelled.emit()

	print("State: * → CANCELED → IDLE")

# ===================================================================
# PREVIEW GHOST MANAGEMENT
# ===================================================================

func _create_preview_ghost() -> void:
	if preview_ghost != null:
		preview_ghost.queue_free()

	preview_ghost = Sprite2D.new()
	preview_ghost.texture = held_card.get_child(0).texture
	preview_ghost.modulate = Color(1, 1, 1, ghost_alpha_moving)  # Start super transparent
	preview_ghost.scale = Vector2(ghost_scale, ghost_scale)
	hex_map.add_child(preview_ghost)

func _update_preview_ghost(delta: float) -> void:
	if preview_ghost == null or hex_map == null:
		return

	# Get mouse position in world coordinates
	var mouse_world_pos = hex_map.get_global_mouse_position()

	# Convert to tile coordinates
	var tile_coords = hex_map.tile_map.local_to_map(mouse_world_pos)

	# Check if tile is valid
	if tile_coords.x >= 0 and tile_coords.x < 50 and tile_coords.y >= 0 and tile_coords.y < 50:
		# Valid tile - snap ghost to tile center
		var tile_world_pos = hex_map.tile_map.map_to_local(tile_coords)
		preview_ghost.position = tile_world_pos
		preview_ghost_target_tile = tile_coords

		# Transition to PREVIEW state if hovering valid tile
		if card_state == CardState.HELD:
			card_state = CardState.PREVIEW

		# Fade in ghost when snapped to valid tile (green tint)
		var target_color = Color(0.8, 1, 0.8, ghost_alpha_snapped)
		preview_ghost.modulate = preview_ghost.modulate.lerp(target_color, ghost_fade_speed * delta)
	else:
		# Invalid tile - follow mouse freely
		preview_ghost.position = mouse_world_pos
		preview_ghost_target_tile = Vector2i(-1, -1)

		# Transition back to HELD if not over valid tile
		if card_state == CardState.PREVIEW:
			card_state = CardState.HELD

		# Fade out ghost when moving (super transparent)
		var target_color = Color(1, 1, 1, ghost_alpha_moving)
		preview_ghost.modulate = preview_ghost.modulate.lerp(target_color, ghost_fade_speed * delta)

func _destroy_preview_ghost() -> void:
	if preview_ghost != null:
		preview_ghost.queue_free()
		preview_ghost = null
	preview_ghost_target_tile = Vector2i(-1, -1)

func _update_camera_follow(delta: float) -> void:
	if not camera_follow_enabled or camera == null or hex_map == null:
		return

	# Get mouse position in world coordinates
	var mouse_world_pos = hex_map.get_global_mouse_position()

	# Get camera center in world coordinates
	var camera_center = camera.get_screen_center_position()

	# Calculate offset from camera center to mouse
	var offset = mouse_world_pos - camera_center
	var distance_from_center = offset.length()

	# Only follow if mouse is beyond threshold
	if distance_from_center > camera_edge_threshold:
		# Calculate how far beyond threshold we are
		var overshoot = distance_from_center - camera_edge_threshold

		# Normalize the offset to get direction
		var direction = offset.normalized()

		# Target position: move camera to bring mouse back to threshold distance
		var target_camera_pos = camera.position + direction * overshoot

		# Smoothly interpolate using lerp for buttery smooth movement
		var new_pos = camera.position.lerp(target_camera_pos, camera_follow_speed * delta)

		# Debug: Check if clamping is blocking movement
		var pre_clamp_pos = new_pos

		# Clamp to camera bounds (if bounds are set)
		if camera_min_bounds != Vector2.ZERO or camera_max_bounds != Vector2.ZERO:
			new_pos.x = clamp(new_pos.x, camera_min_bounds.x, camera_max_bounds.x)
			new_pos.y = clamp(new_pos.y, camera_min_bounds.y, camera_max_bounds.y)

		# Debug: Print when bounds are clamping
		if pre_clamp_pos != new_pos:
			print("Camera clamped! Pre: ", pre_clamp_pos, " Post: ", new_pos, " Bounds: ", camera_min_bounds, " to ", camera_max_bounds)

		camera.position = new_pos

# ===================================================================
# CARD PLACEMENT
# ===================================================================

func _place_card_on_tile(tile_coords: Vector2i) -> void:
	if hex_map == null or held_card == null:
		return

	# Convert tile coordinates to world position
	var world_pos = hex_map.tile_map.map_to_local(tile_coords)

	# Transfer the actual card sprite from hand to board (reuse same sprite!)
	var card_sprite = held_card.get_child(0)  # Get the Sprite2D from wrapper

	# Remove from hand wrapper
	held_card.remove_child(card_sprite)

	# Reset sprite properties for board placement
	card_sprite.position = world_pos
	card_sprite.rotation = 0
	card_sprite.scale = Vector2(0.15, 0.15)  # Downscale to fit tile
	card_sprite.modulate = Color.WHITE

	# Check if placed on water tile and apply wave shader
	var tile_type = hex_map.get_tile_type_at_coords(tile_coords)
	if tile_type == "water":
		_apply_wave_shader(card_sprite)

	# Add to hex map
	hex_map.add_child(card_sprite)

	# Register card with hex map
	hex_map.place_card_on_tile(tile_coords, card_sprite, held_card_data.suit, held_card_data.value)

	# Remove card from hand array
	if held_card_source_index < hand.size():
		hand.remove_at(held_card_source_index)

	# Remove card from container immediately (not queue_free to avoid gaps)
	card_container.remove_child(held_card)
	held_card.queue_free()

	# Update card count
	_update_card_count()

	# Reorganize remaining cards in hand with animation
	call_deferred("_reorganize_hand")

	# Clean up
	_destroy_preview_ghost()
	held_card = null
	held_card_data = {}

	print("Card placed on tile ", tile_coords, " at world pos ", world_pos)

func _return_card_to_source() -> void:
	if held_card == null:
		return

	# Restore source card visibility
	held_card.modulate = Color(1, 1, 1, 1)

	# Animate back to source position
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(held_card, "position", held_card_source_position, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(held_card, "rotation_degrees", held_card_source_rotation, 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(held_card, "scale", held_card_source_scale, 0.2).set_ease(Tween.EASE_OUT)

	# Clean up
	_destroy_preview_ghost()
	held_card = null
	held_card_data = {}

# Clear all cards from display
func clear_hand_display() -> void:
	for child in card_container.get_children():
		child.queue_free()

# Shuffle and redraw the hand
func redraw_hand() -> void:
	draw_initial_hand()

# Apply wave shader to sprite (for water tiles)
func _apply_wave_shader(sprite: Sprite2D) -> void:
	# Create shader material from Cache with parameters
	var shader_material = Cache.create_shader_material("with_wave", {
		"wave_speed": 0.8,
		"wave_amplitude": 2.0,  # Small vertical bob
		"sway_amplitude": 1.5,  # Subtle horizontal sway
		"wave_frequency": 1.5,
		"rotation_amount": 1.0  # Slight rocking
	})

	if shader_material:
		sprite.material = shader_material

# Get card name as string (for debugging)
func get_card_name(suit: int, value: int) -> String:
	var suit_name = ""
	match suit:
		PlayingDeck.Suit.SPADES:
			suit_name = "Spades"
		PlayingDeck.Suit.HEARTS:
			suit_name = "Hearts"
		PlayingDeck.Suit.DIAMONDS:
			suit_name = "Diamonds"
		PlayingDeck.Suit.CLUBS:
			suit_name = "Clubs"

	var value_name = ""
	match value:
		1:
			value_name = "Ace"
		11:
			value_name = "Jack"
		12:
			value_name = "Queen"
		13:
			value_name = "King"
		_:
			value_name = str(value)

	return "%s of %s" % [value_name, suit_name]
