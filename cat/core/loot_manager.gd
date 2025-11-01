extends Node
## LootManager - Minimal wrapper around Rust loot system
## Rust handles: combat tracking, drop generation, toast notifications, resource application
## This only polls for Draw/XP rewards (not yet implemented in Rust)

# Rust bridge (global singleton)
var loot_bridge: LootBridge = null

func _ready() -> void:
	# Create global Rust bridge for loot system
	loot_bridge = LootBridge.new()
	add_child(loot_bridge)
	loot_bridge.name = "LootBridge"

	# Connect to CombatManager signals to forward events to Rust
	if CombatManager:
		CombatManager.combat_started.connect(_on_combat_started)

	# Connect to StatsManager for entity deaths
	if StatsManager:
		StatsManager.entity_died.connect(_on_entity_died)

	print("LootManager: Rust loot bridge ready")

# Forward combat start event to Rust
func _on_combat_started(attacker_ulid: PackedByteArray, defender_ulid: PackedByteArray) -> void:
	if loot_bridge:
		loot_bridge.on_combat_started(attacker_ulid, defender_ulid)

# Forward entity death event to Rust
func _on_entity_died(entity_ulid: PackedByteArray) -> void:
	if loot_bridge:
		# Rust will look up entity type from ULID storage
		loot_bridge.on_entity_died(entity_ulid)

func _process(_delta: float) -> void:
	# Poll for loot events from Rust (only for Draw/XP which aren't handled by Rust yet)
	if not loot_bridge:
		return

	while true:
		var event = loot_bridge.pop_loot_event()
		if event == null:
			break

		var rewards: Array = event.get("rewards", [])

		# Apply Draw and XP rewards (Gold/Food/Faith/Labor handled directly by Rust)
		for reward_dict in rewards:
			var reward_type: String = reward_dict.get("type", "")
			var amount: int = reward_dict.get("amount", 0)

			match reward_type:
				"draw":
					# TODO: Add card draws when draw system exists
					print("[Loot] Player gains %d card draw(s)" % amount)

				"experience":
					# TODO: Apply XP when XP system exists
					print("[Loot] Player gains %d experience" % amount)
