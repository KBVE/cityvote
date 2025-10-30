extends Node

## GameTimer (Singleton)
## Manages a global 60-second repeating timer for game rounds/cycles

# Signals
signal timer_tick(time_left: int)  # Emitted every second with remaining time
signal timer_reset()  # Emitted when timer resets to 60
signal turn_changed(turn: int)  # Emitted when turn increments
signal consume_food()  # Emitted once per turn (every 60 seconds) to consume food

# Timer constants
const TIMER_DURATION: int = 60  # 60 seconds

# Current time remaining
var time_left: int = TIMER_DURATION

# Turn counter (increments every 60 seconds)
var current_turn: int = 0

# Pause state
var is_paused: bool = true  # Start paused until player is ready

# Internal timer
var timer: Timer

func _ready() -> void:
	# Create and configure timer
	timer = Timer.new()
	if not timer:
		push_error("GameTimer: Failed to create timer!")
		return

	timer.wait_time = 1.0  # Tick every second
	timer.one_shot = false
	timer.autostart = false  # Don't auto-start - wait for player to be ready
	add_child(timer)
	timer.timeout.connect(_on_timer_timeout)

	print("GameTimer: Timer created but paused. Waiting for game to start...")

func _on_timer_timeout() -> void:
	time_left -= 1

	# Emit tick signal
	timer_tick.emit(time_left)

	# Check if timer expired
	if time_left <= 0:
		_reset_timer()

func _reset_timer() -> void:
	time_left = TIMER_DURATION
	current_turn += 1
	timer_reset.emit()
	turn_changed.emit(current_turn)

	# Emit food consumption signal (once per turn)
	consume_food.emit()

## Get current time remaining
func get_time_left() -> int:
	return time_left

## Get formatted time string (MM:SS)
func get_time_string() -> String:
	var minutes = time_left / 60
	var seconds = time_left % 60
	return "%02d:%02d" % [minutes, seconds]

## Get simple seconds string
func get_seconds_string() -> String:
	return "%ds" % time_left

## Get current turn number
func get_current_turn() -> int:
	return current_turn

## Manually reset timer (for testing/debugging)
func reset() -> void:
	_reset_timer()

## Pause the timer
func pause() -> void:
	if timer and timer.is_stopped() == false:
		timer.stop()
		is_paused = true
		print("GameTimer: Timer paused at %ds" % time_left)

## Resume the timer
func resume() -> void:
	if timer and is_paused:
		timer.start()
		is_paused = false
		print("GameTimer: Timer resumed at %ds" % time_left)

## Start the timer (used when game begins)
func start_timer() -> void:
	if timer:
		timer.start()
		is_paused = false
		print("GameTimer: Timer started!")

## Check if timer is paused
func is_timer_paused() -> bool:
	return is_paused
