extends CanvasLayer
class_name PlayHand

# === Signals ===
signal card_picked_up()  # Emitted when player picks up a card
signal card_placed()     # Emitted when card is placed on tile
signal card_cancelled()  # Emitted when card placement is cancelled
signal card_swapped()    # Emitted when player swaps cards in hand
signal card_hand_entered()  # Emitted when mouse enters hand area
signal card_hand_exited()   # Emitted when mouse exits hand area

@onready var card_container: Control = $HandPanel/MarginContainer/VBoxContainer/CardContainer
@onready var hand_panel: PanelContainer = $HandPanel
@onready var card_count_label: Label = $HandPanel/MarginContainer/VBoxContainer/CardCountLabel

# Swap indicator UI (cached packed scene)
const SWAP_INDICATOR_SCENE = preload("res://view/hand/tooltip/swap_indicator.tscn")
var swap_indicator: Label = null
var swap_indicator_target_card: Control = null

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

# Current hand of cards (now using PooledCard instances)
var hand: Array[PooledCard] = []
var deck_id: int = -1  # Deck ID from CardDeck

# Hand size limit
var MAX_HAND: int = 12  # Maximum cards in hand (can be upgraded later)

# Card size
var card_width: float = 64.0
var card_height: float = 90.0
var card_wrapper_padding: float = 20.0  # Extra padding around cards for better hover detection

# Card fanning settings (spreading cards in an arc)
var card_spacing: float = 35.0  # Reduced from 50 for more overlap
var arc_height: float = 15.0  # Height of the arc curve (concave up)
var fan_rotation: float = 8.0  # Degrees per card from center for fanning

# === Card State Machine ===
enum CardState { IDLE, HOVER, HELD, PREVIEW, PLACED, CANCELED }
var card_state: CardState = CardState.IDLE

# === Held Card (Game Logic) ===
var held_card: Control = null  # Authoritative game state
var held_card_pooled: PooledCard = null  # Reference to the actual PooledCard
var held_card_source_position: Vector2 = Vector2.ZERO  # Origin in fan
var held_card_source_rotation: float = 0.0
var held_card_source_scale: Vector2 = Vector2.ONE
var held_card_source_index: int = -1

# === Card Preview Ghost (Visual) ===
var preview_ghost: MeshInstance2D = null  # Visual proxy that follows cursor
var preview_ghost_target_tile: Vector2i = Vector2i(-1, -1)  # Current tile under ghost
var ghost_scale: float = 0.8  # Ghost is slightly transparent/smaller
var ghost_alpha_moving: float = 0.15  # Super transparent while moving
var ghost_alpha_snapped: float = 0.85  # More visible when snapped to tile
var ghost_fade_speed: float = 8.0  # How fast the ghost fades in/out

# Hand panel opacity settings
var panel_opacity_idle: float = 0.3  # Low opacity when idle
var panel_opacity_active: float = 1.0  # Full opacity on hover
var panel_fade_speed: float = 6.0  # How fast panel fades in/out
var panel_opacity_tween: Tween = null  # Track current opacity tween to kill it when needed
var is_mouse_over_panel: bool = false  # Track mouse hover state

func _ready() -> void:
	# Defer to ensure all autoloads are ready
	call_deferred("_initialize")

func _initialize() -> void:
	# Wait for scene tree to be ready and all resources loaded (critical for WASM)
	await get_tree().process_frame

	# Set initial panel opacity to low
	hand_panel.modulate.a = panel_opacity_idle

	# Block input from passing through the hand panel to prevent accidental clicks on hex tiles
	# Main.gd checks hand_panel rect to prevent camera dragging over hand area
	hand_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Connect to GameTimer for auto-draw
	if GameTimer:
		GameTimer.timer_reset.connect(_on_timer_reset)

	# Connect hover signals for panel
	hand_panel.mouse_entered.connect(_on_hand_panel_mouse_entered)
	hand_panel.mouse_exited.connect(_on_hand_panel_mouse_exited)

	# Apply Alagard font to card count label
	var font = Cache.get_font("alagard")
	if font:
		card_count_label.add_theme_font_override("font", font)
	else:
		push_warning("PlayHand: Could not load Alagard font from Cache")

	# Create swap indicator UI
	_create_swap_indicator()

	# Update card count
	_update_card_count()

	# Draw initial hand AFTER everything else is set up and resources are loaded
	draw_initial_hand()

