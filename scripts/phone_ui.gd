class_name PhoneUI
extends CanvasLayer
## iPhone-style text message UI for WATCHED.
##
## Dark-mode phone that slides up from the bottom-right of the screen:
## thread list (Mom / Jess / Unknown), conversation view with message bubbles,
## unread badges, a notification banner that slides down from the top when a
## text arrives, and a status-bar clock (11:47 PM, +1 min per story beat).
##
## The whole UI is built in code in _ready(), like dialogue_ui.gd. The
## GameManager drives it (load_threads / receive_text / send_text / open /
## close / advance_clock); it never touches StoryData directly.
##
## Mara never types: her outgoing messages are scripted by story data
## ("text" effects with "from": "mara"). The phone is display + reading only,
## except for scripted quick-replies (see set_quick_reply).

signal quick_reply_tapped(thread_id: String, text: String)

const _PHONE_W := 360.0
const _PHONE_H := 620.0
const _MARGIN := 24.0

const _BG := Color(0.02, 0.02, 0.03)
const _SCREEN_BG := Color(0.11, 0.11, 0.12)
const _TEXT_COLOR := Color(0.93, 0.93, 0.96)
const _DIM_COLOR := Color(0.6, 0.6, 0.65)
const _BUBBLE_IN := Color(0.23, 0.23, 0.25)
const _BUBBLE_OUT := Color(0.04, 0.52, 1.0)
const _ACCENT := Color(0.04, 0.52, 1.0)

var _threads: Dictionary = {}
var _order: Array = []
var _open := false
var _current_thread := ""
var _minutes := 23 * 60 + 46  # intro beat ticks it to 11:47 PM

var _phone_body: PanelContainer
var _home_y := 0.0
var _clock_label: Label
var _list_view: VBoxContainer
var _list_rows: VBoxContainer
var _convo_view: VBoxContainer
var _convo_name: Label
var _convo_scroll: ScrollContainer
var _convo_msgs: VBoxContainer
var _banner: PanelContainer
var _banner_title: Label
var _banner_preview: Label
var _banner_queue: Array = []
var _banner_showing := false

# Checklist tab: to-do list with done / current / locked states.
var _checklist: Array = []
var _checklist_view: VBoxContainer
var _checklist_rows: VBoxContainer
var _tab_messages: Button
var _tab_checklist: Button
# Scripted quick-reply inside a conversation (e.g. texting Mom).
var _quick_reply_thread := ""
var _quick_reply_text := ""
var _quick_reply_btn: Button
var _convo_hint: Label


func _ready() -> void:
	layer = 20
	_build_banner()
	_build_phone()


# ------------------------------------------------------------------
# Construction
# ------------------------------------------------------------------

func _rounded(bg: Color, radius: float, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(radius))
	if border.a > 0.0:
		sb.set_border_width_all(2)
		sb.border_color = border
	return sb


func _label(text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.anchor_top = 0.0
	_banner.anchor_bottom = 0.0
	_banner.offset_left = -240.0
	_banner.offset_right = 240.0
	_banner.offset_top = 12.0
	_banner.offset_bottom = 104.0
	_banner.add_theme_stylebox_override("panel",
		_rounded(Color(0.13, 0.13, 0.15, 0.97), 18, Color(0.3, 0.3, 0.33, 0.6)))
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)
	_banner_title = _label("MESSAGES", 14, _DIM_COLOR)
	vbox.add_child(_banner_title)
	_banner_preview = _label("", 15, _TEXT_COLOR)
	_banner_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_preview.max_lines_visible = 2
	vbox.add_child(_banner_preview)
	_banner.position.y = -130.0
	_banner.visible = false
	add_child(_banner)


