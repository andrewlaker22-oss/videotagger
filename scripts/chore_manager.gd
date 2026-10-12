class_name ChoreManager
extends Node
## Optional house-chore minigames: taking out the trash (fetch-and-carry) and
## washing dishes (hold-to-scrub). Pure side content — offered after the intro,
## never blocks story beats, and persists across dialogue.
##
## Trash: 3 bags (kitchen / living room / bedroom). E picks up ONE at a time
## (visible in hand, slight slowdown); E at the porch bin tosses it in.
## First deposit while outside at night triggers a stalker text.
##
## Dishes: E at the kitchen sink enters wash mode (movement locked, mouse
## released, camera leans in). Hold LMB or E to scrub; each of 4 dishes takes
## ~3 s (progress ring), *ding* per dish, then it moves to the drying rack.
## Finishing the 2nd dish flickers the kitchen lights and texts "turn around".
## Esc exits wash mode.
##
## The GameManager routes chore interactables here (ids "trash_*", "sink")
## and forwards Tab/Esc; this node owns all chore state and the wash UI.

signal changed  # emitted whenever checklist text or progress changes

const TRASH_TOTAL := 3
const DISH_TOTAL := 4
const SCRUB_TIME := 3.0  # seconds of held scrubbing per dish

var in_wash_mode: bool = false

var _trash_done := 0
var _carrying := ""  # bag id currently carried, "" = empty-handed
var _first_deposit := false
var _dishes_done := 0
var _dish_progress := 0.0
var _scrubbing := false
var _bag_bob := 0.0
var _head_base := Vector3.ZERO

var _player: PlayerController
var _ui: DialogueUI
var _apt: ApartmentBuilder
var _phone: PhoneUI
var _audio: AudioManager

var _bag_mesh: MeshInstance3D
var _active_plate: Node3D = null

var _wash_layer: CanvasLayer
var _ring: RingProgress
var _wash_info: Label


class RingProgress extends Control:
	## Circular progress ring drawn in _draw (no textures needed).
	var progress: float = 0.0

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 8.0
		draw_arc(c, r, 0.0, TAU, 64, Color(1, 1, 1, 0.22), 10.0, true)
		var a := TAU * clampf(progress, 0.0, 1.0)
		if a > 0.01:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + a, 64, Color(0.55, 0.85, 1.0), 10.0, true)


func _ready() -> void:
	_build_wash_ui()


func setup(player: PlayerController, ui: DialogueUI, apt: ApartmentBuilder, phone: PhoneUI, audio: AudioManager) -> void:
	_player = player
	_ui = ui
	_apt = apt
	_phone = phone
	_audio = audio
	# The carried bag rides on the camera, bottom-right of the view.
	_bag_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.26, 0.32, 0.26)
	_bag_mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.11, 0.11, 0.13)
	_bag_mesh.material_override = mat
	_bag_mesh.position = Vector3(0.32, -0.32, -0.55)
	_bag_mesh.visible = false
	_player.camera.add_child(_bag_mesh)


# ------------------------------------------------------------------
# Interactable routing (called by the GameManager)
# ------------------------------------------------------------------

func interact(interact_id: String) -> void:
	if interact_id.begins_with("trash_bag_"):
		_pickup_bag(interact_id)
	elif interact_id == "trash_bin":
		_deposit_bag()
	elif interact_id == "sink":
		if _dishes_done >= DISH_TOTAL:
			_ui.show_toast("Already sparkling.")
		else:
			enter_wash_mode()


func get_checklist() -> String:
	if _trash_done >= TRASH_TOTAL and _dishes_done >= DISH_TOTAL:
		return "Chores complete."
	return "Trash %d/%d · Dishes %d/%d" % [_trash_done, TRASH_TOTAL, _dishes_done, DISH_TOTAL]


# ------------------------------------------------------------------
# Trash: fetch-and-carry
# ------------------------------------------------------------------

func _pickup_bag(bag_id: String) -> void:
	if _carrying != "":
		_ui.show_toast("One bag at a time.")
		return
	_carrying = bag_id
	_apt.hide_trash_bag(bag_id)
	_disable_interactable(bag_id)
	_bag_mesh.visible = true
	_player.speed_factor = 0.85
	changed.emit()


func _deposit_bag() -> void:
	if _carrying == "":
		_ui.show_toast("Grab a trash bag first.")
		return
	_carrying = ""
	_trash_done += 1
	_bag_mesh.visible = false
	_player.speed_factor = 1.0
	_audio.play_sfx("toss")
	if not _first_deposit:
		# Horror hook: outside at night, vulnerable — the stalker texts.
		_first_deposit = true
		_phone.receive_text("unknown", "i can see you")
		_audio.play_sfx("text_buzz")
	if _trash_done >= TRASH_TOTAL:
		_ui.show_toast("All clean. For nothing.")
		_audio.play_sfx("ding")
	changed.emit()


