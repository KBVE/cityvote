extends Node
class_name DialogueData

## Dialogue Data Structure
## Helper class for creating dialogue sequences for the NovelPanel
## Provides static methods to build dialogue dictionaries

## Create a simple dialogue entry
## All string parameters support both plain text and i18n keys
## The system will automatically translate i18n keys when displayed
static func create_dialogue(
	speaker: String,         # Plain text or i18n key (e.g., "npc.viking.name")
	text: String,           # Plain text or i18n key (e.g., "npc.viking.greeting")
	title: String = "Dialogue",  # Plain text or i18n key
	avatar: Texture2D = null,
	background: Texture2D = null
) -> Dictionary:
	return {
		"title": title,
		"speaker": speaker,
		"dialogue": text,
		"avatar": avatar,
		"background": background
	}

## Create a dialogue with player choices
## All string parameters support both plain text and i18n keys
static func create_choice_dialogue(
	speaker: String,         # Plain text or i18n key
	text: String,           # Plain text or i18n key
	choices: Array[String], # Array of plain text or i18n keys
	choice_callbacks: Array[Callable] = [],
	title: String = "Dialogue",  # Plain text or i18n key
	avatar: Texture2D = null,
	background: Texture2D = null
) -> Dictionary:
	var dialogue_dict = {
		"title": title,
		"speaker": speaker,
		"dialogue": text,
		"choices": choices,
		"avatar": avatar,
		"background": background
	}

	if choice_callbacks.size() > 0:
		dialogue_dict["choice_callbacks"] = choice_callbacks

	return dialogue_dict

## Example dialogue sequences
class Examples:
	## Viking encounter example
	static func viking_encounter() -> Array[Dictionary]:
		return [
			DialogueData.create_dialogue(
				"Viking Captain",
				"Ahoy there! You've entered our waters. State your business, or face the consequences!",
				"Viking Encounter"
			),
			DialogueData.create_choice_dialogue(
				"Viking Captain",
				"So, what will it be? Will you join us, pay tribute, or fight?",
				["Join your crew", "Pay tribute (50 Gold)", "Fight!", "Flee"],
				[],
				"Viking Encounter"
			)
		]

	## Jezza encounter example
	static func jezza_greeting() -> Array[Dictionary]:
		return [
			DialogueData.create_dialogue(
				"Jezza the Wanderer",
				"Greetings, traveler! I am Jezza, a wanderer of these lands. I've seen many things in my journeys.",
				"Jezza's Tales"
			),
			DialogueData.create_dialogue(
				"Jezza the Wanderer",
				"Would you like to hear a tale of adventure? Or perhaps you seek knowledge of these lands?",
				"Jezza's Tales"
			),
			DialogueData.create_choice_dialogue(
				"Jezza the Wanderer",
				"What interests you most?",
				["Tell me a tale", "Share your knowledge", "Offer a trade", "Farewell"],
				[],
				"Jezza's Tales"
			)
		]

	## Tutorial dialogue example
	static func tutorial_welcome() -> Array[Dictionary]:
		return [
			DialogueData.create_dialogue(
				"Guide",
				"Welcome to the world of AFK! This is a strategy game where you'll build your civilization and conquer the lands.",
				"Tutorial"
			),
			DialogueData.create_dialogue(
				"Guide",
				"You can play cards from your hand to place entities on the map. Combine cards to form poker hands for powerful combos!",
				"Tutorial"
			),
			DialogueData.create_choice_dialogue(
				"Guide",
				"Ready to begin your adventure?",
				["Yes, let's go!", "Tell me more", "Maybe later"],
				[],
				"Tutorial"
			)
		]

	## Quest dialogue example
	static func quest_offer() -> Array[Dictionary]:
		return [
			DialogueData.create_dialogue(
				"Village Elder",
				"Brave adventurer, our village is in dire need of help. Bandits have been raiding our supplies!",
				"Quest: Bandit Trouble"
			),
			DialogueData.create_dialogue(
				"Village Elder",
				"If you could defeat their leader and retrieve our stolen goods, we would be eternally grateful.",
				"Quest: Bandit Trouble"
			),
			DialogueData.create_choice_dialogue(
				"Village Elder",
				"Will you accept this quest?",
				["Accept Quest", "Ask for Reward", "Decline"],
				[],
				"Quest: Bandit Trouble"
			)
		]

	## Simple test dialogue
	static func test_dialogue() -> Array[Dictionary]:
		return [
			DialogueData.create_dialogue(
				"Test Speaker",
				"This is a test dialogue with typewriter effect. Notice how the text appears character by character!",
				"Test Panel"
			),
			DialogueData.create_choice_dialogue(
				"Test Speaker",
				"Here's a choice test. Pick your favorite option!",
				["Option A - Attack", "Option B - Defend", "Option C - Negotiate"],
				[],
				"Test Panel"
			)
		]