func _build_phone() -> void:
	_phone_body = PanelContainer.new()
	_phone_body.anchor_left = 1.0
	_phone_body.anchor_top = 1.0
	_phone_body.anchor_right = 1.0
	_phone_body.anchor_bottom = 1.0
	_phone_body.offset_left = -(_PHONE_W + _MARGIN)
	_phone_body.offset_right = -_MARGIN
	_phone_body.offset_top = -(_PHONE_H + _MARGIN)
	_phone_body.offset_bottom = -_MARGIN
	_phone_body.add_theme_stylebox_override("panel",
		_rounded(Color(0.0, 0.0, 0.0), 44, Color(0.32, 0.32, 0.35)))
	_home_y = _phone_body.offset_top
	add_child(_phone_body)

	var screen_margin := MarginContainer.new()
	screen_margin.add_theme_constant_override("margin_left", 10)
	screen_margin.add_theme_constant_override("margin_right", 10)
	screen_margin.add_theme_constant_override("margin_top", 10)
	screen_margin.add_theme_constant_override("margin_bottom", 10)
	screen_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phone_body.add_child(screen_margin)

	var screen := PanelContainer.new()
	screen.add_theme_stylebox_override("panel", _rounded(_SCREEN_BG, 34))
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_margin.add_child(screen)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(vbox)

	vbox.add_child(_build_status_bar())
	_list_view = _build_list_view()
	vbox.add_child(_list_view)
	_convo_view = _build_convo_view()
	vbox.add_child(_convo_view)
	_checklist_view = _build_checklist_view()
	vbox.add_child(_checklist_view)
	vbox.add_child(_build_tab_bar())

	_phone_body.visible = false


func _build_status_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_label = _label(_clock_string(), 14, _TEXT_COLOR)
	_clock_label.custom_minimum_size = Vector2(90, 30)
	bar.add_child(_clock_label)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(center)
	var island := PanelContainer.new()
	island.custom_minimum_size = Vector2(92, 24)
	island.add_theme_stylebox_override("panel", _rounded(Color.BLACK, 12))
	island.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(island)
	var icons := _label("5G  ▮", 13, _TEXT_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	icons.custom_minimum_size = Vector2(90, 30)
	icons.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(icons)
	return bar


func _build_list_view() -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var header := _label("Messages", 30, _TEXT_COLOR)
	header.add_theme_constant_override("line_spacing", 0)
	var hpad := MarginContainer.new()
	hpad.add_theme_constant_override("margin_left", 14)
	hpad.add_theme_constant_override("margin_top", 6)
	hpad.add_theme_constant_override("margin_bottom", 8)
	hpad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hpad.add_child(header)
	vbox.add_child(hpad)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_list_rows = VBoxContainer.new()
	_list_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_rows.add_theme_constant_override("separation", 2)
	_list_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_list_rows)
	return vbox


func _thread_row(thread_id: String) -> Button:
	var t: Dictionary = _threads[thread_id]
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 64)
	btn.pressed.connect(_show_thread.bind(thread_id))
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn.add_child(hbox)

	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(46, 46)
	var initial := "?" if thread_id == "unknown" else String(t["name"]).left(1)
	avatar.add_theme_stylebox_override("panel", _rounded(Color(0.35, 0.35, 0.38), 23))
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ac := CenterContainer.new()
	ac.set_anchors_preset(Control.PRESET_FULL_RECT)
	ac.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ac.add_child(_label(initial, 20, Color.WHITE))
	avatar.add_child(ac)
	hbox.add_child(avatar)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(mid)
	mid.add_child(_label(String(t["name"]), 17, _TEXT_COLOR))
	var msgs: Array = t["messages"]
	var preview_text := ""
	var preview_time := ""
	if not msgs.is_empty():
		var last: Dictionary = msgs[msgs.size() - 1]
		preview_text = String(last["text"])
		preview_time = String(last.get("time", ""))
	var preview := _label(preview_text, 14, _DIM_COLOR)
	preview.clip_text = true
	mid.add_child(preview)

	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(right)
	right.add_child(_label(preview_time, 12, _DIM_COLOR, HORIZONTAL_ALIGNMENT_RIGHT))
	var unread := int(t.get("unread", 0))
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(22, 22)
	badge.add_theme_stylebox_override("panel", _rounded(_ACCENT, 11))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bc := CenterContainer.new()
	bc.set_anchors_preset(Control.PRESET_FULL_RECT)
	bc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bc.add_child(_label(str(unread), 13, Color.WHITE))
	badge.add_child(bc)
	badge.visible = unread > 0
	right.add_child(badge)
	return btn


