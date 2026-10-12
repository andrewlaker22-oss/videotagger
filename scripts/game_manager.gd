class_name GameManager
extends Node3D
## Runs the game: a small state machine on top of data-driven story beats.
##
## States: EXPLORE -> DIALOGUE <-> CHOICE -> ENDING.
##   EXPLORE:  free first-person movement; E / click on an Interactable starts
##             the beat mapped in StoryData.get_trigger_beats().
##   DIALOGUE: beat lines shown one at a time; E / click advances.
##   CHOICE:   timed choice UI; number keys or mouse; timeout picks default.
##   ENDING:   ending beat lines play, then the ending screen. R restarts.
##
## The manager owns the flag table (set by choices, read by conditional lines
## via "if" / "if_not") and applies beat "effects" (door, blackout, sfx).

enum State { EXPLORE, DIALOGUE, CHOICE, ENDING }

var state: int = State.EXPLORE
var flags: Dictionary = {}

var _beat: Dictionary = {}
var _line_index: int = 0

@onready var player: PlayerController = $Player
@onready var ui: DialogueUI = $DialogueUI
@onready var apartment: ApartmentBuilder = $Apartment
@onready var audio: AudioManager = $AudioManager
@onready var world_env: WorldEnvironment = $WorldEnvironment


func _ready() -> void:
	player.primary_action.connect(_on_primary_action)
	player.choice_hotkey.connect(_on_choice_hotkey)
	player.focus_changed.connect(_on_focus_changed)
	ui.choice_selected.connect(_on_choice_selected)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ui.fade_from_black()
	await get_tree().create_timer(1.4).timeout
	start_beat(StoryData.get_start_beat_id())


func _unhandled_input(event: InputEvent) -> void:
	if state == State.ENDING and event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.physical_keycode == KEY_R:
			get_tree().reload_current_scene()


# ------------------------------------------------------------------
# Beat flow
# ------------------------------------------------------------------

func start_beat(beat_id: String) -> void:
	var beats := StoryData.get_beats()
	if not beats.has(beat_id):
		push_error("GameManager: unknown beat id '%s'." % beat_id)
		return
	_beat = beats[beat_id]
	for effect in _beat.get("effects", []):
		_apply_effect(String(effect))
	if _beat.has("objective"):
		ui.set_objective(String(_beat["objective"]))
	state = State.DIALOGUE
	player.control_locked = true
	player.allow_capture = true
	ui.hide_prompt()
	ui.set_letterbox(true)
	_line_index = 0
	_show_line()


func _line_visible(line: Dictionary) -> bool:
	if line.has("if") and not bool(flags.get(String(line["if"]), false)):
		return false
	if line.has("if_not") and bool(flags.get(String(line["if_not"]), false)):
		return false
	return true


func _show_line() -> void:
	var lines: Array = _beat.get("lines", [])
	while _line_index < lines.size() and not _line_visible(lines[_line_index]):
		_line_index += 1
	if _line_index >= lines.size():
		_after_lines()
		return
	var line: Dictionary = lines[_line_index]
	if line.has("sfx"):
		audio.play_sfx(String(line["sfx"]))
	ui.show_dialogue(String(line.get("who", "")), String(line.get("text", "")))


func _advance_line() -> void:
	_line_index += 1
	_show_line()


func _after_lines() -> void:
	var choices: Array = _beat.get("choices", [])
	if not choices.is_empty():
		_start_choice(choices)
		return
	if _beat.has("ending"):
		_play_ending(String(_beat["ending"]))
		return
	var next_id := String(_beat.get("next", ""))
	if next_id != "":
		start_beat(next_id)
		return
	_resume_explore()


func _start_choice(choices: Array) -> void:
	state = State.CHOICE
	player.allow_capture = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_choices(choices, float(_beat.get("timer", 5.0)))


func _on_choice_selected(choice: Dictionary) -> void:
	if state != State.CHOICE:
		return
	var sets: Dictionary = choice.get("set", {})
	for key in sets:
		flags[key] = sets[key]
	var toast := String(choice.get("toast", ""))
	if toast != "":
		ui.show_toast(toast)
	audio.play_sfx("ui_select")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	start_beat(String(choice["next"]))


func _play_ending(ending_id: String) -> void:
	var endings := StoryData.get_endings()
	if not endings.has(ending_id):
		push_error("GameManager: unknown ending id '%s'." % ending_id)
		return
	state = State.ENDING
	player.allow_capture = false
	ui.set_objective("")
	audio.play_sfx("sting")
	var e: Dictionary = endings[ending_id]
	ui.show_ending("ENDING: " + String(e["title"]), String(e["subtitle"]))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume_explore() -> void:
	state = State.EXPLORE
	player.control_locked = false
	player.allow_capture = true
	ui.hide_dialogue()
	ui.set_letterbox(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------
# Input routing (raw signals from the Player)
# ------------------------------------------------------------------

func _on_primary_action() -> void:
	match state:
		State.EXPLORE:
			_try_interact()
		State.DIALOGUE:
			_advance_line()
		_:
			pass


func _on_choice_hotkey(index: int) -> void:
	if state == State.CHOICE:
		ui.select_index(index)


func _try_interact() -> void:
	var inter: Interactable = player.current
	if inter == null or not inter.enabled:
		return
	var beat_id := String(StoryData.get_trigger_beats().get(inter.interact_id, ""))
	if beat_id == "":
		push_warning("GameManager: interactable '%s' has no mapped beat." % inter.interact_id)
		return
	if inter.one_shot:
		inter.disable()
	audio.play_sfx("interact")
	start_beat(beat_id)


func _on_focus_changed(interactable) -> void:
	var inter := interactable as Interactable
	if state == State.EXPLORE and inter != null:
		ui.show_prompt("[E] " + inter.get_prompt())
	else:
		ui.hide_prompt()


# ------------------------------------------------------------------
# Beat effects (world changes triggered by story data)
# ------------------------------------------------------------------

func _apply_effect(effect_name: String) -> void:
	match effect_name:
		"open_door":
			apartment.open_front_door()
		"blackout":
			apartment.set_blackout(true)
			apartment.disable_all_interactables()
			audio.play_sfx("power_cut")
			player.add_shake(0.5)
			if world_env and world_env.environment:
				var tw := create_tween()
				tw.tween_property(world_env.environment, "ambient_light_energy", 0.05, 1.2)
		"phone_ring":
			audio.play_sfx("phone_ring")
		"power_stutter":
			apartment.stutter_power()
			audio.play_sfx("power_stutter")
		_:
			push_warning("GameManager: unknown beat effect '%s'." % effect_name)
