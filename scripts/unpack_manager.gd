class_name UnpackManager
extends Node
## Core opening gameplay: unpacking moving boxes (3-5 minutes).
##
## Five boxes in the foyer/living room: four labeled (KITCHEN, BOOKS,
## BEDROOM, BATH) with 3 items each, plus one UNMARKED box that only opens
## after the other four are empty. E takes the next item from a box (it
## rides in hand, bottom-right of the camera, with a walk bob); glowing
## zone markers show where the carried item goes; E at a valid zone snaps
## it into place with a *ding*. Zones are spread across the whole house,
## so unpacking teaches the layout. No timers, no fail states.
##
## The unmarked box holds a note reading "welcome home, mara". Taking it
## fires the stalker text ("i know you're home") and `completed`, which
## the GameManager uses to advance the post-intro flow (optional chores).
##
## The GameManager routes unpack interactables here (ids "unpack_*",
## "uzone_*"). Boxes start disabled; start() enables them.

signal changed  # progress changed (GameManager refreshes the objective)
signal completed  # the note was taken; the opening is done

const TOTAL := 12

# [item_id, display name, box_id, mesh kind, zone_id, final slot]
const ITEMS: Array = [
	["mug", "mug", "unpack_box_kitchen", "mug", "uzone_kitchen_sill", Vector3(6.95, 1.05, -2.3)],
	["bowl", "bowl", "unpack_box_kitchen", "bowl", "uzone_kitchen_sill", Vector3(6.95, 1.05, -1.7)],
	["pot", "pot", "unpack_box_kitchen", "pot", "uzone_kitchen_stove", Vector3(6.6, 0.9, -4.62)],
	["books", "books", "unpack_box_books", "books", "uzone_living_shelf", Vector3(-6.7, 1.2, -1.5)],
	["frame", "photo frame", "unpack_box_books", "frame", "uzone_living_sill_south", Vector3(-1.9, 1.14, 4.95)],
	["plant", "plant", "unpack_box_books", "plant", "uzone_living_sill_west", Vector3(-6.9, 1.14, 1.0)],
	["lamp", "lamp", "unpack_box_bedroom", "lamp", "uzone_bed_nightstand", Vector3(4.18, 3.25, -4.5)],
	["clock", "alarm clock", "unpack_box_bedroom", "clock", "uzone_bed_nightstand", Vector3(4.45, 3.25, -4.32)],
	["clothes", "folded clothes", "unpack_box_bedroom", "clothes", "uzone_bed_bed", Vector3(5.5, 3.32, -2.2)],
	["towel", "towel", "unpack_box_bath", "towel", "uzone_bath_tub", Vector3(-4.0, 3.25, -2.0)],
	["soap", "soap", "unpack_box_bath", "soap", "uzone_bath_sink", Vector3(-6.3, 3.56, -4.35)],
	["tp", "toilet paper", "unpack_box_bath", "tp", "uzone_bath_toilet", Vector3(-5.2, 3.6, -4.75)],
]

const NORMAL_BOXES: Array = [
	"unpack_box_kitchen",
	"unpack_box_books",
	"unpack_box_bedroom",
	"unpack_box_bath",
]
const PLAIN_BOX := "unpack_box_plain"

var _started := false
var _finished := false
var _done := 0
var _carrying := ""  # item id currently in hand, "" = empty-handed
var _remaining: Dictionary = {}  # box_id -> Array of item ids, in take order
var _items_by_id: Dictionary = {}  # item_id -> item Dictionary
var _placed: Array = []  # item ids already put away, in place order
var _opened: Array = []  # box ids whose lids have been opened
var _carry_bob := 0.0
var _carry_base_y := -0.3

var _player: PlayerController
var _ui: DialogueUI
var _apt: ApartmentBuilder
var _phone: PhoneUI
var _audio: AudioManager

var _carry_mesh: Node3D = null