func _build_convo_view() -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.visible = false
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := Button.new()
	back.text = "‹ Messages"
	back.flat = true
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_size_override("font_size", 16)
	back.add_theme_color_override("font_color", _ACCENT)
	back.pressed.connect(_show_list)
	header.add_child(back)
	_convo_name = _label("", 17, _TEXT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_convo_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_convo_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_convo_name)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(84, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)
	vbox.add_child(header)

	_convo_scroll = ScrollContainer.new()
	_convo_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_convo_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_convo_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_convo_scroll)
	_convo_msgs = VBoxContainer.new()
	_convo_msgs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_convo_msgs.add_theme_constant_override("separation", 8)
	_convo_msgs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_convo_scroll.add_child(_convo_msgs)

	# Scripted quick-reply (hidden unless set_quick_reply was called for the
	# open thread). Lets Mara send one canned text, e.g. to Mom.
	_quick_reply_btn = Button.new()
	_quick_reply_btn.focus_mode = Control.FOCUS_NONE
	_quick_reply_btn.add_theme_font_size_override("font_size", 16)
	_quick_reply_btn.add_theme_color_override("font_color", Color.WHITE)
	_quick_reply_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	_quick_reply_btn.add_theme_stylebox_override("normal", _rounded(_ACCENT, 14))
	_quick_reply_btn.add_theme_stylebox_override("hover", _rounded(Color(0.1, 0.6, 1.0), 14))
	_quick_reply_btn.add_theme_stylebox_override("pressed", _rounded(Color(0.03, 0.42, 0.85), 14))
	_quick_reply_btn.custom_minimum_size = Vector2(0, 44)
	_quick_reply_btn.visible = false
	_quick_reply_btn.pressed.connect(_on_quick_reply_pressed)
	vbox.add_child(_quick_reply_btn)

	var hint := _label("Mara doesn't reply — she just reads.", 12, _DIM_COLOR,
		HORIZONTAL_ALIGNMENT_CENTER)
	_convo_hint = hint
	var hintpad := MarginContainer.new()
	hintpad.add_theme_constant_override("margin_top", 6)
	hintpad.add_theme_constant_override("margin_bottom", 8)
	hintpad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hintpad.add_child(hint)
	vbox.add_child(hintpad)
	return vbox


func _message_row(msg: Dictionary) -> VBoxContainer:
	var outgoing := String(msg.get("from", "them")) == "me"
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if outgoing:
		margin.add_theme_constant_override("margin_left", 70)
	else:
		margin.add_theme_constant_override("margin_right", 70)
	row.add_child(margin)

	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel",
		_rounded(_BUBBLE_OUT if outgoing else _BUBBLE_IN, 16))
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(bubble)

	var bpad := MarginContainer.new()
	bpad.add_theme_constant_override("margin_left", 12)
	bpad.add_theme_constant_override("margin_right", 12)
	bpad.add_theme_constant_override("margin_top", 8)
	bpad.add_theme_constant_override("margin_bottom", 8)
	bpad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(bpad)

	var text := _label(String(msg.get("text", "")), 16, Color.WHITE)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bpad.add_child(text)

	var time := _label(String(msg.get("time", "")), 11, _DIM_COLOR,
		HORIZONTAL_ALIGNMENT_RIGHT if outgoing else HORIZONTAL_ALIGNMENT_LEFT)
	row.add_child(time)
	return row


# ------------------------------------------------------------------
# Checklist tab
# ------------------------------------------------------------------

func _build_checklist_view() -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.visible = false
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var header := _label("Checklist", 30, _TEXT_COLOR)
	var hpad := MarginContainer.new()
	hpad.add_theme_constant_override("margin_left", 14)
	hpad.add_theme_constant_override("margin_top", 6)
	hpad.add_theme_constant_override("margin_bottom", 8)
	hpad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hpad.add_child(header)
	vbox.add_child(hpad)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_checklist_rows = VBoxContainer.new()
	_checklist_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_checklist_rows.add_theme_constant_override("separation", 16)
	_checklist_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rpad := MarginContainer.new()
	rpad.add_theme_constant_override("margin_left", 14)
	rpad.add_theme_constant_override("margin_right", 14)
	rpad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rpad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rpad.add_child(_checklist_rows)
	scroll.add_child(rpad)
	return vbox


