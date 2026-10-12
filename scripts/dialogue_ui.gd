class_name DialogueUI
extends CanvasLayer
## All 2D interface: objective tracker, interact prompt, dialogue box, timed
## choice panel, "will remember that" toasts, letterbox bars, ending screen.
##
## The whole UI is built in code in _ready() so the entire interface lives in
## this one file — no .tscn wiring to keep in sync. The GameManager drives it;
## it never touches story data directly.

signal choice_selected(choice: Dictionary)

const _TEXT_COLOR := Color(0.93, 0.93, 0.96)
const _DIM_COLOR := Color(0.62, 0.62, 0.68)
const _SPEAKER_COLOR := Color(0.96, 0.82, 0.62)
const _OTHER_COLOR := Color(0.62, 0.74, 0.9)
const _TOAST_COLOR := Color(0.98, 0.9, 0.62)

var _objective: Label
var _chores: Label
var _prompt: Label
var _toast: Label
var _dialogue_panel: PanelContainer
var _speaker: Label
var _text: Label
var _choice_panel: PanelContainer
var _choice_list: VBoxContainer
var _timer_bar: ProgressBar
var _top_bar: ColorRect
var _bottom_bar: ColorRect
var _ending: Control
var _ending_title: Label
var _ending_sub: Label
var _fade: ColorRect

var _choices: Array = []
var _choice_active: bool = false
var _time_left: float = 0.0
var _time_max: float = 1.0
var _toast_tween: Tween = null


func _ready() -> void:
	layer = 10
	_build_objective()
	_build_chores()
	_build_prompt()
	_build_toast()
	_build_dialogue_panel()
	_build_choice_panel()
	_build_letterbox()
	_build_ending_screen()
	_build_fade()


# ------------------------------------------------------------------
# Construction helpers
# ------------------------------------------------------------------

func _shadowed(label: Label) -> Label:
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.8)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 16.0
	sb.content_margin_bottom = 16.0
	return sb


func _build_objective() -> void:
	_objective = Label.new()
	_objective.anchor_left = 0.0
	_objective.anchor_top = 0.0
	_objective.offset_left = 18.0
	_objective.offset_top = 14.0
	_objective.offset_right = 700.0
	_objective.offset_bottom = 44.0
	_objective.add_theme_font_size_override("font_size", 18)
	_objective.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	_shadowed(_objective)
	add_child(_objective)


func _build_chores() -> void:
	# Optional chore checklist, under the story objective. Driven by the
	# GameManager via set_chores(); hidden when empty.
	_chores = Label.new()
	_chores.offset_left = 18.0
	_chores.offset_top = 42.0
	_chores.offset_right = 700.0
	_chores.offset_bottom = 68.0
	_chores.add_theme_font_size_override("font_size", 15)
	_chores.add_theme_color_override("font_color", Color(0.6, 0.68, 0.6))
	_shadowed(_chores)
	_chores.visible = false
	add_child(_chores)


func _build_prompt() -> void:
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt.offset_top = -264.0
	_prompt.offset_bottom = -232.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 20)
	_prompt.add_theme_color_override("font_color", _TEXT_COLOR)
	_shadowed(_prompt)
	_prompt.visible = false
	add_child(_prompt)


func _build_toast() -> void:
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_top = 64.0
	_toast.offset_bottom = 104.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_color", _TOAST_COLOR)
	_shadowed(_toast)
	_toast.modulate.a = 0.0
	add_child(_toast)


func _build_dialogue_panel() -> void:
	_dialogue_panel = PanelContainer.new()
	_dialogue_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_dialogue_panel.offset_left = 48.0
	_dialogue_panel.offset_right = -48.0
	_dialogue_panel.offset_top = -212.0
	_dialogue_panel.offset_bottom = -28.0
	_dialogue_panel.add_theme_stylebox_override("panel", _panel_style())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_dialogue_panel.add_child(vbox)

	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 20)
	_speaker.add_theme_color_override("font_color", _SPEAKER_COLOR)
	vbox.add_child(_speaker)

	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 21)
	_text.add_theme_color_override("font_color", _TEXT_COLOR)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(0, 84)
	vbox.add_child(_text)

	var hint := Label.new()
	hint.text = "E / click ▸"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", _DIM_COLOR)
	vbox.add_child(hint)

	_dialogue_panel.visible = false
	add_child(_dialogue_panel)


func _build_choice_panel() -> void:
	_choice_panel = PanelContainer.new()
	_choice_panel.anchor_left = 0.5
	_choice_panel.anchor_right = 0.5
	_choice_panel.anchor_top = 1.0
	_choice_panel.anchor_bottom = 1.0
	_choice_panel.offset_left = -300.0
	_choice_panel.offset_right = 300.0
	_choice_panel.offset_top = -470.0
	_choice_panel.offset_bottom = -240.0
	_choice_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_choice_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_choice_panel.add_theme_stylebox_override("panel", _panel_style())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_choice_panel.add_child(vbox)

	_timer_bar = ProgressBar.new()
	_timer_bar.show_percentage = false
	_timer_bar.custom_minimum_size = Vector2(0, 12)
	_timer_bar.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	vbox.add_child(_timer_bar)

	_choice_list = VBoxContainer.new()
	_choice_list.add_theme_constant_override("separation", 8)
	vbox.add_child(_choice_list)

	_choice_panel.visible = false
	add_child(_choice_panel)


