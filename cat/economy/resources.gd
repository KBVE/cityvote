class_name Resources
## Resource Types
## Defines all resource types in the game economy

enum ResourceType {
	GOLD = 0,
	FOOD = 1,
	LABOR = 2,
	FAITH = 3,
}

const NAMES := {
	ResourceType.GOLD: "Gold",
	ResourceType.FOOD: "Food",
	ResourceType.LABOR: "Labor",
	ResourceType.FAITH: "Faith",
}

const COLORS := {
	ResourceType.GOLD: Color(0.85, 0.7, 0.35),     # Gold/Yellow
	ResourceType.FOOD: Color(0.9, 0.3, 0.3),       # Red
	ResourceType.LABOR: Color(0.55, 0.45, 0.35),   # Brown/Tan (matches UI)
	ResourceType.FAITH: Color(0.7, 0.5, 0.9),      # Purple
}

const ICONS := {
	# TODO: Add icon paths when assets are ready
	# ResourceType.GOLD: preload("res://ui/icons/gold.png"),
	# ResourceType.FOOD: preload("res://ui/icons/food.png"),
}

## Get resource name from enum value
static func get_name(resource_type: int) -> String:
	return NAMES.get(resource_type, "Unknown")

## Get resource color from enum value
static func get_color(resource_type: int) -> Color:
	return COLORS.get(resource_type, Color.WHITE)

## Get resource icon from enum value
static func get_icon(resource_type: int) -> Texture2D:
	return ICONS.get(resource_type, null)
