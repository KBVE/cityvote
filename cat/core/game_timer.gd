extends Node

## GameTimer (Singleton)
## Manages a global 60-second repeating timer for game rounds/cycles

# Signals
signal timer_tick(time_left: int)  # Emitted every second with remaining time
signal timer_reset()  # Emitted when timer resets to 60
signal turn_changed(turn: int)  # Emitted when turn increments

# Timer constants
const TIMER_DURATION: int = 60  # 60 seconds

# Current time remaining
var time_left: int = TIMER_DURATION

# Turn counter (increments every 60 seconds)
var current_turn: int = 0

# Internal timer
var timer: Timer

func _ready() -> void:
	# Create and configure timer
	timer = Timer.new()
	timer.wait_time = 1.0  # Tick every second
	timer.one_shot = false
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(_on_timer_timeout)

	print("GameTimer: Ready - Starting 60s repeating timer")

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
