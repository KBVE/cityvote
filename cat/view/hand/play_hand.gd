extends CanvasLayer
class_name PlayHand

# === Signals ===
signal card_picked_up()  # Emitted when player picks up a card
signal card_placed()     # Emitted when card is placed on tile
signal card_cancelled()  # Emitted when card placement is cancelled
signal card_swapped()    # Emitted when player swaps cards in hand
signal card_hand_entered()  # Emitted when mouse enters hand area
signal card_hand_exited()   # Emitted when mouse exits hand area

@onready var hand_container: Control = $HandContainer
@onready var card_container: Control = $HandContainer/CardContainer
@onready var card_count_label: Label = $HandContainer/CardCountLabel
@onready var mulligan_button: Button = $HandContainer/MulliganButton

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

# Last placed card position (for combo detection optimization)
var last_placed_card_pos: Vector2i = Vector2i(-1, -1)
const COMBO_CHECK_RADIUS: int = 7  # Only check cards within this hex distance

# Mulligan tracking
var cards_placed_this_game: int = 0  # Track if any cards have been placed
const MULLIGAN_COST: int = 1  # Gold cost per mulligan

# Card size
var card_width: float = 64.0
var card_height: float = 90.0
var card_wrapper_padding: float = 20.0  # Extra padding around cards for better hover detection

# Card fanning settings (spreading cards in an arc)
var card_spacing: float = 35.0  # Reduced from 50 for more overlap
var arc_height: float = 8.0  # Height of the arc curve (concave up) - reduced for less arch
var fan_rotation: float = 6.0  # Degrees per card from center for fanning - reduced for gentler fan

# === Card State Machine ===
enum CardState { IDLE, HOVER, HELD, PREVIEW, PLACED, CANCELED }
var card_state: CardState = CardState.IDLE

# === Held Card (Game Logic) ===
var held_card: Control = null  # The wrapper Control (never moves from its slot)
var held_card_pooled: PooledCard = null  # The actual PooledCard sprite (becomes ghost)
var held_card_source_index: int = -1  # Index in hand array

# === Card Preview Ghost (Visual) ===
var preview_ghost: MeshInstance2D = null  # Visual proxy that follows cursor
var preview_ghost_target_tile: Vector2i = Vector2i(-1, -1)  # Current tile under ghost
var ghost_scale: float = 0.8  # Ghost is slightly transparent/smaller
var ghost_alpha_moving: float = 0.15  # Super transparent while moving
var ghost_alpha_snapped: float = 0.85  # More visible when snapped to tile
var ghost_fade_speed: float = 8.0  # How fast the ghost fades in/out

func _ready() -> void:
	# Defer to ensure all autoloads are ready
	call_deferred("_initialize")

func _initialize() -> void:
	# Wait for scene tree to be ready and all resources loaded (critical for WASM)
	await get_tree().process_frame

	# Connect to GameTimer for auto-draw and turn tracking
	if GameTimer:
		GameTimer.timer_reset.connect(_on_timer_reset)
		GameTimer.turn_changed.connect(_on_turn_changed)

	# Connect mulligan button
	if mulligan_button:
		mulligan_button.text = I18n.translate("ui.hand.mull_again")
		mulligan_button.pressed.connect(_on_mulligan_pressed)
		_update_mulligan_button()  # Set initial state

	# Connect hover signals for hand container (for card_hand_entered/exited signals)
	if hand_container:
		hand_container.mouse_entered.connect(_on_hand_container_mouse_entered)
		hand_container.mouse_exited.connect(_on_hand_container_mouse_exited)

	# Apply Alagard font to card count label
	var font = Cache.get_font_for_current_language()
	if font:
		card_count_label.add_theme_font_override("font", font)
		mulligan_button.add_theme_font_override("font", font)
	else:
		push_warning("PlayHand: Could not load Alagard font from Cache")

	# Connect to ComboPopupManager signals for card clearing
	if ComboPopup:
		ComboPopup.combo_accepted_by_player.connect(_on_combo_accepted_by_player)
		ComboPopup.combo_declined_by_player.connect(_on_combo_declined_by_player)

	# Create swap indicator UI (await since it's async)
	await _create_swap_indicator()

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

	# Update card count display
	_update_card_count()

	# Refresh fan layout after all cards are loaded (deferred to ensure container is sized)
	call_deferred("_refresh_card_positions")

