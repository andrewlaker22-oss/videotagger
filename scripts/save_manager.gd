class_name SaveManager
extends Node
## Manual save slots: user://save_slot_1..3.json.
##
## Handles file IO and validation only. The GameManager builds the payload
## (GameManager._collect_save_data) and applies it (GameManager._apply_save_data);
## each gameplay manager owns its own serialize()/deserialize().

const SLOT_COUNT := 3
const SAVE_VERSION := 1


static func slot_path(slot: int) -> String:
	return "user://save_slot_%d.json" % slot


## "empty" | "ok" | "corrupt"
func slot_state(slot: int) -> String:
	if not FileAccess.file_exists(slot_path(slot)):
		return "empty"
	return "ok" if not read_slot(slot).is_empty() else "corrupt"


## One-line label for the slot buttons: "Slot 1" + timestamp/objective.
func slot_summary(slot: int) -> String:
	match slot_state(slot):
		"ok":
			var d := read_slot(slot)
			var obj := String(d.get("objective", ""))
			if obj == "":
				obj = "Exploring"
			return "%s · %s" % [String(d.get("saved_at", "?")), obj]
		"corrupt":
			return "Corrupted"
		_:
			return "Empty"


func write_slot(slot: int, payload: Dictionary) -> bool:
	var txt := JSON.stringify(payload)
	if txt == "":
		push_error("SaveManager: payload did not stringify.")
		return false
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot write %s." % slot_path(slot))
		return false
	f.store_string(txt)
	f.close()
	return true


## Validated payload, or {} when the slot is missing or corrupt.
func read_slot(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return {}
	var d: Dictionary = parsed
	if int(d.get("version", 0)) != SAVE_VERSION:
		return {}
	if not d.has("flags") or not d.has("player"):
		return {}
	return d