## One checklist row: colored status dot + label. No emoji (font-safe).
func _checklist_row(item: Dictionary) -> Control:
	var state := String(item.get("state", "locked"))
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := PanelContainer.new()
	dot.custom_minimum_size = Vector2(20, 20)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dot_color := Color(0.35, 0.35, 0.38)
	if state == "done":
		dot_color = Color(0.2, 0.78, 0.35)
	elif state == "current":
		dot_color = Color(0.25, 0.62, 1.0)
	dot.add_theme_stylebox_override("panel", _rounded(dot_color, 10))
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(dot)
	var label_color := _DIM_COLOR if state == "locked" else _TEXT_COLOR
	var lab := _label(String(item.get("label", "")), 17, label_color)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hbox.add_child(lab)
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_top", 4)
	wrap.add_theme_constant_override("margin_bottom", 4)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(hbox)
	return wrap


func _render_checklist() -> void:
	for child in _checklist_rows.get_children():
		child.queue_free()
	for item in _checklist:
		_checklist_rows.add_child(_checklist_row(item as Dictionary))


func _tab_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 38)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 15)
	return btn


func _build_tab_bar() -> Control:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 2)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_messages = _tab_button("Messages")
	_tab_messages.pressed.connect(_show_messages_tab)
	bar.add_child(_tab_messages)
	_tab_checklist = _tab_button("Checklist")
	_tab_checklist.pressed.connect(_show_checklist)
	bar.add_child(_tab_checklist)
	pad.add_child(bar)
	_set_active_tab("messages")
	return pad


func _set_active_tab(name: String) -> void:
	_tab_messages.add_theme_color_override("font_color", _DIM_COLOR)
	_tab_checklist.add_theme_color_override("font_color", _DIM_COLOR)
	if name == "checklist":
		_tab_checklist.add_theme_color_override("font_color", _ACCENT)
	else:
		_tab_messages.add_theme_color_override("font_color", _ACCENT)


func _show_messages_tab() -> void:
	_show_list()


# ------------------------------------------------------------------
# Rendering
# ------------------------------------------------------------------

func _render_thread_list() -> void:
	for child in _list_rows.get_children():
		child.queue_free()
	for thread_id in _order:
		_list_rows.add_child(_thread_row(String(thread_id)))


func _render_conversation(thread_id: String) -> void:
	for child in _convo_msgs.get_children():
		child.queue_free()
	var t: Dictionary = _threads[thread_id]
	for msg in t["messages"]:
		_convo_msgs.add_child(_message_row(msg))
	# Scripted quick-reply, if one is armed for this thread.
	if _quick_reply_thread == thread_id and _quick_reply_text != "":
		_quick_reply_btn.text = "Send: \"%s\"" % _quick_reply_text
		_quick_reply_btn.visible = true
		_convo_hint.visible = false
	else:
		_quick_reply_btn.visible = false
		_convo_hint.visible = true
	_scroll_to_bottom.call_deferred()


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var bar := _convo_scroll.get_v_scroll_bar()
	if bar:
		_convo_scroll.scroll_vertical = int(bar.max_value)


func _show_list() -> void:
	_current_thread = ""
	_convo_view.visible = false
	_checklist_view.visible = false
	_render_thread_list()
	_list_view.visible = true
	_set_active_tab("messages")


func _show_thread(thread_id: String) -> void:
	if not _threads.has(thread_id):
		return
	_current_thread = thread_id
	(_threads[thread_id] as Dictionary)["unread"] = 0
	_convo_name.text = String((_threads[thread_id] as Dictionary)["name"])
	_list_view.visible = false
	_checklist_view.visible = false
	_convo_view.visible = true
	_set_active_tab("messages")
	_render_conversation(thread_id)


func _show_checklist() -> void:
	_current_thread = ""
	_list_view.visible = false
	_convo_view.visible = false
	_render_checklist()
	_checklist_view.visible = true
	_set_active_tab("checklist")


# ------------------------------------------------------------------
# Public API (driven by the GameManager)
# ------------------------------------------------------------------

func load_threads(data: Dictionary) -> void:
	_threads.clear()
	_order.clear()
	for thread_id in data.keys():
		var src: Dictionary = data[thread_id]
		_threads[thread_id] = {
			"name": String(src.get("name", thread_id)),
			"number": String(src.get("number", "")),
			"messages": (src.get("messages", []) as Array).duplicate(true),
			"unread": 0,
		}
		_order.append(thread_id)
	_clock_label.text = _clock_string()
	_render_thread_list()