# Update card count label
func _update_card_count() -> void:
	if card_count_label:
		card_count_label.text = I18n.translate("ui.hand.card_count") % [hand.size(), MAX_HAND]

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

	# Calculate vertical center offset to center cards in container
	var container_height = card_container.size.y
	var vertical_center_offset = (container_height - card_height - card_wrapper_padding * 2) / 2.0

	for i in range(total_cards):
		var card_wrapper = card_container.get_child(i)
		var offset_from_center = i - center_index

		# Set pivot point to bottom center of card for rotation (accounting for padding)
		card_wrapper.pivot_offset = Vector2(card_width / 2.0 + card_wrapper_padding, card_height + card_wrapper_padding)

		# Set z-index: cards from left to right increase in z-index (rightmost cards on top)
		card_wrapper.z_index = i

		# Reset scale and modulate (undo any hover effects)
		card_wrapper.scale = Vector2(1.0, 1.0)
		card_wrapper.modulate = Color(1.0, 1.0, 1.0, 1.0)

		# Calculate horizontal position (spread cards with dynamic spacing)
		var base_x = container_center_x + (offset_from_center * dynamic_spacing) - (card_width / 2.0)
		card_wrapper.position.x = base_x

		# Rotate card for fanning effect
		card_wrapper.rotation_degrees = offset_from_center * fan_rotation

		# Adjust vertical position to create arc curve (concave up - cards dip toward center)
		var arc_offset = abs(offset_from_center) * arc_height
		card_wrapper.position.y = vertical_center_offset + arc_offset  # Centered + arc offset

# Reorganize hand with smooth animation after card is removed/added
func _reorganize_hand() -> void:
	var total_cards = card_container.get_child_count()
	if total_cards == 0:
		return

	var center_index = (total_cards - 1) / 2.0

	# Calculate container center for positioning
	var container_width = card_container.size.x
	var container_center_x = container_width / 2.0
	var container_height = card_container.size.y
	var vertical_center_offset = (container_height - card_height - card_wrapper_padding * 2) / 2.0

	for i in range(total_cards):
		var card_wrapper = card_container.get_child(i)
		var offset_from_center = i - center_index

		# Set pivot point to bottom center of card for rotation (accounting for padding)
		card_wrapper.pivot_offset = Vector2(card_width / 2.0 + card_wrapper_padding, card_height + card_wrapper_padding)

		# Set z-index: cards from left to right increase in z-index (rightmost cards on top)
		# This ensures no card gets hidden behind others
		card_wrapper.z_index = i

		# Calculate new positions
		var target_x = container_center_x + (offset_from_center * card_spacing) - (card_width / 2.0)
		var target_rotation = offset_from_center * fan_rotation
		var arc_offset = abs(offset_from_center) * arc_height
		var target_y = vertical_center_offset + arc_offset

		# Animate to new position smoothly
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(card_wrapper, "position:x", target_x, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(card_wrapper, "position:y", target_y, 0.4).set_ease(Tween.EASE_OUT)
		tween.tween_property(card_wrapper, "rotation_degrees", target_rotation, 0.4).set_ease(Tween.EASE_OUT)
		tween.tween_property(card_wrapper, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT)
		tween.tween_property(card_wrapper, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.3)

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

	# Ensure card scale is correct (reset to 1.0 in case it was modified)
	card.scale = Vector2.ONE

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

	# Calculate horizontal position (centered in container with fan spread)
	var container_width = card_container.size.x
	var container_center_x = container_width / 2.0

	# Dynamic spacing: reduce spacing when hand is fuller to keep all cards visible
	var dynamic_spacing = card_spacing
	if total_cards > 8:
		# For 9-12 cards, reduce spacing to fit them all
		dynamic_spacing = min(card_spacing, (container_width - 100) / total_cards)

	var base_x = container_center_x + (offset_from_center * dynamic_spacing) - (card_width / 2.0)
	card_wrapper.position.x = base_x

	# Calculate vertical position with arc and vertical centering
	var container_height = card_container.size.y
	var vertical_center_offset = (container_height - card_height - card_wrapper_padding * 2) / 2.0
	var arc_offset = abs(offset_from_center) * arc_height
	card_wrapper.position.y = vertical_center_offset + arc_offset

	# Set z-index: cards from left to right increase in z-index (rightmost cards on top)
	card_wrapper.z_index = index

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
		if card != held_card:
			# Hovering over a different card while holding one - show swap indicator
			_show_swap_indicator(card)
			# Highlight the target card with golden tint
			var tween = create_tween()
			tween.tween_property(card, "modulate", Color(1.2, 1.0, 0.6, 1.0), 0.2)  # Golden highlight
		return

	if card_state != CardState.IDLE:
		return  # Don't hover effect while card is held

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
	# Calculate arc offset based on card index (concave up)
	var card_index = card.get_index()
	var total_cards = hand.size()  # Use actual hand size
	var center_index = (total_cards - 1) / 2.0
	var offset_from_center = card_index - center_index
	var arc_offset = abs(offset_from_center) * arc_height

	# Calculate vertical center offset to match _refresh_card_positions
	var container_height = card_container.size.y
	var vertical_center_offset = (container_height - card_height - card_wrapper_padding * 2) / 2.0
	var original_y = vertical_center_offset + arc_offset

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "position:y", original_y, 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2(1.0, 1.0), 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.2)