func setup(player: PlayerController, ui: DialogueUI, apt: ApartmentBuilder, phone: PhoneUI, audio: AudioManager) -> void:
	_player = player
	_ui = ui
	_apt = apt
	_phone = phone
	_audio = audio
	for it in ITEMS:
		var d := {
			"id": String(it[0]), "name": String(it[1]), "box": String(it[2]),
			"kind": String(it[3]), "zone": String(it[4]),
		}
		var slot: Vector3 = it[5]
		d["slot"] = slot
		_items_by_id[d["id"]] = d
		if not _remaining.has(d["box"]):
			_remaining[d["box"]] = []
		(_remaining[d["box"]] as Array).append(d["id"])


## Begins the opening: the four labeled boxes become usable.
func start() -> void:
	if _started:
		return
	_started = true
	_set_boxes_enabled(true)
	changed.emit()


func is_started() -> bool:
	return _started


func is_finished() -> bool:
	return _finished


func get_done() -> int:
	return _done


func get_carried() -> String:
	return _carrying


## Zone id the carried item belongs to ("" when empty-handed).
func get_carried_zone() -> String:
	if _carrying == "":
		return ""
	return String((_items_by_id[_carrying] as Dictionary)["zone"])


# ------------------------------------------------------------------
# Interactable routing (called by the GameManager)
# ------------------------------------------------------------------

func interact(interact_id: String) -> void:
	if _finished or not _started:
		return
	if interact_id == PLAIN_BOX:
		_take_note()
	elif String(interact_id).begins_with("unpack_box_"):
		_take_from_box(interact_id)
	elif String(interact_id).begins_with("uzone_"):
		_place_at_zone(interact_id)


func _take_from_box(box_id: String) -> void:
	if _carrying != "":
		return
	var remaining: Array = _remaining.get(box_id, [])
	if remaining.is_empty():
		return
	_apt.open_unpack_box(box_id)
	if not _opened.has(box_id):
		_opened.append(box_id)
	var item_id := String(remaining.pop_front())
	var item: Dictionary = _items_by_id[item_id]
	_carrying = item_id
	_audio.play_sfx("unpack")
	_carry_mesh = _apt.make_unpack_item_mesh(String(item["kind"]))
	_carry_mesh.scale = Vector3.ONE * 0.8
	_carry_base_y = -0.3
	_carry_mesh.position = Vector3(0.32, _carry_base_y, -0.55)
	_player.camera.add_child(_carry_mesh)
	# While carrying, only the item's zone is a valid target.
	_set_boxes_enabled(false)
	_set_zone(String(item["zone"]), true, "Place the %s" % String(item["name"]))
	_apt.set_unpack_zones([String(item["zone"])])
	changed.emit()


func _place_at_zone(zone_id: String) -> void:
	if _carrying == "":
		return
	var item: Dictionary = _items_by_id[_carrying]
	if String(item["zone"]) != zone_id:
		return
	_done += 1
	_placed.append(_carrying)
	_free_carry_mesh()
	var slot: Vector3 = item["slot"]
	var node := _apt.spawn_unpack_prop(String(item["kind"]), slot)
	node.scale = Vector3.ONE * 0.4
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_audio.play_sfx("ding")
	_carrying = ""
	_set_zone(zone_id, false, "")
	_apt.hide_unpack_zones()
	if _done >= TOTAL:
		# All four labeled boxes are empty: the unmarked box can be opened.
		_set_interactable(PLAIN_BOX, true)
		_ui.show_toast("One box left. That one wasn't on the truck.")
		_audio.play_sfx("paper")
	else:
		_set_boxes_enabled(true)
	changed.emit()


func _take_note() -> void:
	if _finished or _carrying != "":
		return
	_finished = true
	_apt.open_unpack_box(PLAIN_BOX)
	if not _opened.has(PLAIN_BOX):
		_opened.append(PLAIN_BOX)
	_audio.play_sfx("paper")
	# The note, held up to read.
	_carry_mesh = _apt.make_unpack_item_mesh("note")
	_carry_mesh.scale = Vector3.ONE * 0.9
	_carry_base_y = -0.26
	_carry_mesh.position = Vector3(0.28, _carry_base_y, -0.5)
	_carry_mesh.rotation.x = -0.45
	_player.camera.add_child(_carry_mesh)
	_set_interactable(PLAIN_BOX, false)
	_set_boxes_enabled(false)
	_apt.hide_unpack_zones()
	# Horror payoff: the stalker texts the moment she reads it.
	_phone.receive_text("unknown", "i know you're home")
	_audio.play_sfx("text_buzz")
	_ui.show_toast("\u201cwelcome home, mara\u201d")
	changed.emit()
	completed.emit()
	# The note lowers out of view after a moment.
	await get_tree().create_timer(6.0).timeout
	if is_instance_valid(_carry_mesh):
		var tw := create_tween()
		tw.tween_property(_carry_mesh, "scale", Vector3.ZERO, 0.8)
		tw.tween_callback(_carry_mesh.queue_free)
		_carry_mesh = null


