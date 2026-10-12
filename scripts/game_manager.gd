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

## Phone checklist (sequential onboarding). Each item maps to a flag;
## the first incomplete item is "current", later ones are "locked".
const CHECKLIST_ORDER: Array = ["lock_door", "text_mom", "unpack"]
const CHECKLIST_LABELS := {
	"lock_door": "Lock the front door",
	"text_mom": "Text Mom you're home",
	"unpack": "Unpack the boxes",
}
const CHECKLIST_FLAGS := {
	"lock_door": "door_locked",
	"text_mom": "texted_mom",
	"unpack": "unpacking_done",
}

var state: int = State.EXPLORE
var flags: Dictionary = {}

## Hiding spots (future stalker room-check sequence — no stalker AI yet,
## just the hide/unhide mechanic). "" = not hidden; otherwise one of
## "bedroom_closet" / "bathroom_closet" / "foyer_closet".
var hidden_spot_id: String = ""

## Per-spot hide transform: where the player stands inside, and the yaw
## they face (outward, through the door). Exit = wherever they stood when
## they hid (stored in _hide_entry_pos), so unhide is always safe.
const HIDE_SPOTS := {
	"bedroom_closet": {"hide_pos": Vector3(6.30, 2.7, -0.5), "face_yaw": PI * 0.5},
	"bathroom_closet": {"hide_pos": Vector3(-6.0, 2.7, -1.55), "face_yaw": 0.0},
	"foyer_closet": {"hide_pos": Vector3(1.80, 0.0, 3.5), "face_yaw": PI * 0.5},
}
const HIDE_YAW_LIMIT := 1.05  # ~60 degrees of peeking while hidden.

var _hide_entry_pos: Vector3 = Vector3.ZERO
var _unhide_busy: bool = false

var _beat: Dictionary = {}
var _line_index: int = 0

@onready var player: PlayerController = $Player
@onready var ui: DialogueUI = $DialogueUI
@onready var apartment: ApartmentBuilder = $Apartment
@onready var audio: AudioManager = $AudioManager
@onready var phone_ui: PhoneUI = $PhoneUI
@onready var chores: ChoreManager = $ChoreManager
@onready var unpack: UnpackManager = $UnpackManager
@onready var world_env: WorldEnvironment = $WorldEnvironment


func _ready() -> void:
	player.primary_action.connect(_on_primary_action)
	player.choice_hotkey.connect(_on_choice_hotkey)
	player.focus_changed.connect(_on_focus_changed)
	ui.choice_selected.connect(_on_choice_selected)
	chores.setup(player, ui, apartment, phone_ui, audio)
	chores.changed.connect(_on_chores_changed)
	unpack.setup(player, ui, apartment, phone_ui, audio)
	unpack.changed.connect(_on_unpack_changed)
	unpack.completed.connect(_on_unpack_completed)
	phone_ui.quick_reply_tapped.connect(_on_quick_reply_tapped)
	phone_ui.load_threads(StoryData.get_phone_threads())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ui.fade_from_black()
	await get_tree().create_timer(1.4).timeout
	start_beat(StoryData.get_start_beat_id())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			match k.physical_keycode:
				KEY_R:
					if state == State.ENDING:
						get_tree().reload_current_scene()
				KEY_TAB:
					if state == State.EXPLORE:
						if chores.in_wash_mode:
							chores.exit_wash_mode()
						else:
							_toggle_phone()
						get_viewport().set_input_as_handled()
				KEY_ESCAPE:
					if phone_ui.is_open():
						_close_phone()
						get_viewport().set_input_as_handled()
					elif chores.in_wash_mode:
						chores.exit_wash_mode()
						get_viewport().set_input_as_handled()


# ------------------------------------------------------------------
# Beat flow
# ------------------------------------------------------------------

func start_beat(beat_id: String) -> void:
	var beats := StoryData.get_beats()
	if not beats.has(beat_id):
		push_error("GameManager: unknown beat id '%s'." % beat_id)
		return
	# A story beat never plays while the player is hidden: step out first
	# (instantly), then run the beat normally.
	if is_player_hidden():
		_unhide(true)
	_beat = beats[beat_id]
	phone_ui.advance_clock()
	for effect in _beat.get("effects", []):
		if effect is Dictionary:
			_apply_effect_dict(effect)
		else:
			_apply_effect(String(effect))
	if _beat.has("objective"):
		ui.set_objective(String(_beat["objective"]))
		# A story objective takes over from the unpacking/checklist trackers.
		flags["unpacking_objective"] = false
		flags["checklist_objective"] = false
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
	# The phone checklist is the onboarding: offered once, right after the
	# intro, as the first objective. The phone auto-opens on the checklist
	# the very first time. The optional chores come after unpacking.
	if not bool(flags.get("checklist_started", false)) and not bool(flags.get("unpacking_done", false)):
		flags["checklist_started"] = true
		flags["checklist_objective"] = true
		_refresh_checklist()
		ui.show_toast("Check your list — press Tab")
		_open_phone("checklist")
	elif not bool(flags.get("chores_offered", false)) and bool(flags.get("unpacking_done", false)):
		flags["chores_offered"] = true
		_offer_chores()