func _disable_interactable(interact_id: String) -> void:
	for n in get_tree().get_nodes_in_group("interactable"):
		var inter := n as Interactable
		if inter != null and inter.interact_id == interact_id:
			inter.disable()
			return


# ------------------------------------------------------------------
# Dishes: wash mode
# ------------------------------------------------------------------

func enter_wash_mode() -> void:
	if in_wash_mode or _dishes_done >= DISH_TOTAL:
		return
	in_wash_mode = true
	_scrubbing = false
	_dish_progress = 0.0
	_ui.hide_prompt()
	_player.control_locked = true
	_player.allow_capture = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_head_base = _player.head.position
	var tw := create_tween()
	tw.tween_property(_player.head, "position", _head_base + Vector3(0.0, -0.04, 0.15), 0.5)
	_wash_layer.visible = true
	_update_wash_ui()
	_audio.play_sfx("water")


func exit_wash_mode() -> void:
	if not in_wash_mode:
		return
	in_wash_mode = false
	_scrubbing = false
	_wash_layer.visible = false
	_player.control_locked = false
	_player.allow_capture = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var tw := create_tween()
	tw.tween_property(_player.head, "position", _head_base, 0.4)
	_audio.play_sfx("interact")


func _unhandled_input(event: InputEvent) -> void:
	if not in_wash_mode:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_scrubbing = mb.pressed
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.physical_keycode == KEY_E:
			_scrubbing = k.pressed
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if in_wash_mode and _dishes_done < DISH_TOTAL:
		if _scrubbing:
			_dish_progress += delta / SCRUB_TIME
			if _dish_progress >= 1.0:
				_complete_dish()
			else:
				_ring.progress = _dish_progress
				_ring.queue_redraw()
				if _active_plate != null:
					_active_plate.rotation.z = sin(Time.get_ticks_msec() / 1000.0 * 28.0) * 0.06
		elif _active_plate != null:
			_active_plate.rotation.z = 0.0
	if _carrying != "" and _bag_mesh != null and _bag_mesh.visible:
		_bag_bob += delta
		_bag_mesh.position.y = -0.32 + sin(_bag_bob * 7.0) * 0.012


func _complete_dish() -> void:
	var idx := _dishes_done
	_dishes_done += 1
	_dish_progress = 0.0
	_ring.progress = 0.0
	_ring.queue_redraw()
	if _active_plate != null:
		_active_plate.rotation.z = 0.0
	_audio.play_sfx("ding")
	_apt.dish_to_rack(idx)
	_active_plate = _apt.get_dish_plate(_dishes_done)
	if _dishes_done == 2:
		# Horror hook: attention occupied at the sink — lights flicker,
		# and the stalker texts.
		_apt.flicker_near(Vector3(4.9, 2.4, -2.5), 5.0, 1.6)
		_phone.receive_text("unknown", "turn around")
		_audio.play_sfx("text_buzz")
	if _dishes_done >= DISH_TOTAL:
		_ui.show_toast("Dishes done.")
		_audio.play_sfx("ding")
		exit_wash_mode()
		_disable_interactable("sink")
	else:
		_update_wash_ui()
	changed.emit()


func _update_wash_ui() -> void:
	_wash_info.text = "Dish %d of %d" % [_dishes_done + 1, DISH_TOTAL]
	_active_plate = _apt.get_dish_plate(_dishes_done)


func _build_wash_ui() -> void:
	_wash_layer = CanvasLayer.new()
	_wash_layer.layer = 15
	_wash_layer.visible = false
	add_child(_wash_layer)

	_ring = RingProgress.new()
	_ring.set_anchors_preset(Control.PRESET_CENTER)
	_ring.offset_left = -70.0
	_ring.offset_top = -110.0
	_ring.offset_right = 70.0
	_ring.offset_bottom = 30.0
	_wash_layer.add_child(_ring)

	_wash_info = Label.new()
	_wash_info.set_anchors_preset(Control.PRESET_CENTER)
	_wash_info.offset_left = -150.0
	_wash_info.offset_top = 40.0
	_wash_info.offset_right = 150.0
	_wash_info.offset_bottom = 70.0
	_wash_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wash_info.add_theme_font_size_override("font_size", 22)
	_wash_info.add_theme_color_override("font_color", Color(0.93, 0.93, 0.96))
	_wash_info.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_wash_info.add_theme_constant_override("shadow_offset_x", 2)
	_wash_info.add_theme_constant_override("shadow_offset_y", 2)
	_wash_layer.add_child(_wash_info)

	var hint := Label.new()
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -300.0
	hint.offset_top = -120.0
	hint.offset_right = 300.0
	hint.offset_bottom = -90.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "Hold LMB to scrub · Esc to stop"
	hint.add_theme_font_size_override("font_size", 17)
	hint.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68))
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	hint.add_theme_constant_override("shadow_offset_x", 2)
	hint.add_theme_constant_override("shadow_offset_y", 2)
	_wash_layer.add_child(hint)
