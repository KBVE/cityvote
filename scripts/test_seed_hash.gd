extends SceneTree

## Test script for seed hash function
## Tests conversion of strings to i32-safe seed values
##
## Usage: godot --headless --script res://scripts/test_seed_hash.gd

func _init():
	print("=== Seed Hash Function Test ===\n")

	# Test various string inputs
	var test_strings = ["home", "test", "world", "adventure", "12345", "", "MyWorld123", "こんにちは"]

	print("Testing string-to-seed conversion:")
	print("%-20s | %-15s | %s" % ["Input", "Seed", "Valid i32"])
	print("------------------------------------------------------------")

	for text in test_strings:
		var seed = _string_to_seed(text)
		var is_valid = (seed >= -2147483648 and seed <= 2147483647)
		print("%-20s | %-15d | %s" % [text, seed, "✓" if is_valid else "✗"])

	# Test determinism (same input = same output)
	print("\nTesting determinism (5 runs of 'home'):")
	for i in range(5):
		var seed = _string_to_seed("home")
		print("  Run %d: %d" % [i + 1, seed])

	# Test random seed generation with i32 bounds
	print("\nTesting random seed generation (5 samples):")
	for i in range(5):
		var random_seed = randi() % 2147483647
		var is_valid = (random_seed >= 0 and random_seed <= 2147483647)
		print("  Random %d: %d (valid: %s)" % [i + 1, random_seed, "✓" if is_valid else "✗"])

	print("\n=== All tests complete ===")
	quit()

## Convert string to deterministic i32 seed (matches language_selector.gd implementation)
func _string_to_seed(text: String) -> int:
	# Simple hash function that generates deterministic i32 value from string
	var hash: int = 0
	for i in range(text.length()):
		var char_code = text.unicode_at(i)
		# Mix bits using prime multiplier and XOR
		hash = ((hash * 31) + char_code) & 0x7FFFFFFF  # Keep within positive i32 range

	# Allow negative seeds too, so map to full i32 range
	if hash > 1073741824:  # If in upper half of positive range
		hash = hash - 2147483648  # Map to negative range

	return hash