# Hand panel hover effects
func _on_hand_container_mouse_entered() -> void:
	card_hand_entered.emit()

func _on_hand_container_mouse_exited() -> void:
	card_hand_exited.emit()

# Create the swap indicator UI from cached packed scene
func _create_swap_indicator() -> void:
	swap_indicator = SWAP_INDICATOR_SCENE.instantiate()

	if not swap_indicator:
		push_error("PlayHand: Failed to instantiate swap indicator scene!")
		return

	print("PlayHand: Created swap_indicator")

	# Set translated text
	swap_indicator.text = I18n.translate("ui.hand.swap")
	print("PlayHand: swap_indicator.text = ", swap_indicator.text)

	# Apply Alagard font
	var font = Cache.get_font_for_current_language()
	if font:
		swap_indicator.add_theme_font_override("font", font)

	# Add to self (PlayHand root) instead of card_container to avoid clipping
	# Set very high z-index to render on top of everything
	swap_indicator.z_index = 1000
	add_child(swap_indicator)
	print("PlayHand: Added swap_indicator as child with z_index=1000")

	# Position above the card container, centered
	# Wait one frame to get proper sizing
	await get_tree().process_frame

	# Validate objects after await
	if not is_instance_valid(swap_indicator) or not is_instance_valid(card_container):
		print("PlayHand: swap_indicator or card_container became invalid after await!")
		return

	# Position relative to card_container's global position
	var container_global_pos = card_container.global_position
	var container_width = card_container.size.x

	# Center horizontally above the card container
	swap_indicator.global_position = Vector2(
		container_global_pos.x + container_width / 2 - swap_indicator.size.x / 2,
		container_global_pos.y - swap_indicator.size.y - 10  # 10px above
	)
	print("PlayHand: Positioned swap_indicator at global ", swap_indicator.global_position, " size=", swap_indicator.size)

