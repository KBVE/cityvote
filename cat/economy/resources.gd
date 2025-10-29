class_name Resources
## Resource Types
## Defines all resource types in the game economy

enum Resource {
	GOLD = 0,
	FOOD = 1,
	LABOR = 2,
	FAITH = 3,
}

const NAMES := {
	Resource.GOLD: "Gold",
	Resource.FOOD: "Food",
	Resource.LABOR: "Labor",
	Resource.FAITH: "Faith",
}

const ICONS := {
	# TODO: Add icon paths when assets are ready
	# Resource.GOLD: preload("res://ui/icons/gold.png"),
	# Resource.FOOD: preload("res://ui/icons/food.png"),
}

## Get resource name from enum value
static func get_name(resource_type: int) -> String:
	return NAMES.get(resource_type, "Unknown")

## Get resource icon from enum value
static func get_icon(resource_type: int) -> Texture2D:
	return ICONS.get(resource_type, null)
