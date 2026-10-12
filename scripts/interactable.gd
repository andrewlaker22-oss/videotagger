class_name Interactable
extends StaticBody3D
## A raycast-detectable hotspot the player can trigger with E / click.
##
## Created in code by apartment_builder.gd. The story meaning of an
## interactable is NOT stored here — see StoryData.get_trigger_beats(), which
## maps interact_id -> beat id. That keeps story authoring in one place.

@export var interact_id: String = ""
@export var prompt: String = "Interact"
@export var one_shot: bool = true

var enabled: bool = true


func _ready() -> void:
	add_to_group("interactable")


func get_prompt() -> String:
	return prompt


func disable() -> void:
	enabled = false