# Show swap indicator (fixed position above hand panel)
func _show_swap_indicator(target_card: Control) -> void:
	if not swap_indicator:
		print("PlayHand: swap_indicator is null!")
		return

	swap_indicator_target_card = target_card
	swap_indicator.visible = true
	print("PlayHand: Showing swap indicator at position ", swap_indicator.position, " visible=", swap_indicator.visible)

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
	# Block all input while combo popup is active
	if ComboPopup and ComboPopup.is_popup_active:
		get_viewport().set_input_as_handled()
		return

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
	# If we're already holding a card, swap it
	if card_state == CardState.HELD or card_state == CardState.PREVIEW:
		# Don't pick the same card twice
		if held_card == card:
			return

		# SWAP: Return old card to END of hand, then pick new card
		_return_card_to_end()
		print("State: Swapping cards - old card moved to end")

		# Emit signal that cards were swapped
		card_swapped.emit()

	held_card = card
	held_card_source_index = card.get_index()

	# Get PooledCard from hand array
	if held_card_source_index < hand.size():
		held_card_pooled = hand[held_card_source_index]
	else:
		push_error("PlayHand: Card index %d out of range (hand size: %d)" % [held_card_source_index, hand.size()])
		return

	# Create preview ghost (reparents PooledCard to hex_map)
	_create_preview_ghost()

	# Hide the wrapper (card is now ghost)
	held_card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Reorganize remaining cards in hand
	call_deferred("_reorganize_hand")

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
	_return_card_to_end()
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

		# Set z-index above all entities so ghost is always visible
		held_card_pooled.z_index = Cache.Z_INDEX_GHOST_CARD

func _update_preview_ghost(delta: float) -> void:
	if preview_ghost == null or hex_map == null:
		return

	# Get mouse position in world coordinates
	var mouse_world_pos = hex_map.get_global_mouse_position()

	# Offset the ghost to the right of the cursor so it doesn't cover the tile
	var ghost_offset = Vector2(80, 0)  # 80 pixels to the right of cursor

	# Convert to tile coordinates
	var tile_coords = hex_map.tile_map.local_to_map(mouse_world_pos)

	# No bounds check - infinite world support
	# Valid tile - snap ghost to tile center with offset
	var tile_world_pos = hex_map.tile_map.map_to_local(tile_coords)
	preview_ghost.position = tile_world_pos + ghost_offset
	preview_ghost_target_tile = tile_coords

	# Check if tile is occupied
	var is_tile_occupied = hex_map.card_data.has(tile_coords)

	if not is_tile_occupied:
		# Show hint for placing card on empty tile
		GlobalHint.show_hint(I18n.translate("ui.hand.hint_place_card"))

	# Transition to PREVIEW state if hovering valid tile
	if card_state == CardState.HELD:
		card_state = CardState.PREVIEW

	# Fade in ghost when snapped to valid tile (green tint)
	var target_color = Color(0.8, 1, 0.8, ghost_alpha_snapped)
	preview_ghost.modulate = preview_ghost.modulate.lerp(target_color, ghost_fade_speed * delta)

func _destroy_preview_ghost() -> void:
	# Don't destroy the ghost - it's the actual PooledCard that will be returned to hand or placed
	preview_ghost = null
	preview_ghost_target_tile = Vector2i(-1, -1)
	# Hide hint when card interaction ends
	GlobalHint.hide_hint()

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

	# Set z-index to render above tiles and other entities
	card_sprite.z_index = Cache.Z_INDEX_ENTITY_BASE + tile_coords.y + Cache.Z_INDEX_CARD_OFFSET

	# Note: Wave shader disabled for cards because it would override the card atlas material
	# and lose the card_id instance parameter. Cards keep their atlas material so they
	# display correctly. If wave effect is needed, a combined shader would be required.

	# Register card with hex map (using PooledCard's suit/value)
	var success = hex_map.place_card_on_tile(tile_coords, card_sprite, card_sprite.suit, card_sprite.value)

	if not success:
		# Tile is occupied - return card to hand
		push_warning("PlayHand: Cannot place card - tile is occupied!")
		Toast.show_toast(I18n.translate("ui.hand.tile_occupied"), 2.0)
		_return_card_to_end()
		return

	# Show toast notification for card placement
	var card_name = card_sprite.get_card_name()
	Toast.show_toast(I18n.translate("ui.hand.card_placed", [card_name]), 2.0)

	# Track last placed card position for combo detection
	last_placed_card_pos = tile_coords

	# Track card placement (for mulligan prevention)
	cards_placed_this_game += 1
	_update_mulligan_button()  # Disable mulligan after first card

	# Check for card combos after placement
	_check_for_combos()

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