func _offer_chores() -> void:
	ui.show_toast("The place is a mess. Tidy up? (Optional)")
	ui.set_chores(chores.get_checklist())


# ------------------------------------------------------------------
# Hiding spots. E on a "hide_*" hotspot snaps the player just inside the
# closet (facing out), swings the door shut, and locks movement while
# keeping mouse-look (clamped to a peek cone). E again steps back out.
# No stalker AI reads this yet; is_player_hidden()/hidden_spot_id are
# the future-proof query surface.
# ------------------------------------------------------------------

func is_player_hidden() -> bool:
	return hidden_spot_id != ""


func _hide(spot_id: String) -> void:
	if is_player_hidden() or state != State.EXPLORE:
		return
	if not HIDE_SPOTS.has(spot_id):
		return
	var spot: Dictionary = HIDE_SPOTS[spot_id]
	_hide_entry_pos = player.global_position
	hidden_spot_id = spot_id
	player.velocity = Vector3.ZERO
	player.global_position = spot["hide_pos"]
	player.rotation.y = float(spot["face_yaw"])
	player.head.rotation.x = 0.0
	player.movement_locked = true
	player.set_yaw_limits(float(spot["face_yaw"]), HIDE_YAW_LIMIT)
	apartment.set_hide_door(spot_id, false)
	var inter := _find_interactable("hide_" + spot_id)
	if inter != null:
		inter.disable()
	ui.hide_prompt()
	ui.show_prompt("Hidden — E to come out")
	audio.play_sfx("hide")


func _unhide(instant: bool = false) -> void:
	if not is_player_hidden() or _unhide_busy:
		return
	var spot_id := hidden_spot_id
	if instant:
		# Story beat fired mid-hide: snap everything, no waiting.
		apartment.set_hide_door_immediate(spot_id, true)
		_finish_unhide(spot_id)
		return
	_unhide_busy = true
	apartment.set_hide_door(spot_id, true)
	await get_tree().create_timer(0.45).timeout
	_unhide_busy = false
	if hidden_spot_id == spot_id:
		_finish_unhide(spot_id)


func _finish_unhide(spot_id: String) -> void:
	hidden_spot_id = ""
	player.movement_locked = false
	player.clear_yaw_limits()
	player.velocity = Vector3.ZERO
	player.global_position = _hide_entry_pos
	var inter := _find_interactable("hide_" + spot_id)
	if inter != null:
		inter.enable()
	ui.hide_prompt()
	audio.play_sfx("unhide")


func _find_interactable(interact_id: String) -> Interactable:
	for n in get_tree().get_nodes_in_group("interactable"):
		var inter := n as Interactable
		if inter != null and inter.interact_id == interact_id:
			return inter
	return null


func _enable_interactable(interact_id: String) -> void:
	var inter := _find_interactable(interact_id)
	if inter != null:
		inter.enable()


## Fully retires an interactable: disabled AND removed from the interact
## ray, so it can never occlude a hotspot placed behind/over it.
func _retire_interactable(interact_id: String) -> void:
	var inter := _find_interactable(interact_id)
	if inter == null:
		return
	inter.disable()
	for c in inter.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = true


## First checklist item id whose flag is not set ("" when all done).
func _checklist_current() -> String:
	for id in CHECKLIST_ORDER:
		if not bool(flags.get(String(CHECKLIST_FLAGS[id]), false)):
			return String(id)
	return ""


## Rebuilds the phone checklist UI, arms the Mom quick-reply while it's
## the current item, unlocks unpacking once (a) and (b) are done, and
## tracks the HUD objective on the current item.
func _refresh_checklist() -> void:
	var items: Array = []
	var current := _checklist_current()
	for id in CHECKLIST_ORDER:
		var sid := String(id)
		var done := bool(flags.get(String(CHECKLIST_FLAGS[sid]), false))
		var state := "done"
		if not done:
			state = "current" if sid == current else "locked"
		items.append({"id": sid, "label": String(CHECKLIST_LABELS[sid]), "state": state})
	phone_ui.set_checklist(items)
	# Quick-reply for "text mom" only while it's the current item.
	if current == "text_mom":
		phone_ui.set_quick_reply("mom", "home safe! love you")
	else:
		phone_ui.clear_quick_reply()
	# Unlock the unpacking boxes once locking + texting are done.
	if current == "unpack" and not unpack.is_started():
		flags["unpacking_offered"] = true
		flags["unpacking_objective"] = true
		flags["checklist_objective"] = false
		unpack.start()
	elif bool(flags.get("checklist_objective", false)) and current != "":
		ui.set_objective(String(CHECKLIST_LABELS[current]))


func _lock_front_door() -> void:
	if bool(flags.get("door_locked", false)):
		return
	if _checklist_current() != "lock_door":
		return
	# Don't swing the panel through the player.
	if player.global_position.distance_to(Vector3(0.8, 0.0, 5.0)) < 1.6:
		ui.show_toast("Step away from the door first.")
		return
	flags["door_locked"] = true
	apartment.close_front_door()
	audio.play_sfx("door_lock")
	audio.play_sfx("ding")
	ui.show_toast("Front door locked.")
	_disable_interactable("front_door_lock")
	_refresh_checklist()