# Draw 9+ cards: 7 random from deck + 2 guaranteed custom cards
# (Could have more than 2 custom if they get lucky and draw custom cards)
func draw_initial_hand() -> void:
	hand.clear()
	clear_hand_display()

	# Create a deck with custom cards included
	var card_deck = get_node("/root/CardDeck")
	deck_id = card_deck.create_deck(true)  # Deck contains 54 cards (52 standard + 2 custom)

	# Draw 7 random cards from deck (whatever they are - could include custom cards)
	for i in range(7):
		var card = card_deck.draw_card(deck_id)
		if card == null:
			push_warning("PlayHand: Failed to draw card %d" % i)
			continue

		hand.append(card)
		display_card(card, i)

	# Guarantee the 2 custom cards are ALSO in hand (on top of the 7 drawn)
	# Create fresh instances from the pool
	var viking_card = Cluster.acquire("playing_card") as PooledCard
	if viking_card:
		viking_card.init_custom_card(CardAtlas.CARD_VIKINGS)
		hand.append(viking_card)
		display_card(viking_card, hand.size() - 1)

	var dino_card = Cluster.acquire("playing_card") as PooledCard
	if dino_card:
		dino_card.init_custom_card(CardAtlas.CARD_DINO)
		hand.append(dino_card)
		display_card(dino_card, hand.size() - 1)

	# Refresh fan layout after all cards are loaded (deferred to ensure container is sized)
	call_deferred("_refresh_card_positions")

# Update card count label
func _update_card_count() -> void:
	if card_count_label:
		card_count_label.text = "Cards: %d / %d" % [hand.size(), MAX_HAND]

# Add a card to the hand (for manual testing/debugging)
func add_card_to_hand(suit: int, value: int) -> void:
	# Acquire a new card from the pool
	var card = Cluster.acquire("playing_card") as PooledCard
	if card:
		card.init_card(suit, value)
		hand.append(card)
		display_card(card, hand.size() - 1)
		_update_card_count()

		# Refresh fan layout to show new card properly
		call_deferred("_refresh_card_positions")
	else:
		push_error("PlayHand: Failed to acquire card from pool")

# Refresh all card positions to match current fan layout
func _refresh_card_positions() -> void:
	var total_cards = card_container.get_child_count()
	if total_cards == 0:
		return

	var center_index = (total_cards - 1) / 2.0

	# Calculate container center for positioning
	var container_width = card_container.size.x
	var container_center_x = container_width / 2.0

	# Dynamic spacing: reduce spacing when hand is fuller to keep all cards visible
	var dynamic_spacing = card_spacing
	if total_cards > 8:
		# For 9-12 cards, reduce spacing to fit them all
		dynamic_spacing = min(card_spacing, (container_width - 100) / total_cards)

	for i in range(total_cards):
		var card_wrapper = card_container.get_child(i)
		var offset_from_center = i - center_index

		# Set pivot point to bottom center of card for rotation (accounting for padding)
		card_wrapper.pivot_offset = Vector2(card_width / 2.0 + card_wrapper_padding, card_height + card_wrapper_padding)

		# Calculate horizontal position (spread cards with dynamic spacing)
		var base_x = container_center_x + (offset_from_center * dynamic_spacing) - (card_width / 2.0)
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

		# Set pivot point to bottom center of card for rotation (accounting for padding)
		card_wrapper.pivot_offset = Vector2(card_width / 2.0 + card_wrapper_padding, card_height + card_wrapper_padding)

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

	# After reorganizing, check if mouse is still over hand panel and restore opacity
	call_deferred("_check_hand_panel_hover")