func _return_card_to_end() -> void:
	if held_card == null or held_card_pooled == null:
		return

	# Reparent the PooledCard back to the hand wrapper (from hex_map)
	if held_card_pooled.get_parent():
		held_card_pooled.get_parent().remove_child(held_card_pooled)
	held_card.add_child(held_card_pooled)

	# Reset PooledCard transform to its proper position within the wrapper
	held_card_pooled.position = Vector2(card_width / 2.0 + card_wrapper_padding, card_height / 2.0 + card_wrapper_padding)
	held_card_pooled.rotation = 0
	held_card_pooled.scale = Vector2.ONE
	held_card_pooled.modulate = Color.WHITE

	# Re-enable mouse input on wrapper
	held_card.mouse_filter = Control.MOUSE_FILTER_PASS

	# Update hand array: remove card from old position and add to end
	if held_card_source_index >= 0 and held_card_source_index < hand.size():
		hand.remove_at(held_card_source_index)
	hand.append(held_card_pooled)

	# Move wrapper to END of container (rightmost position)
	card_container.move_child(held_card, -1)

	# Clean up
	_destroy_preview_ghost()
	held_card = null
	held_card_pooled = null

	# Reorganize hand to fan properly with card at end
	call_deferred("_reorganize_hand")

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
	var hand_rect = hand_container.get_global_rect()
	return hand_rect.has_point(mouse_pos)

# Auto-draw card when timer resets (every 60 seconds)
func _on_timer_reset() -> void:
	# Check if hand is at max capacity
	if hand.size() >= MAX_HAND:
		# Send toast: Hand is full
		Toast.show_toast(I18n.translate("ui.hand.full"), 3.0)
		return

	# Hand has space - draw a card
	var card = CardDeck.draw_card(deck_id)
	if card:
		# Add the card to hand
		hand.append(card)

		# Create wrapper for the new card
		var card_wrapper = Control.new()
		card_wrapper.name = "Card_%d" % (hand.size() - 1)
		card_wrapper.custom_minimum_size = Vector2(card_width + card_wrapper_padding * 2, card_height + card_wrapper_padding * 2)
		card_wrapper.mouse_filter = Control.MOUSE_FILTER_PASS

		# Reparent PooledCard to wrapper
		if card.get_parent():
			card.get_parent().remove_child(card)
		card_wrapper.add_child(card)

		# Position sprite within wrapper (centered, accounting for padding)
		card.scale = Vector2.ONE
		card.position = Vector2(card_width / 2.0 + card_wrapper_padding, card_height / 2.0 + card_wrapper_padding)

		# Connect hover and input signals
		card_wrapper.mouse_entered.connect(_on_card_mouse_entered.bind(card_wrapper))
		card_wrapper.mouse_exited.connect(_on_card_mouse_exited.bind(card_wrapper))
		card_wrapper.gui_input.connect(_on_card_gui_input.bind(card_wrapper))

		# Add to container at END
		card_container.add_child(card_wrapper)

		_update_card_count()

		# Refresh fan layout to show all cards properly positioned
		_refresh_card_positions()

		# Send toast: Drew a card
		Toast.show_toast(I18n.translate("ui.hand.drew", [card.get_card_name()]), 2.5)
	else:
		# No cards left in deck
		Toast.show_toast(I18n.translate("ui.hand.deck_empty"), 2.5)

# ===================================================================
# COMBO DETECTION
# ===================================================================