func _on_quick_reply_tapped(thread_id: String, text: String) -> void:
	if thread_id != "mom" or _checklist_current() != "text_mom":
		return
	phone_ui.clear_quick_reply()
	phone_ui.send_text("mom", text)
	flags["texted_mom"] = true
	audio.play_sfx("ding")
	ui.show_toast("Sent.")
	_refresh_checklist()


func _disable_interactable(interact_id: String) -> void:
	for n in get_tree().get_nodes_in_group("interactable"):
		var inter := n as Interactable
		if inter != null and inter.interact_id == interact_id:
			inter.disable()
			return


func _on_unpack_changed() -> void:
	if bool(flags.get("unpacking_objective", false)):
		ui.set_objective("Unpack the boxes (%d/%d)" % [unpack.get_done(), UnpackManager.TOTAL])


func _on_unpack_completed() -> void:
	flags["unpacking_done"] = true
	if bool(flags.get("unpacking_objective", false)):
		flags["unpacking_objective"] = false
		ui.set_objective("")
	_refresh_checklist()  # marks "unpack" done in the phone checklist
	# Let the note land before the chores prompt appears.
	await get_tree().create_timer(3.5).timeout
	if not bool(flags.get("chores_offered", false)):
		flags["chores_offered"] = true
		_offer_chores()


func _on_chores_changed() -> void:
	ui.set_chores(chores.get_checklist())


# ------------------------------------------------------------------
# Phone (Tab to open/close during EXPLORE only)
# ------------------------------------------------------------------

func _toggle_phone() -> void:
	if phone_ui.is_open():
		_close_phone()
	else:
		_open_phone()


func _open_phone(view: String = "messages") -> void:
	phone_ui.open(view)
	ui.hide_prompt()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.control_locked = true
	player.allow_capture = false
	audio.play_sfx("phone_open")


func _close_phone() -> void:
	phone_ui.close()
	player.control_locked = false
	player.allow_capture = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	audio.play_sfx("phone_close")


# ------------------------------------------------------------------
# Input routing (raw signals from the Player)
# ------------------------------------------------------------------

func _on_primary_action() -> void:
	match state:
		State.EXPLORE:
			if not phone_ui.is_open() and not chores.in_wash_mode:
				_try_interact()
		State.DIALOGUE:
			_advance_line()
		_:
			pass


func _on_choice_hotkey(index: int) -> void:
	if state == State.CHOICE:
		ui.select_index(index)


func _try_interact() -> void:
	# E while hidden always steps out — no aim needed.
	if is_player_hidden():
		_unhide()
		return
	var inter: Interactable = player.current
	if inter == null or not inter.enabled:
		return
	# Hiding-spot hotspots go to the hide mechanic (never story beats).
	var cid := String(inter.interact_id)
	if cid.begins_with("hide_"):
		_hide(cid.trim_prefix("hide_"))
		return
	# Mechanical doors toggle instead of starting a story beat.
	if String(inter.interact_id).begins_with("door_"):
		apartment.toggle_door(inter.interact_id)
		audio.play_sfx("interact")
		return
	# Chore hotspots go to the ChoreManager (optional minigames).
	if cid.begins_with("trash_") or cid == "sink":
		chores.interact(cid)
		audio.play_sfx("interact")
		return
	# Unpacking hotspots go to the UnpackManager (core opening gameplay).
	if cid.begins_with("unpack_") or cid.begins_with("uzone_"):
		unpack.interact(cid)
		audio.play_sfx("interact")
		return
	# Front-door lock (phone checklist item).
	if cid == "front_door_lock":
		_lock_front_door()
		return
	var beat_id := String(StoryData.get_trigger_beats().get(inter.interact_id, ""))
	if beat_id == "":
		push_warning("GameManager: interactable '%s' has no mapped beat." % inter.interact_id)
		return
	if inter.one_shot:
		inter.disable()
	audio.play_sfx("interact")
	# The bedroom wardrobe's story beat is consumed: retire its hotspot
	# (including ray occlusion) and create the Hide hotspot for the door.
	if inter.interact_id == "bedroom_closet":
		_retire_interactable("bedroom_closet")
		apartment.add_hide_hotspot("bedroom_closet")
	start_beat(beat_id)


func _on_focus_changed(interactable) -> void:
	var inter := interactable as Interactable
	if is_player_hidden():
		# Keep the exit hint up; no other prompts while hidden.
		ui.show_prompt("Hidden — E to come out")
		return
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


## Dictionary beat effects (see the "effects" schema in story_data.gd).
func _apply_effect_dict(d: Dictionary) -> void:
	match String(d.get("effect", "")):
		"text":
			var from_id := String(d.get("from", ""))
			var text := String(d.get("text", ""))
			if from_id == "mara":
				phone_ui.send_text(String(d.get("to", "")), text)
			else:
				phone_ui.receive_text(from_id, text)
				audio.play_sfx("text_buzz")
		_:
			push_warning("GameManager: unknown dict beat effect '%s'." % str(d.get("effect", "")))
