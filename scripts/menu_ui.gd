class_name MenuUI
extends CanvasLayer
## Pause menu (Esc during EXPLORE): Resume / Save Game / Load Game /
## Settings / Quit. Code-built like dialogue_ui.gd (layer 30, above the phone).
##
## The GameManager drives open()/close() and handles the signals; settings
## changes and slot labels go through SettingsManager / SaveManager directly.

signal resume_pressed
signal save_slot_chosen(slot: int)
signal load_slot_chosen(slot: int)
signal quit_pressed

const _TEXT := Color(0.93, 0.93, 0.96)
const _DIM := Color(0.62, 0.62, 0.68)

var _open := false
var _root: Control
var _title: Label
var _main_view: VBoxContainer
var _settings_view: VBoxContainer
var _slots_view: VBoxContainer
var _slot_buttons: Array = []
var _slots_mode := "save"

var _vol_slider: HSlider
var _sens_slider: HSlider
var _vol_value: Label
var _sens_value: Label
var _invert_check: CheckButton

var _settings: SettingsManager
var _saves: SaveManager


func _ready() -> void:
	layer = 30
	_build()
	_root.visible = false


func setup(settings: SettingsManager, saves: SaveManager) -> void:
	_settings = settings
	_saves = saves


func is_open() -> bool:
	return _open


func open() -> void:
	_open = true
	_show_main()
	_root.visible = true


func close() -> void:
	_open = false
	_root.visible = false


## Refresh the slot button labels (called after a save).
func refresh_slots() -> void:
	if _saves == null:
		return
	for i in range(_slot_buttons.size()):
		var b := _slot_buttons[i] as Button
		b.text = "Slot %d\n%s" % [i + 1, _saves.slot_summary(i + 1)]


# ------------------------------------------------------------------
# Construction
# ------------------------------------------------------------------

func _vbox() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	return v


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override("font_size", 19)
	return b


func _back_button() -> Button:
	var b := _button("‹ Back")
	b.pressed.connect(_show_main)
	return b


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.05, 0.97)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.3, 0.3, 0.35)
	sb.content_margin_left = 32.0
	sb.content_margin_right = 32.0
	sb.content_margin_top = 26.0
	sb.content_margin_bottom = 26.0
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_color", _TEXT)
	vbox.add_child(_title)

	_main_view = _vbox()
	_settings_view = _vbox()
	_slots_view = _vbox()
	vbox.add_child(_main_view)
	vbox.add_child(_settings_view)
	vbox.add_child(_slots_view)

	_build_main()
	_build_settings()
	_build_slots()


func _build_main() -> void:
	var resume := _button("Resume")
	resume.pressed.connect(func() -> void: resume_pressed.emit())
	_main_view.add_child(resume)
	var save := _button("Save Game")
	save.pressed.connect(func() -> void: _show_slots("save"))
	_main_view.add_child(save)
	var load := _button("Load Game")
	load.pressed.connect(func() -> void: _show_slots("load"))
	_main_view.add_child(load)
	var settings := _button("Settings")
	settings.pressed.connect(_show_settings)
	_main_view.add_child(settings)
	var quit := _button("Quit to Desktop")
	quit.pressed.connect(func() -> void: quit_pressed.emit())
	_main_view.add_child(quit)


func _slider_row(label_text: String) -> Dictionary:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	var hbox := HBoxContainer.new()
	var lab := Label.new()
	lab.text = label_text
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.add_theme_font_size_override("font_size", 17)
	lab.add_theme_color_override("font_color", _TEXT)
	hbox.add_child(lab)
	var val := Label.new()
	val.add_theme_font_size_override("font_size", 17)
	val.add_theme_color_override("font_color", _DIM)
	hbox.add_child(val)
	vbox.add_child(hbox)
	var slider := HSlider.new()
	slider.focus_mode = Control.FOCUS_NONE
	slider.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(slider)
	_settings_view.add_child(vbox)
	return {"slider": slider, "value": val}


func _build_settings() -> void:
	var vol := _slider_row("Master Volume")
	_vol_slider = vol["slider"] as HSlider
	_vol_value = vol["value"] as Label
	_vol_slider.min_value = 0.0
	_vol_slider.max_value = 100.0
	_vol_slider.step = 1.0
	_vol_slider.value_changed.connect(_on_vol_changed)

	var sens := _slider_row("Mouse Sensitivity")
	_sens_slider = sens["slider"] as HSlider
	_sens_value = sens["value"] as Label
	_sens_slider.min_value = 0.5
	_sens_slider.max_value = 2.0
	_sens_slider.step = 0.05
	_sens_slider.value_changed.connect(_on_sens_changed)

	_invert_check = CheckButton.new()
	_invert_check.text = "Invert Y axis"
	_invert_check.focus_mode = Control.FOCUS_NONE
	_invert_check.add_theme_font_size_override("font_size", 17)
	_invert_check.toggled.connect(_on_invert_toggled)
	_settings_view.add_child(_invert_check)

	_settings_view.add_child(_back_button())


func _build_slots() -> void:
	for i in range(SaveManager.SLOT_COUNT):
		var b := _button("")
		b.pressed.connect(_on_slot_pressed.bind(i + 1))
		_slot_buttons.append(b)
		_slots_view.add_child(b)
	_slots_view.add_child(_back_button())


# ------------------------------------------------------------------
# Views
# ------------------------------------------------------------------

func _show_main() -> void:
	_title.text = "PAUSED"
	_main_view.visible = true
	_settings_view.visible = false
	_slots_view.visible = false


func _show_settings() -> void:
	if _settings == null:
		return
	_title.text = "SETTINGS"
	_main_view.visible = false
	_slots_view.visible = false
	_settings_view.visible = true
	_vol_slider.set_value_no_signal(_settings.volume)
	_vol_value.text = "%d%%" % _settings.volume
	_sens_slider.set_value_no_signal(_settings.sensitivity_mult)
	_sens_value.text = "%.2fx" % _settings.sensitivity_mult
	_invert_check.set_pressed_no_signal(_settings.invert_y)


func _show_slots(mode: String) -> void:
	_slots_mode = mode
	_title.text = "SAVE GAME" if mode == "save" else "LOAD GAME"
	_main_view.visible = false
	_settings_view.visible = false
	_slots_view.visible = true
	refresh_slots()


func _on_slot_pressed(slot: int) -> void:
	if _slots_mode == "save":
		save_slot_chosen.emit(slot)
	else:
		load_slot_chosen.emit(slot)


func _on_vol_changed(v: float) -> void:
	if _settings == null:
		return
	_settings.set_volume(int(v))
	_vol_value.text = "%d%%" % _settings.volume


func _on_sens_changed(v: float) -> void:
	if _settings == null:
		return
	_settings.set_sensitivity(v)
	_sens_value.text = "%.2fx" % _settings.sensitivity_mult


func _on_invert_toggled(b: bool) -> void:
	if _settings == null:
		return
	_settings.set_invert_y(b)