func _build_letterbox() -> void:
	_top_bar = ColorRect.new()
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_bar.offset_bottom = 64.0
	_top_bar.color = Color.BLACK
	_top_bar.visible = false
	add_child(_top_bar)

	_bottom_bar = ColorRect.new()
	_bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom_bar.offset_top = -64.0
	_bottom_bar.color = Color.BLACK
	_bottom_bar.visible = false
	add_child(_bottom_bar)


func _build_ending_screen() -> void:
	_ending = Control.new()
	_ending.set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color.BLACK
	_ending.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ending.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	_ending_title = Label.new()
	_ending_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ending_title.add_theme_font_size_override("font_size", 64)
	_ending_title.add_theme_color_override("font_color", Color(0.75, 0.12, 0.12))
	vbox.add_child(_ending_title)

	_ending_sub = Label.new()
	_ending_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ending_sub.add_theme_font_size_override("font_size", 24)
	_ending_sub.add_theme_color_override("font_color", _DIM_COLOR)
	vbox.add_child(_ending_sub)

	var hint := Label.new()
	hint.text = "Press R to play again"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", _DIM_COLOR)
	vbox.add_child(hint)

	_ending.visible = false
	add_child(_ending)


func _build_fade() -> void:
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


# ------------------------------------------------------------------
# Per-frame: choice countdown
# ------------------------------------------------------------------

func _process(delta: float) -> void:
	if _choice_active:
		_time_left -= delta
		_timer_bar.value = _time_left
		if _time_left <= 0.0:
			_choose_default()


# ------------------------------------------------------------------
# Public API (driven by the GameManager)
# ------------------------------------------------------------------

func fade_from_black(duration: float = 1.6) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, duration)


func set_objective(text: String) -> void:
	_objective.text = text
	_objective.visible = text != ""


## Current objective text (used for save-slot labels).
func get_objective() -> String:
	return _objective.text


func set_chores(text: String) -> void:
	_chores.text = text
	_chores.visible = text != ""


func show_prompt(text: String) -> void:
	_prompt.text = text
	_prompt.visible = true


func hide_prompt() -> void:
	_prompt.visible = false


func show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.2)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.8)


func show_dialogue(who: String, text: String) -> void:
	if who == "":
		_speaker.visible = false
	else:
		_speaker.visible = true
		_speaker.text = who
		# Tint non-Mara speakers colder for readability.
		if who == "MARA":
			_speaker.add_theme_color_override("font_color", _SPEAKER_COLOR)
		else:
			_speaker.add_theme_color_override("font_color", _OTHER_COLOR)
	_text.text = text
	_dialogue_panel.visible = true


func hide_dialogue() -> void:
	_dialogue_panel.visible = false


func show_choices(choices: Array, timeout: float) -> void:
	for child in _choice_list.get_children():
		child.queue_free()
	_choices = choices
	_time_max = timeout
	_time_left = timeout
	_timer_bar.max_value = timeout
	_timer_bar.value = timeout
	for i in choices.size():
		var choice: Dictionary = choices[i]
		var btn := Button.new()
		btn.text = "%d. %s" % [i + 1, String(choice.get("text", "…"))]
		btn.add_theme_font_size_override("font_size", 20)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_choice_button.bind(i))
		_choice_list.add_child(btn)
	_choice_panel.visible = true
	_choice_active = true


func hide_choices() -> void:
	_choice_active = false
	_choice_panel.visible = false


## Hotkey (1-4) selection, routed from the GameManager.
func select_index(i: int) -> void:
	if _choice_active and i >= 0 and i < _choices.size():
		_choose(i)


func set_letterbox(visible: bool) -> void:
	_top_bar.visible = visible
	_bottom_bar.visible = visible


func show_ending(title: String, subtitle: String) -> void:
	hide_prompt()
	hide_dialogue()
	hide_choices()
	_ending_title.text = title
	_ending_sub.text = subtitle
	_ending.visible = true


# ------------------------------------------------------------------
# Internal
# ------------------------------------------------------------------

func _on_choice_button(i: int) -> void:
	_choose(i)


func _choose_default() -> void:
	var idx := 0
	for i in _choices.size():
		if bool((_choices[i] as Dictionary).get("default", false)):
			idx = i
			break
	_choose(idx)


func _choose(i: int) -> void:
	if not _choice_active:
		return
	_choice_active = false
	_choice_panel.visible = false
	choice_selected.emit(_choices[i])