# Display a single card in the hand
func display_card(card: PooledCard, index: int) -> void:
	# Create a control wrapper for each card to handle rotation and hover
	var card_wrapper = Control.new()
	card_wrapper.name = "Card_%d" % index
	# Make wrapper larger than card to ensure good hover coverage when rotated/arced
	card_wrapper.custom_minimum_size = Vector2(card_width + card_wrapper_padding * 2, card_height + card_wrapper_padding * 2)
	card_wrapper.mouse_filter = Control.MOUSE_FILTER_PASS

	if card == null:
		push_error("PlayHand: Received null card")
		return

	# Reparent PooledCard sprite to wrapper
	if card.get_parent():
		card.get_parent().remove_child(card)
	card_wrapper.add_child(card)

	# Position sprite within wrapper (centered, accounting for padding)
	card.position = Vector2(card_width / 2.0 + card_wrapper_padding, card_height / 2.0 + card_wrapper_padding)

	# Fan the cards - rotate based on position from center
	# Use actual hand size instead of hardcoded value
	var total_cards = hand.size()
	var center_index = (total_cards - 1) / 2.0
	var offset_from_center = index - center_index

	# Set pivot point to bottom center of card for rotation (accounting for padding)
	card_wrapper.pivot_offset = Vector2(card_width / 2.0 + card_wrapper_padding, card_height + card_wrapper_padding)

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
	# If holding a card, show swap indicator
	if card_state == CardState.HELD or card_state == CardState.PREVIEW:
		# Keep hand panel at full opacity during swap mode
		is_mouse_over_panel = true
		_set_hand_panel_opacity(panel_opacity_active)

		if card != held_card:
			# Hovering over a different card while holding one - show swap indicator
			_show_swap_indicator(card)
			# Highlight the target card with golden tint
			var tween = create_tween()
			tween.tween_property(card, "modulate", Color(1.2, 1.0, 0.6, 1.0), 0.2)  # Golden highlight
		return

	if card_state != CardState.IDLE:
		return  # Don't hover effect while card is held

	# Keep hand panel at full opacity when hovering cards
	is_mouse_over_panel = true
	_set_hand_panel_opacity(panel_opacity_active)

	# Lift card up and make it slightly larger
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "position:y", card.position.y - 20, 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2(1.1, 1.1), 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate", Color(1.2, 1.2, 1.2, 1.0), 0.2)

func _on_card_mouse_exited(card: Control) -> void:
	# Hide swap indicator when leaving card
	if swap_indicator_target_card == card:
		_hide_swap_indicator()

	if held_card == card:
		return  # Don't reset while this card is held

	# Return card to original position
	var original_y = 0.0
	# Calculate arc offset based on card index (concave up)
	var card_index = card.get_index()
	var total_cards = hand.size()  # Use actual hand size
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
	is_mouse_over_panel = true
	_set_hand_panel_opacity(panel_opacity_active)
	card_hand_entered.emit()

func _on_hand_panel_mouse_exited() -> void:
	is_mouse_over_panel = false
	_set_hand_panel_opacity(panel_opacity_idle)
	card_hand_exited.emit()

# Check if mouse is over hand panel and restore full opacity (used after reorganizing)
func _check_hand_panel_hover() -> void:
	# Update the tracked state based on actual mouse position
	var mouse_over = _is_mouse_over_hand_ui()
	is_mouse_over_panel = mouse_over
	# Always set opacity to ensure it's correct after reorganization
	_set_hand_panel_opacity(panel_opacity_active if mouse_over else panel_opacity_idle)