func receive_text(thread_id: String, text: String) -> void:
	if not _threads.has(thread_id):
		push_warning("PhoneUI: unknown thread '%s'." % thread_id)
		return
	var t: Dictionary = _threads[thread_id]
	(t["messages"] as Array).append({"from": "them", "text": text, "time": _clock_string()})
	if _open and _current_thread == thread_id:
		_render_conversation(thread_id)
	else:
		t["unread"] = int(t["unread"]) + 1
		if _open:
			_render_thread_list()
		_queue_banner(thread_id, text)


func send_text(thread_id: String, text: String) -> void:
	if not _threads.has(thread_id):
		push_warning("PhoneUI: unknown thread '%s'." % thread_id)
		return
	var t: Dictionary = _threads[thread_id]
	(t["messages"] as Array).append({"from": "me", "text": text, "time": _clock_string()})
	if _open and _current_thread == thread_id:
		_render_conversation(thread_id)
	elif _open:
		_render_thread_list()


func advance_clock() -> void:
	_minutes += 1
	_clock_label.text = _clock_string()


func is_open() -> bool:
	return _open


func open(view: String = "messages", thread_id: String = "") -> void:
	_open = true
	_phone_body.visible = true
	# NOTE: animate offset_top, not position.y — with bottom anchors,
	# position.y reports the absolute screen position, not the anchor offset.
	_phone_body.offset_top = 220.0
	if view == "checklist":
		_show_checklist()
	elif thread_id != "":
		_show_thread(thread_id)
	else:
		_show_list()
	var tw := create_tween()
	tw.tween_property(_phone_body, "offset_top", _home_y, 0.35)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func close() -> void:
	_open = false
	var tw := create_tween()
	tw.tween_property(_phone_body, "offset_top", 220.0, 0.3)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(_phone_body.hide)


func unread_count(thread_id: String) -> int:
	if not _threads.has(thread_id):
		return 0
	return int((_threads[thread_id] as Dictionary).get("unread", 0))


## Checklist tab. Each item: {"id", "label", "state"} with state in
## "done" / "current" / "locked". Driven by the GameManager.
func set_checklist(items: Array) -> void:
	_checklist = items
	if _checklist_view != null and _checklist_view.visible:
		_render_checklist()


func is_on_checklist() -> bool:
	return _checklist_view != null and _checklist_view.visible


## Arms a one-tap canned reply inside a conversation (e.g. texting Mom).
## The GameManager sends the actual text on quick_reply_tapped.
func set_quick_reply(thread_id: String, text: String) -> void:
	_quick_reply_thread = thread_id
	_quick_reply_text = text
	if _open and _current_thread == thread_id:
		_render_conversation(thread_id)


func clear_quick_reply() -> void:
	_quick_reply_thread = ""
	_quick_reply_text = ""
	if _quick_reply_btn != null:
		_quick_reply_btn.visible = false
	if _convo_hint != null:
		_convo_hint.visible = true


func _on_quick_reply_pressed() -> void:
	if _quick_reply_thread != "" and _quick_reply_text != "":
		quick_reply_tapped.emit(_quick_reply_thread, _quick_reply_text)


# ------------------------------------------------------------------
# Banner
# ------------------------------------------------------------------

func _queue_banner(thread_id: String, text: String) -> void:
	_banner_queue.append({"thread": thread_id, "text": text})
	if not _banner_showing:
		_pump_banner()


func _pump_banner() -> void:
	if _banner_queue.is_empty():
		_banner_showing = false
		return
	_banner_showing = true
	var b: Dictionary = _banner_queue.pop_front()
	var t: Dictionary = _threads[b["thread"]]
	_banner_title.text = "MESSAGES · " + String(t["name"]).to_upper()
	_banner_preview.text = String(b["text"])
	_banner.visible = true
	var tw := create_tween()
	tw.tween_property(_banner, "position:y", 12.0, 0.35)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(4.0).timeout
	var tw2 := create_tween()
	tw2.tween_property(_banner, "position:y", -130.0, 0.3)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw2.finished
	_banner.visible = false
	_pump_banner()


# ------------------------------------------------------------------
# Clock
# ------------------------------------------------------------------

func _clock_string() -> String:
	var h := (_minutes / 60) % 24
	var m := _minutes % 60
	var suffix := "AM" if h < 12 else "PM"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, m, suffix]
