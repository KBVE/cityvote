extends Ship

# Viking ship - extends the Ship base class

func _ready():
	# Preload all 16 directional sprites (counter-clockwise from north)
	ship_sprites = [
		preload("res://nodes/ships/viking/ship1.png"),   # 0 - North
		preload("res://nodes/ships/viking/ship2.png"),   # 1 - NNW
		preload("res://nodes/ships/viking/ship3.png"),   # 2 - NW
		preload("res://nodes/ships/viking/ship4.png"),   # 3 - WNW (if exists)
		preload("res://nodes/ships/viking/ship5.png"),   # 4 - West
		preload("res://nodes/ships/viking/ship6.png"),   # 5 - WSW
		preload("res://nodes/ships/viking/ship7.png"),   # 6 - SW
		preload("res://nodes/ships/viking/ship8.png"),   # 7 - SSW
		preload("res://nodes/ships/viking/ship9.png"),   # 8 - South
		preload("res://nodes/ships/viking/ship10.png"),  # 9 - SSE
		preload("res://nodes/ships/viking/ship11.png"),  # 10 - SE
		preload("res://nodes/ships/viking/ship12.png"),  # 11 - ESE
		preload("res://nodes/ships/viking/ship13.png"),  # 12 - East
		preload("res://nodes/ships/viking/ship14.png"),  # 13 - ENE
		preload("res://nodes/ships/viking/ship15.png"),  # 14 - NE
		preload("res://nodes/ships/viking/ship16.png")   # 15 - NNE
	]

	super._ready()

func _process(delta):
	# Example: rotate to face mouse (for testing)
	# Uncomment to test rotation:
	# var mouse_pos = get_global_mouse_position()
	# var direction_vec = mouse_pos - global_position
	# set_direction(vector_to_direction(direction_vec))
	pass