# Set hand panel opacity with proper tween management (kills existing tween first)
func _set_hand_panel_opacity(target_opacity: float) -> void:
	# Kill existing tween to avoid conflicts
	if panel_opacity_tween and panel_opacity_tween.is_valid():
		panel_opacity_tween.kill()

	# Create new tween
	panel_opacity_tween = create_tween()
	panel_opacity_tween.tween_property(hand_panel, "modulate:a", target_opacity, 0.3).set_ease(Tween.EASE_OUT)

# Create the swap indicator UI from cached packed scene
func _create_swap_indicator() -> void:
	swap_indicator = SWAP_INDICATOR_SCENE.instantiate()

	if not swap_indicator:
		push_error("PlayHand: Failed to instantiate swap indicator scene!")
		return

	# Apply Alagard font
	var font = Cache.get_font("alagard")
	if font:
		swap_indicator.add_theme_font_override("font", font)

	# Position it centered above the card container (fixed position)
	if not is_instance_valid(card_container):
		push_error("PlayHand: card_container is invalid!")
		return

	card_container.add_child(swap_indicator)

	# Position above the card container, centered
	# Wait one frame to get proper sizing
	await get_tree().process_frame

	# Validate objects after await
	if not is_instance_valid(swap_indicator) or not is_instance_valid(card_container):
		return

	var container_width = card_container.size.x
	swap_indicator.position = Vector2(
		container_width / 2 - swap_indicator.size.x / 2,
		-swap_indicator.size.y - 10  # 10px above the card container
	)

# Show swap indicator (fixed position above hand panel)
func _show_swap_indicator(target_card: Control) -> void:
	if not swap_indicator:
		return

	swap_indicator_target_card = target_card
	swap_indicator.visible = true

# Hide swap indicator
func _hide_swap_indicator() -> void:
	if swap_indicator:
		swap_indicator.visible = false

	# Reset the golden highlight on the target card (if any)
	if swap_indicator_target_card and is_instance_valid(swap_indicator_target_card):
		var tween = create_tween()
		tween.tween_property(swap_indicator_target_card, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.2)

	swap_indicator_target_card = null