func _free_carry_mesh() -> void:
	if _carry_mesh != null and is_instance_valid(_carry_mesh):
		_carry_mesh.queue_free()
	_carry_mesh = null


func _process(delta: float) -> void:
	if _carry_mesh != null and is_instance_valid(_carry_mesh):
		_carry_bob += delta
		_carry_mesh.position.y = _carry_base_y + sin(_carry_bob * 7.0) * 0.012


# ------------------------------------------------------------------
# Save/load support. A carried item is put back into its box (never
# restored in-hand).
# ------------------------------------------------------------------

func serialize() -> Dictionary:
	var rem := {}
	for box_id in _remaining.keys():
		rem[box_id] = (_remaining[box_id] as Array).duplicate()
	return {
		"started": _started,
		"finished": _finished,
		"done": _done,
		"carrying": _carrying,
		"remaining": rem,
		"placed": _placed.duplicate(),
		"opened": _opened.duplicate(),
	}


func deserialize(d: Dictionary) -> void:
	_free_carry_mesh()
	_carrying = ""
	_started = bool(d.get("started", false))
	_finished = bool(d.get("finished", false))
	_done = int(d.get("done", 0))
	_remaining.clear()
	var rem: Dictionary = d.get("remaining", {})
	for box_id in rem.keys():
		var arr: Array = []
		for iid in rem[box_id]:
			arr.append(str(iid))
		_remaining[String(box_id)] = arr
	# A carried item goes back into its box.
	var carry_id := String(d.get("carrying", ""))
	if carry_id != "" and _items_by_id.has(carry_id):
		var box := String((_items_by_id[carry_id] as Dictionary)["box"])
		if _remaining.has(box):
			(_remaining[box] as Array).push_front(carry_id)
	# Rebuild placed props and opened lids.
	_placed.clear()
	for iid in d.get("placed", []):
		var sid := str(iid)
		if _items_by_id.has(sid):
			var item: Dictionary = _items_by_id[sid]
			_apt.spawn_unpack_prop(String(item["kind"]), item["slot"])
			_placed.append(sid)
	_opened.clear()
	for box_id in d.get("opened", []):
		var bid := String(box_id)
		_apt.open_unpack_box(bid)
		_opened.append(bid)
	# Restore hotspot states.
	_apt.hide_unpack_zones()
	if _finished:
		_set_boxes_enabled(false)
		_set_interactable(PLAIN_BOX, false)
	elif _started:
		_set_boxes_enabled(true)
		_set_interactable(PLAIN_BOX, _done >= TOTAL)
	else:
		_set_boxes_enabled(false)
		_set_interactable(PLAIN_BOX, false)
	changed.emit()


# ------------------------------------------------------------------
# Interactable plumbing
# ------------------------------------------------------------------

## Enables only boxes that still hold items (or all off).
func _set_boxes_enabled(enabled: bool) -> void:
	for box_id in NORMAL_BOXES:
		var remaining: Array = _remaining.get(box_id, [])
		_set_interactable(box_id, enabled and not remaining.is_empty())


func _set_zone(zone_id: String, enabled: bool, prompt: String) -> void:
	for n in get_tree().get_nodes_in_group("interactable"):
		var inter := n as Interactable
		if inter != null and inter.interact_id == zone_id:
			if prompt != "":
				inter.prompt = prompt
			if enabled:
				inter.enable()
			else:
				inter.disable()
			return


func _set_interactable(interact_id: String, enabled: bool) -> void:
	for n in get_tree().get_nodes_in_group("interactable"):
		var inter := n as Interactable
		if inter != null and inter.interact_id == interact_id:
			if enabled:
				inter.enable()
			else:
				inter.disable()
			return