## Check for card combos on the hex grid (ASYNC - runs on worker thread)
## Only checks cards near the last placed card for performance and relevance
func _check_for_combos() -> void:
	if not hex_map or not CardComboBridge:
		return

	# If no last placed card position, can't filter
	if last_placed_card_pos == Vector2i(-1, -1):
		print("No last placed card position - skipping combo check")
		return

	# Collect placed cards ONLY within COMBO_CHECK_RADIUS of last placed card
	var placed_cards: Array[Dictionary] = []
	var filtered_out_count: int = 0

	# Get all card data from hex_map
	for tile_coords in hex_map.card_data.keys():
		# Calculate hex distance from last placed card
		var distance = _hex_distance(last_placed_card_pos, tile_coords)

		# Skip cards too far away (not relevant to current combo)
		if distance > COMBO_CHECK_RADIUS:
			filtered_out_count += 1
			continue

		var card_info = hex_map.card_data[tile_coords]
		var card_sprite = card_info.get("sprite")

		# Create card dictionary for combo detection
		var card_dict: Dictionary = CardComboBridge.create_card_dict(
			card_info.get("ulid"),
			card_info.get("suit", 0),
			card_info.get("value", 0),
			card_info.get("card_id", 0),
			tile_coords.x,
			tile_coords.y,
			card_sprite.is_custom if card_sprite is PooledCard else false
		)

		placed_cards.append(card_dict)

	# Debug: Print card positions and values
	print("=== Checking combos for %d cards (filtered out %d cards beyond radius %d) ===" % [placed_cards.size(), filtered_out_count, COMBO_CHECK_RADIUS])
	print("  Last placed card at: (%d, %d)" % [last_placed_card_pos.x, last_placed_card_pos.y])
	for card in placed_cards:
		var value_name = _get_value_name(card.get("value", 0))
		var suit_name = _get_suit_name(card.get("suit", 0))
		var dist = _hex_distance(last_placed_card_pos, Vector2i(card.get("x"), card.get("y")))
		print("  Card at (%d, %d): %s of %s (distance: %d)" % [card.get("x"), card.get("y"), value_name, suit_name, dist])

	# Need at least 5 cards for a combo
	if placed_cards.size() < 5:
		print("Not enough cards for combo (need 5, have %d in radius)" % placed_cards.size())
		return

	# Request combo detection (async - result via callback)
	CardComboBridge.request_combo_detection(placed_cards, _on_combo_result)

## Callback when combo detection completes
func _on_combo_result(result: Dictionary) -> void:
	# Debug: Print result
	print("=== Combo Detection Result ===")
	print("  Result keys: %s" % [result.keys()])
	if result.has("hand_name"):
		print("  Hand: %s (rank %d)" % [result["hand_name"], result.get("hand_rank", -1)])
	if result.has("card_indices"):
		print("  Card indices in combo: %s" % [result["card_indices"]])

	# Check if a combo was found
	if not result.has("hand_name") or not result.has("card_indices"):
		print("  No valid combo found (missing hand_name or card_indices)")
		return

	# Get hand rank (0 = High Card, which we don't want to show)
	var hand_rank = result.get("hand_rank", 0)
	if hand_rank == 0:
		# High Card - not a real combo, don't show popup
		print("  High Card detected - not showing popup")
		return

	print("Combo found: %s (rank %d)" % [result["hand_name"], hand_rank])

	# Highlight cards in the combo with outline shader
	_highlight_combo_cards(result)

	# Show combo popup (waits for player to accept/decline)
	if ComboPopup:
		ComboPopup.show_combo(result)
		# Don't auto-apply resources - wait for player to accept
		# Signals are connected in _initialize()

	# Play a sound effect (if available)
	# TODO: Add combo sound effect

## Helper: Calculate hex distance between two tile coordinates
## Uses cube coordinate formula: (|dx| + |dy| + |dz|) / 2
func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dx = abs(a.x - b.x)
	var dy = abs(a.y - b.y)
	var dz = abs(dx + dy)
	return (dx + dy + dz) / 2

## Helper: Get card value name for debugging
func _get_value_name(value: int) -> String:
	match value:
		1: return "Ace"
		11: return "Jack"
		12: return "Queen"
		13: return "King"
		_: return str(value)

## Helper: Get suit name for debugging
func _get_suit_name(suit: int) -> String:
	match suit:
		0: return "Clubs"
		1: return "Diamonds"
		2: return "Hearts"
		3: return "Spades"
		_: return "Unknown"