# === EVENT: Pick Card ===
func _on_card_gui_input(event: InputEvent, card: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_event_pick_card(card)

func _process(delta: float) -> void:
	if card_state == CardState.HELD or card_state == CardState.PREVIEW:
		_update_preview_ghost(delta)
		_update_camera_follow(delta)

func _input(event: InputEvent) -> void:
	# Don't block input here - let card wrappers handle clicks via gui_input
	# Main.gd handles blocking drag/camera panning when over hand UI

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

# EVENT: Pick Card - Transition IDLE → HELD (or swap if already holding)
func _event_pick_card(card: Control) -> void:
	# If we're already holding a card, return it to hand first
	if card_state == CardState.HELD or card_state == CardState.PREVIEW:
		# Don't pick the same card twice
		if held_card == card:
			return

		# Return the previous card to its position
		_return_card_to_source()
		print("State: Swapping cards - returned previous card to hand")

		# Emit signal that cards were swapped
		card_swapped.emit()

	held_card = card
	held_card_source_index = card.get_index()
	held_card_source_position = card.position
	held_card_source_rotation = card.rotation_degrees
	held_card_source_scale = card.scale

	# Get PooledCard from hand array
	if held_card_source_index < hand.size():
		held_card_pooled = hand[held_card_source_index]

	# Create preview ghost
	_create_preview_ghost()

	# Hide source card in hand and block mouse input so clicks pass through
	held_card.modulate = Color(1, 1, 1, 0.3)  # Make semi-transparent
	held_card.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let clicks pass through

	# Transition to HELD state
	card_state = CardState.HELD

	# Emit signal (for future use if needed)
	card_picked_up.emit()

	print("State: IDLE → HELD")

# EVENT: Confirm Place - Transition PREVIEW → PLACED
func _event_confirm_place() -> void:
	if card_state != CardState.PREVIEW:
		return  # Can only place from PREVIEW state

	# Check if mouse is over the hand UI - prevent accidental placement
	if _is_mouse_over_hand_ui():
		print("Cannot place card: mouse is over hand UI")
		return

	if preview_ghost_target_tile != Vector2i(-1, -1):
		_place_card_on_tile(preview_ghost_target_tile)
		card_state = CardState.IDLE  # Return to IDLE state after placing

		# Emit signal to re-enable manual camera panning
		card_placed.emit()

		print("State: PREVIEW → PLACED → IDLE")

# EVENT: Cancel - Transition * → CANCELED → IDLE
func _event_cancel() -> void:
	_return_card_to_source()
	card_state = CardState.IDLE

	# Hide swap indicator
	_hide_swap_indicator()

	# Emit signal to re-enable manual camera panning
	card_cancelled.emit()

	print("State: * → CANCELED → IDLE")

# ===================================================================
# PREVIEW GHOST MANAGEMENT
# ===================================================================

func _create_preview_ghost() -> void:
	# The preview ghost IS the held_card_pooled itself, just reparented to follow the cursor
	# We'll reparent it back to the hand wrapper when cancelled, or to the board when placed
	if held_card_pooled:
		preview_ghost = held_card_pooled

		# Debug: Check what card_id the ghost has
		print("Ghost created - card_id: ", held_card_pooled.card_id, " (", held_card_pooled.get_card_name(), ")")
		print("Ghost instance param: ", held_card_pooled.get_instance_shader_parameter("card_id"))

		# Remove from hand wrapper and add to hex_map to follow cursor
		if held_card_pooled.get_parent():
			held_card_pooled.get_parent().remove_child(held_card_pooled)

		hex_map.add_child(held_card_pooled)
		held_card_pooled.modulate = Color(1, 1, 1, ghost_alpha_moving)
		held_card_pooled.scale = Vector2(ghost_scale, ghost_scale)

func _update_preview_ghost(delta: float) -> void:
	if preview_ghost == null or hex_map == null:
		return

	# Get mouse position in world coordinates
	var mouse_world_pos = hex_map.get_global_mouse_position()

	# Offset the ghost to the right of the cursor so it doesn't cover the tile
	var ghost_offset = Vector2(80, 0)  # 80 pixels to the right of cursor

	# Convert to tile coordinates
	var tile_coords = hex_map.tile_map.local_to_map(mouse_world_pos)

	# Check if tile is valid (use MapConfig for correct bounds)
	if tile_coords.x >= 0 and tile_coords.x < MapConfig.MAP_WIDTH and tile_coords.y >= 0 and tile_coords.y < MapConfig.MAP_HEIGHT:
		# Valid tile - snap ghost to tile center with offset
		var tile_world_pos = hex_map.tile_map.map_to_local(tile_coords)
		preview_ghost.position = tile_world_pos + ghost_offset
		preview_ghost_target_tile = tile_coords

		# Transition to PREVIEW state if hovering valid tile
		if card_state == CardState.HELD:
			card_state = CardState.PREVIEW

		# Fade in ghost when snapped to valid tile (green tint)
		var target_color = Color(0.8, 1, 0.8, ghost_alpha_snapped)
		preview_ghost.modulate = preview_ghost.modulate.lerp(target_color, ghost_fade_speed * delta)
	else:
		# Invalid tile - follow mouse freely with offset
		preview_ghost.position = mouse_world_pos + ghost_offset
		preview_ghost_target_tile = Vector2i(-1, -1)

		# Transition back to HELD if not over valid tile
		if card_state == CardState.PREVIEW:
			card_state = CardState.HELD

		# Fade out ghost when moving (super transparent)
		var target_color = Color(1, 1, 1, ghost_alpha_moving)
		preview_ghost.modulate = preview_ghost.modulate.lerp(target_color, ghost_fade_speed * delta)

func _destroy_preview_ghost() -> void:
	# Don't destroy the ghost - it's the actual PooledCard that will be returned to hand or placed
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
	if hex_map == null or held_card == null or held_card_pooled == null:
		return

	# Convert tile coordinates to world position
	var world_pos = hex_map.tile_map.map_to_local(tile_coords)

	# Transfer the actual card sprite from hand to board (reuse same sprite!)
	var card_sprite = held_card_pooled  # The PooledCard sprite

	# Card is already a child of hex_map from the preview ghost, so just reset properties
	# Reset sprite properties for board placement
	card_sprite.position = world_pos
	card_sprite.rotation = 0
	card_sprite.scale = Vector2(0.15, 0.15)  # Downscale to fit tile
	card_sprite.modulate = Color.WHITE

	# Note: Wave shader disabled for cards because it would override the card atlas material
	# and lose the card_id instance parameter. Cards keep their atlas material so they
	# display correctly. If wave effect is needed, a combined shader would be required.

	# Register card with hex map (using PooledCard's suit/value)
	hex_map.place_card_on_tile(tile_coords, card_sprite, card_sprite.suit, card_sprite.value)

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
	_hide_swap_indicator()
	held_card = null
	held_card_pooled = null

	print("Card placed on tile ", tile_coords, " at world pos ", world_pos)

func _return_card_to_source() -> void:
	if held_card == null or held_card_pooled == null:
		return

	# Reparent the PooledCard back to the hand wrapper
	if held_card_pooled.get_parent():
		held_card_pooled.get_parent().remove_child(held_card_pooled)
	held_card.add_child(held_card_pooled)

	# Reset PooledCard transform (accounting for wrapper padding)
	held_card_pooled.position = Vector2(card_width / 2.0 + card_wrapper_padding, card_height / 2.0 + card_wrapper_padding)
	held_card_pooled.rotation = 0
	held_card_pooled.scale = Vector2.ONE
	held_card_pooled.modulate = Color.WHITE

	# Restore wrapper visibility and mouse filter
	held_card.modulate = Color(1, 1, 1, 1)
	held_card.mouse_filter = Control.MOUSE_FILTER_PASS  # Re-enable mouse input

	# Animate wrapper back to source position
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(held_card, "position", held_card_source_position, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(held_card, "rotation_degrees", held_card_source_rotation, 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(held_card, "scale", held_card_source_scale, 0.2).set_ease(Tween.EASE_OUT)

	# Clean up
	_destroy_preview_ghost()
	held_card = null
	held_card_pooled = null

# Clear all cards from display
func clear_hand_display() -> void:
	for child in card_container.get_children():
		child.queue_free()

# Shuffle and redraw the hand
func redraw_hand() -> void:
	draw_initial_hand()

# Get card name as string (for debugging)
func get_card_name(suit: int, value: int) -> String:
	# Use CardAtlas helper for consistent card naming
	return CardAtlas.get_card_name(suit, value)

# Check if mouse is currently over the hand UI
func _is_mouse_over_hand_ui() -> bool:
	var mouse_pos = get_viewport().get_mouse_position()
	var hand_rect = hand_panel.get_global_rect()
	return hand_rect.has_point(mouse_pos)

# Auto-draw card when timer resets (every 60 seconds)
func _on_timer_reset() -> void:
	# Check if hand is at max capacity
	if hand.size() >= MAX_HAND:
		# Send toast: Hand is full
		Toast.show_toast("Hand is full! Use a card to draw more.", 3.0)
		return

	# Hand has space - draw a card
	var card = CardDeck.draw_card(deck_id)
	if card:
		add_card_to_hand(card.suit, card.value)
		# Send toast: Drew a card
		Toast.show_toast("Drew: %s" % get_card_name(card.suit, card.value), 2.5)
	else:
		# No cards left in deck
		Toast.show_toast("Deck is empty!", 2.5)