## Highlight combo cards with outline shader
func _highlight_combo_cards(combo_data: Dictionary) -> void:
	var positions = combo_data.get("positions", [])
	var combo_shader = load("res://view/hand/combo/combo.gdshader")

	for pos in positions:
		# pos is a Dictionary with "x" and "y" keys from Rust
		var tile_coords = Vector2i(pos["x"], pos["y"])
		var card_info = hex_map.card_data.get(tile_coords)

		if card_info:
			var card_sprite = card_info.get("sprite")

			if card_sprite is PooledCard:
				# Apply combo highlight shader
				var shader_material = ShaderMaterial.new()
				shader_material.shader = combo_shader
				shader_material.set_shader_parameter("outline_color", Color(0.2, 1.0, 0.3, 1.0))  # Bright green
				shader_material.set_shader_parameter("outline_width", 3.0)
				shader_material.set_shader_parameter("pulse_speed", 3.0)
				shader_material.set_shader_parameter("pulse_intensity", 0.4)

				card_sprite.material = shader_material
				print("  Highlighted card at %s (is_dynamic=%s)" % [tile_coords, card_sprite.is_dynamic])

## Called when player accepts the combo
func _on_combo_accepted_by_player(combo_data: Dictionary) -> void:
	print("PlayHand: Player accepted combo!")
	_clear_combo_cards(combo_data)

## Called when player declines the combo
func _on_combo_declined_by_player(combo_data: Dictionary) -> void:
	print("PlayHand: Player declined combo")
	_remove_combo_highlights(combo_data)

## Remove highlight shader from combo cards
func _remove_combo_highlights(combo_data: Dictionary) -> void:
	var positions = combo_data.get("positions", [])

	for pos in positions:
		# pos is a Dictionary with "x" and "y" keys from Rust
		var tile_coords = Vector2i(pos["x"], pos["y"])
		var card_info = hex_map.card_data.get(tile_coords)

		if card_info:
			var card_sprite = card_info.get("sprite")

			if card_sprite is PooledCard:
				# Remove shader
				card_sprite.material = null
				print("  Removed highlight from card at %s" % [tile_coords])

## Clear combo cards from board (called when player accepts combo)
## Removes ALL cards that were used in the combo (regular cards + wildcards)
## Cards NOT in the combo remain on the board
func _clear_combo_cards(combo_data: Dictionary) -> void:
	var positions = combo_data.get("positions", [])

	print("PlayHand: Clearing %d combo cards from board" % positions.size())

	for pos in positions:
		# pos is a Dictionary with "x" and "y" keys from Rust
		var tile_coords = Vector2i(pos["x"], pos["y"])
		var card_info = hex_map.card_data.get(tile_coords)

		if card_info:
			var card_sprite = card_info.get("sprite")

			# Remove from hex_map
			hex_map.card_data.erase(tile_coords)

			# Remove from Rust CardRegistry
			var card_registry = get_node("/root/CardRegistryBridge")
			if card_registry:
				card_registry.remove_card_at(tile_coords.x, tile_coords.y)

				# Return card to pool (not queue_free - reuse for performance!)
				if card_sprite and is_instance_valid(card_sprite):
					if card_sprite is PooledCard and Cluster:
						Cluster.release("playing_card", card_sprite)
					else:
						# Fallback: free if not a pooled card
						card_sprite.queue_free()

				print("  Cleared card at %s" % [tile_coords])

# ===================================================================
# MULLIGAN SYSTEM
# ===================================================================

## Handle mulligan button press
func _on_mulligan_pressed() -> void:
	# Check if mulligan is allowed
	if not _can_mulligan():
		return

	# Pause the game timer during mulligan
	if GameTimer:
		GameTimer.pause()

	# Deduct gold via Rust ledger (source of truth) - Issue #3 fix
	# Use float explicitly to match Rust's f32 expectation
	var cost = {ResourceLedger.R.GOLD: float(MULLIGAN_COST)}

	var gold_before = ResourceLedger.get_current(ResourceLedger.R.GOLD)
	print("PlayHand: Gold before mulligan: %.1f" % gold_before)

	if not ResourceLedger.can_spend(cost):
		Toast.show_toast("Not enough gold! Need %d gold to mulligan." % MULLIGAN_COST, 3.0)
		if GameTimer:
			GameTimer.resume()
		return

	if not ResourceLedger.spend(cost):
		push_error("PlayHand: Failed to spend gold for mulligan (should have been caught by can_spend)!")
		if GameTimer:
			GameTimer.resume()
		return

	var gold_after = ResourceLedger.get_current(ResourceLedger.R.GOLD)
	print("PlayHand: Gold after mulligan: %.1f (spent %.1f)" % [gold_after, gold_before - gold_after])

	# Separate bonus cards (custom cards) from deck cards
	var bonus_cards: Array[PooledCard] = []
	var deck_cards: Array[PooledCard] = []

	for card in hand:
		if card and is_instance_valid(card):
			if card.is_custom:
				bonus_cards.append(card)
			else:
				deck_cards.append(card)

	# Only release deck cards back to pool
	for card in deck_cards:
		Cluster.release("playing_card", card)

	# Clear hand and display
	hand.clear()
	clear_hand_display()

	# Draw 7 new cards from deck
	var card_deck = get_node("/root/CardDeck")
	for i in range(7):
		var card = card_deck.draw_card(deck_id)
		if card == null:
			push_warning("PlayHand: Failed to draw card %d during mulligan" % i)
			continue

		hand.append(card)
		display_card(card, hand.size() - 1)

	# Re-add bonus cards to hand
	for bonus_card in bonus_cards:
		hand.append(bonus_card)
		display_card(bonus_card, hand.size() - 1)

	# Refresh all card positions to properly fan the entire hand
	_refresh_card_positions()

	# Update button state
	_update_mulligan_button()

	# Resume timer after a brief moment (allows player to see new hand)
	await get_tree().create_timer(0.5).timeout
	if GameTimer:
		GameTimer.resume()

	Toast.show_toast("Mulliganed! Drew new hand. (-%d Gold)" % MULLIGAN_COST, 3.0)
	print("PlayHand: Player mulliganed hand, cost %d gold" % MULLIGAN_COST)

## Check if mulligan is allowed
func _can_mulligan() -> bool:
	# Only on turn 0
	if GameTimer and GameTimer.get_current_turn() > 0:
		return false

	# Only if no cards have been placed
	if cards_placed_this_game > 0:
		return false

	return true

## Update mulligan button enabled/disabled state
func _update_mulligan_button() -> void:
	if not mulligan_button:
		return

	var can_mull = _can_mulligan()

	# HIDE button after turn 0 or after placing any cards
	if not can_mull:
		if mulligan_button.visible:  # Only hide if currently visible
			var current_turn = GameTimer.get_current_turn() if GameTimer else -1
			print("PlayHand: Hiding mulligan button - Turn: %d, Cards placed: %d" % [current_turn, cards_placed_this_game])
			mulligan_button.visible = false
		return

	# Check if player has enough gold
	var cost = {ResourceLedger.R.GOLD: MULLIGAN_COST}
	var has_gold = ResourceLedger.can_spend(cost)

	# Show button (only if currently hidden)
	if not mulligan_button.visible:
		mulligan_button.visible = true

	# Only update disabled state if it changed (prevents unnecessary transitions)
	var should_disable = not has_gold
	if mulligan_button.disabled != should_disable:
		mulligan_button.disabled = should_disable

	# Update tooltip
	if not has_gold:
		mulligan_button.tooltip_text = "Not enough gold (need %d)" % MULLIGAN_COST
	else:
		mulligan_button.tooltip_text = "Redraw your entire hand for %d gold" % MULLIGAN_COST

## Handle turn changes (disable mulligan after turn 0)
func _on_turn_changed(turn: int) -> void:
	_update_mulligan_button()
