class_name ApartmentBuilder
extends Node3D
## Procedurally builds the WATCHED house from data tables.
##
## All geometry is primitives (boxes, quads) with dark, moody materials —
## pure placeholder art. Nothing here is load-bearing for the story: the
## GameManager only calls open_front_door(), set_blackout(),
## stutter_power() and disable_all_interactables(). To replace placeholders
## with real art, see assets/README.md.
##
## Floor plan (meters, XZ plane, y-up). House: x in [-7, 7], z in [-5, 5].
## Three stories, 2.7 m each: basement floor at y=-2.7, ground at y=0,
## upper at y=2.7, roof slab at y=5.4.
##
## GROUND: porch + foyer (front door in south wall), living room (west, TV),
##   kitchen (east), stair hall (both staircases).
## UPPER: hall, bedroom (east, photo + closet), bathroom (north-west, mirror),
##   open landing (south).
## BASEMENT: open dim space, storage boxes, breaker box on the east wall.
##
## Stairs are visual steps (no collision) plus ONE sloped ramp StaticBody3D
## each, gentle enough (~29 deg) for the CharacterBody3D player to walk.

const WALL_H := 2.7
const WALL_T := 0.18

const BASE_Y := -2.7
const GROUND_Y := 0.0
const UPPER_Y := 2.7

# Wall segments as [Vector2, Vector2, y_base] in the XZ plane. Door gaps are
# made by splitting a wall into two segments; see the plan above.
const WALLS: Array = [
	# ---- GROUND FLOOR (y0 = 0).
	# North wall (z=-5): back-door gap x in [4.0, 5.2].
	[Vector2(-7, -5), Vector2(4.0, -5), GROUND_Y],
	[Vector2(5.2, -5), Vector2(7, -5), GROUND_Y],
	# South wall (z=5): front-door gap x in [0.2, 1.4]; window gaps
	# x in [-2.5, -1.3] and [3.1, 4.3].
	[Vector2(-7, 5), Vector2(-2.5, 5), GROUND_Y],
	[Vector2(-1.3, 5), Vector2(0.2, 5), GROUND_Y],
	[Vector2(1.4, 5), Vector2(3.1, 5), GROUND_Y],
	[Vector2(4.3, 5), Vector2(7, 5), GROUND_Y],
	# West wall (x=-7): window gaps z in [-3.6, -2.4] and [0.4, 1.6].
	[Vector2(-7, -5), Vector2(-7, -3.6), GROUND_Y],
	[Vector2(-7, -2.4), Vector2(-7, 0.4), GROUND_Y],
	[Vector2(-7, 1.6), Vector2(-7, 5), GROUND_Y],
	# East wall (x=7): window gap z in [-2.6, -1.4].
	[Vector2(7, -5), Vector2(7, -2.6), GROUND_Y],
	[Vector2(7, -1.4), Vector2(7, 5), GROUND_Y],
	# x=-1 (living | stair hall + foyer). Wide opening z in [0, 2].
	[Vector2(-1, -5), Vector2(-1, 0), GROUND_Y],
	[Vector2(-1, 2), Vector2(-1, 5), GROUND_Y],
	# x=2.5 (hall/foyer | kitchen). Kitchen door z in [-0.6, 0.6].
	[Vector2(2.5, -5), Vector2(2.5, -0.6), GROUND_Y],
	[Vector2(2.5, 0.6), Vector2(2.5, 5), GROUND_Y],
	# z=1 (foyer | stair hall). Opening x in [-0.8, 2.0].
	[Vector2(-1, 1), Vector2(-0.8, 1), GROUND_Y],
	[Vector2(2.0, 1), Vector2(2.5, 1), GROUND_Y],
	# ---- UPPER FLOOR (y0 = 2.7).
	# North wall (z=-5): frosted bathroom window gap x in [-5.0, -3.8].
	[Vector2(-7, -5), Vector2(-5.0, -5), UPPER_Y],
	[Vector2(-3.8, -5), Vector2(7, -5), UPPER_Y],
	[Vector2(-7, 5), Vector2(7, 5), UPPER_Y],
	[Vector2(-7, -5), Vector2(-7, 5), UPPER_Y],
	# East wall (x=7): bedroom window gap z in [-3.1, -1.9].
	[Vector2(7, -5), Vector2(7, -3.1), UPPER_Y],
	[Vector2(7, -1.9), Vector2(7, 5), UPPER_Y],
	# x=-1 (landing | upper hall). Opening z in [-0.5, 0.5].
	[Vector2(-1, -5), Vector2(-1, -0.5), UPPER_Y],
	[Vector2(-1, 0.5), Vector2(-1, 1), UPPER_Y],
	# x=2.5 (hall | bedroom). Bedroom door z in [-0.6, 0.6].
	[Vector2(2.5, -5), Vector2(2.5, -0.6), UPPER_Y],
	[Vector2(2.5, 0.6), Vector2(2.5, 1), UPPER_Y],
	# z=1 (hall | landing). Opening x in [-0.8, 2.0].
	[Vector2(-1, 1), Vector2(-0.8, 1), UPPER_Y],
	[Vector2(2.0, 1), Vector2(2.5, 1), UPPER_Y],
	# z=1 (bedroom | landing).
	[Vector2(2.5, 1), Vector2(7, 1), UPPER_Y],
	# Bathroom (x in [-7, -3.5], z in [-5, -1]). Door in east wall, z in [-3.2, -2.2].
	[Vector2(-3.5, -5), Vector2(-3.5, -3.2), UPPER_Y],
	[Vector2(-3.5, -2.2), Vector2(-3.5, -1), UPPER_Y],
	[Vector2(-7, -1), Vector2(-3.5, -1), UPPER_Y],
	# ---- BASEMENT (y0 = -2.7). Open plan: outer shell only.
	[Vector2(-7, -5), Vector2(7, -5), BASE_Y],
	[Vector2(-7, 5), Vector2(7, 5), BASE_Y],
	[Vector2(-7, -5), Vector2(-7, 5), BASE_Y],
	[Vector2(7, -5), Vector2(7, 5), BASE_Y],
]

var _mats: Dictionary = {}
var _lights: Array = []  # Dictionaries: {node, base, mode, phase}.
var _blackout: bool = false
var _stutter_until: float = 0.0
var _door_pivot: Node3D = null
var _door_open: bool = false
var _doors: Dictionary = {}  # door_id -> {pivot, open, open_angle, interactable}.
var _trash_bag_nodes: Dictionary = {}  # bag_id -> Array of prop nodes.
var _dish_plates: Array = []  # dirty dish bodies, in wash order.
var _rack_slots: Array = []  # Vector3 slots in the drying rack.
var _flicker: Dictionary = {}  # light index -> {"until": float} (horror flicker).
var _unpack_lids: Dictionary = {}  # box_id -> lid StaticBody3D (hidden on open).
var _unpack_markers: Dictionary = {}  # zone_id -> glowing marker MeshInstance3D.
var _unpack_marker_mat: StandardMaterial3D  # shared pulsing emission material.
var _hide_closets: Dictionary = {}  # spot_id -> {node, pivot, hotspot}.


func _ready() -> void:
	_make_materials()
	_build_shell()
	_build_stairs()
	_build_porch()
	_build_foyer()
	_build_living_room()
	_build_kitchen()
	_build_bedroom()
	_build_bathroom()
	_build_landing()
	_build_basement()
	_build_hide_closets()
	_build_front_door()
	_build_doors()
	_build_windows()
	_build_backyard()
	_build_interactables()
	_build_chores()
	_build_unpack()
	_build_lights()


func _process(delta: float) -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	if _stutter_until > 0.0 and t >= _stutter_until:
		_stutter_until = 0.0
		_blackout = true
	var stuttering := _stutter_until > 0.0
	for i in _lights.size():
		var entry: Dictionary = _lights[i]
		var l: OmniLight3D = entry["node"]
		if _blackout:
			l.light_energy = maxf(0.0, l.light_energy - delta * 6.0)
			continue
		var base: float = entry["base"]
		var phase: float = entry["phase"]
		var e := base
		# Temporary horror flicker (see flicker_near): force "dying" mode.
		var mode := String(entry["mode"])
		if _flicker.has(i):
			if t < float((_flicker[i] as Dictionary)["until"]):
				mode = "dying"
			else:
				_flicker.erase(i)
		if stuttering:
			# Power gasps back for a heartbeat: violent flicker, then it dies.
			e = base * (0.15 + 0.85 * absf(sin(t * 27.0 + phase * 3.1)))
			if fmod(t * 7.0 + phase, 1.0) < 0.12:
				e *= 0.1
		else:
			match mode:
				"steady":
					e = base * (0.95 + 0.05 * sin(t * 11.0 + phase))
				"buzz":
					e = base * (0.92 + 0.08 * sin(t * 43.0 + phase))
					if fmod(t * 3.1 + phase, 1.0) < 0.05:
						e *= 0.25
				"dying":
					e = base * (0.55 + 0.45 * sin(t * 1.7 + phase))
					if sin(t * 8.3 + phase * 2.7) > 0.93:
						e *= 0.08
		l.light_energy = e
	# Pulse the unpacking zone markers (shared emissive material).
	if _unpack_marker_mat != null:
		_unpack_marker_mat.emission_energy_multiplier = 1.2 + 0.8 * sin(t * 5.0)


# ------------------------------------------------------------------
# Public API used by the GameManager
# ------------------------------------------------------------------

func open_front_door() -> void:
	if _door_open or _door_pivot == null:
		return
	_door_open = true
	var tw := create_tween()
	tw.tween_property(_door_pivot, "rotation:y", 1.85, 1.6).set_trans(Tween.TRANS_SINE)


## Swings the front door shut again (used when Mara locks up).
func close_front_door() -> void:
	if _door_pivot == null:
		return
	_door_open = false
	var tw := create_tween()
	tw.tween_property(_door_pivot, "rotation:y", 0.15, 1.2).set_trans(Tween.TRANS_SINE)


func set_blackout(value: bool) -> void:
	_blackout = value


## Briefly restores power with a violent flicker, then kills it again.
## Used by the breaker beat.
func stutter_power(duration: float = 1.6) -> void:
	_blackout = false
	_stutter_until = Time.get_ticks_msec() / 1000.0 + duration


## Makes lights near `pos` flicker hard for `duration` seconds, then restores
## their normal mode. Used for the dish-washing horror beat.
func flicker_near(pos: Vector3, radius: float, duration: float = 1.5) -> void:
	var until: float = Time.get_ticks_msec() / 1000.0 + duration
	for i in _lights.size():
		var entry: Dictionary = _lights[i]
		var l: OmniLight3D = entry["node"]
		if l.position.distance_to(pos) <= radius and not _flicker.has(i):
			_flicker[i] = {"until": until}


func disable_all_interactables() -> void:
	for child in get_children():
		if child is Interactable:
			var inter := child as Interactable
			# The breaker box must stay usable: the breaker beat needs it
			# AFTER the blackout disables everything else. Mechanical doors
			# also stay usable (they are not story beats). Chore hotspots
			# (trash_*, sink) persist too — chores never block the story.
			if inter.interact_id == "breaker_box":
				continue
			if String(inter.interact_id).begins_with("door_"):
				continue
			if String(inter.interact_id).begins_with("trash_"):
				continue
			if inter.interact_id == "sink":
				continue
			# Unpacking hotspots (unpack_*, uzone_*) persist too — the opening
			# gameplay never blocks the story, and its state survives beats.
			if String(inter.interact_id).begins_with("unpack_"):
				continue
			if String(inter.interact_id).begins_with("uzone_"):
				continue
			# The front-door lock persists too — the checklist survives beats.
			if inter.interact_id == "front_door_lock":
				continue
			# Hiding spots stay usable in the dark — that is when they matter.
			if String(inter.interact_id).begins_with("hide_"):
				continue
			inter.disable()


## Toggles a mechanical door (E to open/close). Smooth hinged swing; the
## panel's collision rotates with it, so the doorway is walkable when open.
func toggle_door(door_id: String) -> void:
	if not _doors.has(door_id):
		push_warning("ApartmentBuilder: unknown door '%s'." % door_id)
		return
	var d: Dictionary = _doors[door_id]
	var is_open: bool = d["open"]
	d["open"] = not is_open
	var pivot: Node3D = d["pivot"]
	var target: float = 0.0 if is_open else float(d["open_angle"])
	var tw := create_tween()
	tw.tween_property(pivot, "rotation:y", target, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var inter: Interactable = d["interactable"]
	inter.prompt = "Close the door" if not is_open else "Open the door"


## Snaps a mechanical door to a saved open/closed state (save/load restore).
func _set_door_instant(door_id: String, is_open: bool) -> void:
	if not _doors.has(door_id):
		return
	var dd: Dictionary = _doors[door_id]
	dd["open"] = is_open
	(dd["pivot"] as Node3D).rotation.y = float(dd["open_angle"]) if is_open else 0.0
	(dd["interactable"] as Interactable).prompt = "Close the door" if is_open else "Open the door"


# ------------------------------------------------------------------
# Save/load support: blackout + door states. Hide-closet doors always
# reset to closed — the player never loads hidden.
# ------------------------------------------------------------------

func serialize_world() -> Dictionary:
	var doors := {}
	for door_id in _doors.keys():
		doors[door_id] = bool((_doors[door_id] as Dictionary)["open"])
	return {"blackout": _blackout, "doors": doors, "front_open": _door_open}


func deserialize_world(d: Dictionary) -> void:
	var doors: Dictionary = d.get("doors", {})
	for door_id in doors.keys():
		_set_door_instant(String(door_id), bool(doors[door_id]))
	if d.has("front_open"):
		_door_open = bool(d["front_open"])
		if _door_pivot != null:
			_door_pivot.rotation.y = 1.85 if _door_open else 0.15
	_blackout = bool(d.get("blackout", false))


# ------------------------------------------------------------------
# Materials
# ------------------------------------------------------------------

func _mat(albedo: Color, roughness: float = 0.9, metallic: float = 0.0, emission: Color = Color(0, 0, 0)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = roughness
	m.metallic = metallic
	if emission != Color(0, 0, 0):
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 1.5
	return m


func _make_materials() -> void:
	_mats["wall"] = _mat(Color(0.16, 0.16, 0.19))
	_mats["floor"] = _mat(Color(0.23, 0.17, 0.12), 0.8)
	_mats["concrete"] = _mat(Color(0.13, 0.13, 0.15), 0.95)
	_mats["ceiling"] = _mat(Color(0.1, 0.1, 0.12))
	_mats["door"] = _mat(Color(0.3, 0.2, 0.13), 0.7)
	_mats["wood"] = _mat(Color(0.32, 0.22, 0.14), 0.75)
	_mats["fabric"] = _mat(Color(0.35, 0.12, 0.14), 0.95)
	_mats["fabric_dark"] = _mat(Color(0.16, 0.14, 0.18), 0.95)
	_mats["bedding"] = _mat(Color(0.5, 0.5, 0.55), 0.95)
	_mats["metal"] = _mat(Color(0.55, 0.58, 0.62), 0.35, 0.9)
	_mats["appliance"] = _mat(Color(0.7, 0.72, 0.75), 0.5, 0.2)
	_mats["dark"] = _mat(Color(0.05, 0.05, 0.06), 0.9)
	_mats["paper"] = _mat(Color(0.92, 0.9, 0.84), 0.9, 0.0, Color(0.22, 0.21, 0.18))
	_mats["mirror"] = _mat(Color(0.6, 0.68, 0.75), 0.08, 1.0)
	_mats["screen"] = _mat(Color(0.02, 0.03, 0.05), 0.4, 0.0, Color(0.05, 0.08, 0.12))
	_mats["lamp_glow"] = _mat(Color(1.0, 0.8, 0.55), 0.6, 0.0, Color(1.0, 0.7, 0.4))
	_mats["tube_glow"] = _mat(Color(0.8, 1.0, 0.9), 0.6, 0.0, Color(0.5, 0.8, 0.7))
	_mats["led_red"] = _mat(Color(0.5, 0.05, 0.05), 0.6, 0.0, Color(1.0, 0.1, 0.1))
	_mats["glass"] = _mat(Color(0.05, 0.08, 0.13), 0.12, 0.85)
	_mats["glass_frosted"] = _mat(Color(0.42, 0.47, 0.52), 0.65, 0.1)
	_mats["dirt"] = _mat(Color(0.11, 0.085, 0.06), 1.0)
	_mats["dirt_path"] = _mat(Color(0.16, 0.12, 0.08), 1.0)
	_mats["cardboard"] = _mat(Color(0.52, 0.4, 0.26), 0.92)
	_mats["cardboard_dark"] = _mat(Color(0.38, 0.29, 0.18), 0.92)
	_mats["clay"] = _mat(Color(0.58, 0.3, 0.2), 0.9)
	_mats["leaf"] = _mat(Color(0.14, 0.34, 0.14), 0.95)


func _mat_by(mat_name: String) -> StandardMaterial3D:
	return _mats[mat_name] as StandardMaterial3D


# ------------------------------------------------------------------
# Geometry helpers
# ------------------------------------------------------------------

func _add_box(size: Vector3, pos: Vector3, mat_name: String, rot_y: float = 0.0, collide: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rot_y
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat_by(mat_name)
	body.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
	add_child(body)
	return body


## Same as _add_box but parented under an arbitrary node (for closet
## assemblies that live in local space, possibly rotated).
func _cadd_box(parent: Node3D, size: Vector3, pos: Vector3, mat_name: String, rot_y: float = 0.0, collide: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rot_y
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat_by(mat_name)
	body.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
	parent.add_child(body)
	return body


func _add_quad(size: Vector2, pos: Vector3, mat_name: String, rot_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	mi.material_override = _mat_by(mat_name)
	mi.position = pos
	mi.rotation.y = rot_y
	add_child(mi)
	return mi


func _add_wall(a: Vector2, b: Vector2, y0: float) -> void:
	var length := a.distance_to(b)
	var center := (a + b) * 0.5
	var angle := atan2(b.x - a.x, b.y - a.y)
	_add_box(Vector3(WALL_T, WALL_H, length), Vector3(center.x, y0 + WALL_H * 0.5, center.y), "wall", angle)


func _add_guard(a: Vector2, b: Vector2, y0: float, h: float = 1.0) -> void:
	# Low guard wall around a stairwell opening.
	var length := a.distance_to(b)
	var center := (a + b) * 0.5
	var angle := atan2(b.x - a.x, b.y - a.y)
	_add_box(Vector3(WALL_T, h, length), Vector3(center.x, y0 + h * 0.5, center.y), "wall", angle)


func _add_light(pos: Vector3, color: Color, energy: float, light_range: float, flicker_mode: String) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	add_child(l)
	_lights.append({"node": l, "base": energy, "mode": flicker_mode, "phase": randf() * 10.0})


func _add_interactable(interact_id: String, prompt: String, pos: Vector3, extents: Vector3) -> Interactable:
	var inter := Interactable.new()
	inter.interact_id = interact_id
	inter.prompt = prompt
	inter.position = pos
	# Hotspots live on physics layer 2: the player's InteractRay (mask 3)
	# sees them, but the player body (mask 1) never collides with them.
	inter.collision_layer = 2
	inter.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = extents * 2.0
	cs.shape = shape
	inter.add_child(cs)
	add_child(inter)
	return inter


# ------------------------------------------------------------------
# Shell: walls, floor slabs (with stairwell holes), porch
# ------------------------------------------------------------------

func _build_shell() -> void:
	for w in WALLS:
		_add_wall(w[0], w[1], w[2])
	# Basement floor slab (top at y=-2.7).
	_add_box(Vector3(14.6, 0.15, 10.6), Vector3(0, -2.775, 0), "concrete")
	# Ground slab = basement ceiling (top y=0). Hole over the basement stair:
	# x in [0.85, 2.15], z in [-4.0, 0.9] (down-run at x in [0.9, 2.1],
	# 0.05 m clearance each side so no visible slot).
	_add_box(Vector3(8.15, 0.15, 10.6), Vector3(-3.225, -0.075, 0), "floor")
	_add_box(Vector3(5.15, 0.15, 10.6), Vector3(4.725, -0.075, 0), "floor")
	_add_box(Vector3(1.3, 0.15, 4.4), Vector3(1.5, -0.075, 3.1), "floor")
	_add_box(Vector3(1.3, 0.15, 1.3), Vector3(1.5, -0.075, -4.65), "floor")
	# Upper slab = ground ceiling (top y=2.7). Hole over the upper stair:
	# x in [-0.75, 0.55], z in [-4.0, 0.9] (up-run at x in [-0.7, 0.5],
	# 0.05 m clearance each side so no visible slot).
	_add_box(Vector3(6.55, 0.15, 10.6), Vector3(-4.025, 2.625, 0), "floor")
	_add_box(Vector3(6.75, 0.15, 10.6), Vector3(3.925, 2.625, 0), "floor")
	_add_box(Vector3(1.3, 0.15, 4.4), Vector3(-0.1, 2.625, 3.1), "floor")
	_add_box(Vector3(1.3, 0.15, 1.3), Vector3(-0.1, 2.625, -4.65), "floor")
	# Roof slab (top y=5.4).
	_add_box(Vector3(14.6, 0.15, 10.6), Vector3(0, 5.325, 0), "ceiling")


func _build_stairs() -> void:
	# Up-run: ground -> upper, x in [-0.7, 0.5]. Down-run: ground -> basement,
	# x in [0.9, 2.1]. Both run z: 0.9 -> -4.0, rise 2.7 (~29 deg).
	_build_stair_run(-0.1, true)
	_build_stair_run(1.5, false)
	# Guard walls around the stairwell holes (1 m, on the slab edges).
	# Upper floor, hole x in [-0.75, 0.55], z in [-4.0, 0.9] (north edge is the stair exit).
	_add_guard(Vector2(-0.75, -4.0), Vector2(-0.75, 0.9), UPPER_Y)
	_add_guard(Vector2(0.55, -4.0), Vector2(0.55, 0.9), UPPER_Y)
	_add_guard(Vector2(-0.75, 0.9), Vector2(0.55, 0.9), UPPER_Y)
	# Ground floor, hole x in [0.85, 2.15], z in [-4.0, 0.9] (south edge is the stair entry).
	_add_guard(Vector2(0.85, -4.0), Vector2(0.85, 0.9), GROUND_Y)
	_add_guard(Vector2(2.15, -4.0), Vector2(2.15, 0.9), GROUND_Y)
	_add_guard(Vector2(0.85, -4.0), Vector2(2.15, -4.0), GROUND_Y)
	# Fascia trim around the stairwell holes so the slab cuts read as
	# finished edges from below instead of raw black slots.
	_add_fascia(0.85, 2.15, -4.0, 0.9, -0.075)  # basement ceiling
	_add_fascia(-0.75, 0.55, -4.0, 0.9, 2.625)  # ground ceiling


func _add_fascia(x0: float, x1: float, z0: float, z1: float, y: float) -> void:
	# Wood trim frame around a stairwell slab hole. Slightly proud of the
	# 0.15-thick slab; visual only, the hole stays passable.
	var t := 0.2
	var w := 0.12
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	_add_box(Vector3(w, t, (z1 - z0) + w), Vector3(x0 - w * 0.5, y, cz), "wood", 0.0, false)
	_add_box(Vector3(w, t, (z1 - z0) + w), Vector3(x1 + w * 0.5, y, cz), "wood", 0.0, false)
	_add_box(Vector3((x1 - x0) + w, t, w), Vector3(cx, y, z0 - w * 0.5), "wood", 0.0, false)
	_add_box(Vector3((x1 - x0) + w, t, w), Vector3(cx, y, z1 + w * 0.5), "wood", 0.0, false)


func _build_stair_run(x_center: float, up: bool) -> void:
	var steps := 14
	var run := 4.9
	var rise := 2.7
	var dir := 1.0 if up else -1.0
	var h := rise / steps
	var floor_y := 0.0 if up else -2.7
	# Visual steps: solid boxes with closed risers, NO collision. Each step
	# spans from its tread top down past the next tread, so the staircase
	# reads as a solid mass from every angle (no floating slats).
	for i in range(steps):
		var top_y := dir * (i + 1) * h
		var z := 0.9 - (i + 0.5) * (run / steps)
		var bottom_y := maxf(top_y - h - 0.05, floor_y)
		var height := top_y - bottom_y
		if height < 0.03:
			continue  # last down-run tread: the basement floor is the tread
		_add_box(Vector3(1.2, height, run / steps + 0.02),
			Vector3(x_center, top_y - height * 0.5, z), "wood", 0.0, false)
	# ONE sloped ramp StaticBody3D for collision.
	var angle := atan2(rise, run)
	var length := sqrt(run * run + rise * rise) + 0.02
	var normal := Vector3(0, cos(angle), dir * sin(angle))
	var body := StaticBody3D.new()
	body.position = Vector3(x_center, dir * rise * 0.5, -1.55) - 0.06 * normal
	body.rotation.x = dir * angle
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2, 0.12, length)
	mi.mesh = bm
	mi.material_override = _mat_by("wood")
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 0.12, length)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


# ------------------------------------------------------------------
# Rooms
# ------------------------------------------------------------------

func _build_porch() -> void:
	# Small stoop outside the front door (x in [-0.4, 2.0], z in [5.0, 6.4]).
	_add_box(Vector3(2.4, 0.15, 1.4), Vector3(0.8, -0.075, 5.7), "concrete")
	# Railings so the player can't walk off into the dark.
	_add_box(Vector3(0.08, 0.9, 1.4), Vector3(-0.4, 0.45, 5.7), "wood")
	_add_box(Vector3(0.08, 0.9, 1.4), Vector3(2.0, 0.45, 5.7), "wood")
	_add_box(Vector3(2.48, 0.9, 0.08), Vector3(0.8, 0.45, 6.4), "wood")
	# Doormat.
	_add_box(Vector3(0.9, 0.03, 0.5), Vector3(0.8, 0.015, 5.5), "fabric_dark", 0.0, false)


func _build_foyer() -> void:
	# Rug and a small side table.
	_add_box(Vector3(2.0, 0.03, 1.4), Vector3(0.75, 0.015, 3.5), "fabric_dark", 0.0, false)
	_add_box(Vector3(0.8, 0.75, 0.4), Vector3(-0.5, 0.375, 4.6), "wood")
	# Stair-hall runner (no collision).
	_add_box(Vector3(2.4, 0.03, 4.6), Vector3(0.75, 0.015, -1.2), "fabric_dark", 0.0, false)


func _build_living_room() -> void:
	# Couch faces north, toward the TV on the north wall.
	_add_box(Vector3(2.2, 0.45, 0.95), Vector3(-4, 0.225, -2.6), "fabric")
	_add_box(Vector3(2.2, 0.75, 0.28), Vector3(-4, 0.7, -2.15), "fabric")
	_add_box(Vector3(0.28, 0.65, 0.95), Vector3(-5.1, 0.55, -2.6), "fabric")
	_add_box(Vector3(0.28, 0.65, 0.95), Vector3(-2.9, 0.55, -2.6), "fabric")
	# Coffee table and rug.
	_add_box(Vector3(1.2, 0.4, 0.6), Vector3(-4, 0.2, -3.5), "wood")
	_add_box(Vector3(3.0, 0.03, 2.2), Vector3(-4, 0.015, -3.2), "fabric_dark", 0.0, false)
	# TV stand + dead TV on the north wall.
	_add_box(Vector3(1.8, 0.5, 0.5), Vector3(-4, 0.25, -4.55), "wood")
	_add_box(Vector3(1.5, 0.85, 0.12), Vector3(-4, 1.15, -4.55), "dark")
	_add_quad(Vector2(1.35, 0.7), Vector3(-4, 1.15, -4.48), "screen")
	# Floor lamp beside the TV stand (placeholder boxes + emissive shade).
	_add_box(Vector3(0.3, 0.06, 0.3), Vector3(-2.6, 0.03, -4.4), "dark")
	_add_box(Vector3(0.06, 1.6, 0.06), Vector3(-2.6, 0.8, -4.4), "dark")
	_add_box(Vector3(0.4, 0.32, 0.4), Vector3(-2.6, 1.72, -4.4), "lamp_glow", 0.0, false)
	# Second floor lamp with the dying flicker.
	_add_box(Vector3(0.06, 1.7, 0.06), Vector3(-5.8, 0.85, -0.5), "dark")
	_add_box(Vector3(0.35, 0.3, 0.35), Vector3(-5.8, 1.8, -0.5), "lamp_glow", 0.0, false)


func _build_kitchen() -> void:
	# Counter run along the north wall, west of the back door (door x in [4.0, 5.2]).
	_add_box(Vector3(1.4, 0.9, 0.65), Vector3(3.2, 0.45, -4.62), "wood")
	# Stove, east of the back door.
	_add_box(Vector3(0.7, 0.9, 0.65), Vector3(6.6, 0.45, -4.62), "dark")
	# Fridge with the note on its front (front face at z = -4.15).
	_add_box(Vector3(0.85, 1.9, 0.8), Vector3(5.725, 0.95, -4.55), "appliance")
	_add_box(Vector3(0.05, 0.5, 0.06), Vector3(5.395, 1.2, -4.13), "metal", 0.0, false)
	_add_quad(Vector2(0.28, 0.34), Vector3(5.725, 1.35, -4.14), "paper")
	# The knife, displayed in the middle of the counter.
	_add_box(Vector3(0.28, 0.015, 0.045), Vector3(3.2, 0.93, -4.62), "metal", 0.5, false)
	_add_box(Vector3(0.12, 0.03, 0.05), Vector3(3.02, 0.93, -4.55), "dark", 0.5, false)


func _build_bedroom() -> void:
	var y := UPPER_Y
	# Bed, headboard against the north wall.
	_add_box(Vector3(1.6, 0.3, 2.2), Vector3(5.5, y + 0.15, -3.0), "wood")
	_add_box(Vector3(1.54, 0.25, 2.14), Vector3(5.5, y + 0.42, -3.0), "bedding")
	_add_box(Vector3(0.7, 0.12, 0.4), Vector3(5.5, y + 0.6, -3.9), "paper", 0.0, false)
	_add_box(Vector3(1.54, 0.08, 1.2), Vector3(5.5, y + 0.58, -2.5), "fabric_dark", 0.0, false)
	# Nightstand with the framed photo.
	_add_box(Vector3(0.55, 0.55, 0.55), Vector3(4.3, y + 0.275, -4.5), "wood")
	_add_box(Vector3(0.22, 0.28, 0.04), Vector3(4.3, y + 0.7, -4.5), "dark", 0.0, false)
	# Wardrobe / closet: built enterable by _build_hide_closets() (see the
	# Hiding spots section) so Mara can hide inside it later in the story.


func _build_bathroom() -> void:
	var y := UPPER_Y
	# Sink + mirror (mirror faces +z, into the room).
	_add_box(Vector3(0.35, 0.7, 0.35), Vector3(-6.3, y + 0.35, -4.5), "appliance")
	_add_box(Vector3(0.6, 0.15, 0.5), Vector3(-6.3, y + 0.78, -4.5), "appliance")
	_add_quad(Vector2(0.7, 0.9), Vector3(-6.3, y + 1.7, -4.9), "mirror")
	# Toilet.
	_add_box(Vector3(0.45, 0.4, 0.6), Vector3(-5.2, y + 0.2, -4.5), "appliance")
	_add_box(Vector3(0.45, 0.5, 0.2), Vector3(-5.2, y + 0.65, -4.75), "appliance")
	# Tub.
	_add_box(Vector3(1.7, 0.55, 0.75), Vector3(-4.6, y + 0.275, -2.0), "appliance")
	# Fluorescent tube fixture.
	_add_box(Vector3(1.2, 0.06, 0.15), Vector3(-5.5, y + 2.55, -3.0), "tube_glow", 0.0, false)


func _build_landing() -> void:
	var y := UPPER_Y
	# Bookshelf + rug for the open landing.
	_add_box(Vector3(1.2, 1.8, 0.35), Vector3(-6.8, y + 0.9, 3.0), "wood")
	_add_box(Vector3(2.4, 0.03, 1.8), Vector3(-4.0, y + 0.015, 3.0), "fabric_dark", 0.0, false)


func _build_basement() -> void:
	var y := BASE_Y
	# Support columns.
	_add_box(Vector3(0.3, 2.7, 0.3), Vector3(-3, y + 1.35, 0), "concrete")
	_add_box(Vector3(0.3, 2.7, 0.3), Vector3(3, y + 1.35, 0), "concrete")
	# Storage boxes.
	_add_box(Vector3(0.9, 0.9, 0.9), Vector3(-4.5, y + 0.45, -3.0), "wood")
	_add_box(Vector3(0.7, 0.7, 0.7), Vector3(-5.4, y + 0.35, -2.3), "wood")
	_add_box(Vector3(0.7, 0.7, 0.7), Vector3(-4.5, y + 1.25, -3.0), "wood", 0.3, false)
	_add_box(Vector3(1.0, 0.8, 0.8), Vector3(4.2, y + 0.4, 2.5), "wood")
	_add_box(Vector3(0.8, 0.8, 0.8), Vector3(-2.5, y + 0.4, 3.5), "wood")
	_add_box(Vector3(0.8, 0.6, 0.6), Vector3(2.0, y + 0.3, -3.5), "wood")
	# Breaker box on the east wall (inner face at x = 6.91).
	_add_box(Vector3(0.15, 0.7, 0.5), Vector3(6.82, y + 1.35, -1.0), "metal")
	# Tiny red LED so it can be found in the dark (emissive; blackout can't kill it).
	_add_box(Vector3(0.03, 0.06, 0.06), Vector3(6.73, y + 1.6, -1.0), "led_red", 0.0, false)


# ------------------------------------------------------------------
# Hiding spots. Three enterable closets for a future stalker room-check
# sequence (no stalker AI yet): the bedroom wardrobe, a bathroom linen
# cabinet, and a foyer coat closet. Each is a hollow carcass with a
# hinged door that swings OUTWARD (never through a hidden player).
# The GameManager owns the hide/unhide state; this only builds the set
# dressing and exposes door control.
# ------------------------------------------------------------------

# [spot_id, center, rot_y, hotspot_pos, hotspot_extents].
# The door sits on the local +Z face; rot_y turns it to face the room.
# (The bedroom wardrobe lives on the east wall: the north wall can't fit
# it clear of the bed's north-east corner.)
const HIDE_CLOSETS: Array = [
	["bedroom_closet", Vector3(6.35, 2.7, -0.5), -PI * 0.5, Vector3(5.25, 3.9, -0.5), Vector3(0.4, 0.65, 0.55)],
	["bathroom_closet", Vector3(-6.0, 2.7, -1.5), PI, Vector3(-6.0, 3.9, -2.6), Vector3(0.5, 0.65, 0.35)],
	["foyer_closet", Vector3(1.85, 0.0, 3.5), -PI * 0.5, Vector3(0.75, 1.2, 3.5), Vector3(0.35, 0.65, 0.55)],
]

const HIDE_DOOR_OPEN_ANGLE := -1.75  # swings outward, into the room.


func _build_hide_closets() -> void:
	for c in HIDE_CLOSETS:
		# The bedroom wardrobe doubles as the "closet" story beat: its Hide
		# hotspot is only created once that beat is consumed, so the two
		# hotspots never occlude each other on the same door.
		var make_hotspot := String(c[0]) != "bedroom_closet"
		_build_hide_closet(String(c[0]), c[1], float(c[2]), c[3], c[4], make_hotspot)


func _build_hide_closet(spot_id: String, center: Vector3, rot_y: float, hotspot_pos: Vector3, hotspot_extents: Vector3, make_hotspot: bool = true) -> void:
	var w := 1.1   # interior ~0.98 m wide
	var d := 1.0   # interior ~0.88 m deep
	var h := 2.1
	var t := 0.06  # panel thickness
	var node := Node3D.new()
	node.position = center
	node.rotation.y = rot_y
	add_child(node)
	# Carcass: back, sides, top. No floor panel (the room floor is the floor).
	_cadd_box(node, Vector3(w, h, t), Vector3(0, h * 0.5, -d * 0.5 + t * 0.5), "wood")
	_cadd_box(node, Vector3(t, h, d), Vector3(-w * 0.5 + t * 0.5, h * 0.5, 0), "wood")
	_cadd_box(node, Vector3(t, h, d), Vector3(w * 0.5 - t * 0.5, h * 0.5, 0), "wood")
	_cadd_box(node, Vector3(w, t, d), Vector3(0, h - t * 0.5, 0), "wood")
	# Hanging rod, high and clear of the player's head (visual only).
	_cadd_box(node, Vector3(w - 2.0 * t, 0.04, 0.04), Vector3(0, 1.78, -0.15), "dark", 0.0, false)
	# Hinged door on the +Z (front) face. Pivot at the left jamb; the panel
	# extends +X when closed and swings outward (+Z, into the room).
	var panel_w := w - 2.0 * t - 0.04
	var pivot := Node3D.new()
	pivot.position = Vector3(-w * 0.5 + t + 0.01, 0, d * 0.5)
	node.add_child(pivot)
	var panel := _cadd_box(pivot, Vector3(panel_w, 2.0, 0.06), Vector3(panel_w * 0.5 + 0.01, 1.0, 0), "door")
	# Knob near the panel's free edge.
	var knob := MeshInstance3D.new()
	var km := BoxMesh.new()
	km.size = Vector3(0.07, 0.07, 0.12)
	knob.mesh = km
	knob.material_override = _mat_by("metal")
	knob.position = Vector3(panel_w * 0.5 - 0.12, 0, 0.05)
	panel.add_child(knob)
	# Hide hotspot in front of the door. Reusable, never one-shot.
	_hide_closets[spot_id] = {"node": node, "pivot": pivot, "hotspot": null,
		"hotspot_pos": hotspot_pos, "hotspot_extents": hotspot_extents}
	if make_hotspot:
		add_hide_hotspot(spot_id)


## Creates the Hide hotspot for a hiding spot (the bedroom one is deferred
## until its story beat is consumed). Calling it again just re-enables the
## hotspot, so it is also safe for future systems (e.g. the stalker
## sequence) to call directly.
func add_hide_hotspot(spot_id: String) -> void:
	if not _hide_closets.has(spot_id):
		push_warning("ApartmentBuilder: unknown hiding spot '%s'." % spot_id)
		return
	var d: Dictionary = _hide_closets[spot_id]
	if d["hotspot"] != null:
		(d["hotspot"] as Interactable).enable()
		return
	var inter := _add_interactable("hide_" + spot_id, "Hide",
		d["hotspot_pos"], d["hotspot_extents"])
	inter.one_shot = false
	d["hotspot"] = inter


## Swings a hiding-spot door open (tween) or shut. Driven by the
## GameManager as part of hide/unhide; doors are never toggled directly.
func set_hide_door(spot_id: String, open: bool) -> void:
	if not _hide_closets.has(spot_id):
		push_warning("ApartmentBuilder: unknown hiding spot '%s'." % spot_id)
		return
	var d: Dictionary = _hide_closets[spot_id]
	var old_tw: Tween = d.get("tween")
	if old_tw != null and old_tw.is_valid():
		old_tw.kill()
	var pivot: Node3D = d["pivot"]
	var target: float = HIDE_DOOR_OPEN_ANGLE if open else 0.0
	var tw := create_tween()
	d["tween"] = tw
	tw.tween_property(pivot, "rotation:y", target, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Snaps a hiding-spot door open/shut instantly (story-beat safety path).
func set_hide_door_immediate(spot_id: String, open: bool) -> void:
	if not _hide_closets.has(spot_id):
		return
	var d: Dictionary = _hide_closets[spot_id]
	var old_tw: Tween = d.get("tween")
	if old_tw != null and old_tw.is_valid():
		old_tw.kill()
	(d["pivot"] as Node3D).rotation.y = HIDE_DOOR_OPEN_ANGLE if open else 0.0


## Enables a hiding spot's Hide hotspot. The bedroom one starts disabled
## until the "closet" story beat is consumed; future systems (e.g. the
## stalker sequence) can also call this directly.
func enable_hide_spot(spot_id: String) -> void:
	add_hide_hotspot(spot_id)


func _build_front_door() -> void:
	# Hinged at the west edge of the doorway (x=0.2, z=5.0); the panel extends
	# +x when closed. Slightly ajar at start; open_door() swings it ~106
	# degrees inward, into the foyer.
	# Lintel above the door: the wall gap is full height (2.7 m) but the panel
	# is only 2.1 m, so close the 0.6 m strip above it.
	_add_box(Vector3(1.2, 0.6, WALL_T), Vector3(0.8, 2.4, 5.0), "wall")
	_door_pivot = Node3D.new()
	_door_pivot.position = Vector3(0.2, 0, 5.0)
	_door_pivot.rotation.y = 0.15
	add_child(_door_pivot)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.16, 2.1, 0.08)
	mi.mesh = bm
	mi.material_override = _mat_by("door")
	mi.position = Vector3(0.58, 1.05, 0)
	_door_pivot.add_child(mi)


# ------------------------------------------------------------------
# Windows (fixed glass). The WALLS table leaves the openings; this fills
# below-sill / above-header and adds frame + glass.
# [cx, cz, width, y0, sill_h, header_h, along_x, frosted]
# ------------------------------------------------------------------

const WINDOWS: Array = [
	[-7.0, -3.0, 1.2, GROUND_Y, 1.0, 2.2, false, false],  # living west 1
	[-7.0, 1.0, 1.2, GROUND_Y, 1.0, 2.2, false, false],   # living west 2
	[7.0, -2.0, 1.2, GROUND_Y, 1.0, 2.2, false, false],    # kitchen east
	[-1.9, 5.0, 1.2, GROUND_Y, 1.0, 2.2, true, false],     # south, west of door
	[3.7, 5.0, 1.2, GROUND_Y, 1.0, 2.2, true, false],      # south, east of door
	[7.0, -2.5, 1.2, UPPER_Y, 1.0, 2.2, false, false],     # bedroom east
	[-4.4, -5.0, 1.2, UPPER_Y, 1.5, 2.3, true, true],      # bathroom north, frosted
]


func _build_windows() -> void:
	for w in WINDOWS:
		_add_window(w[0], w[1], w[2], w[3], w[4], w[5], w[6], w[7])


func _add_window(cx: float, cz: float, width: float, y0: float, sill_h: float, header_h: float, along_x: bool, frosted: bool) -> void:
	var sill_y := y0 + sill_h
	var header_y := y0 + header_h
	var mid_y := (sill_y + header_y) * 0.5
	var glass_h := header_h - sill_h - 0.1
	var glass_w := width - 0.1
	var ft := 0.09  # frame trim thickness
	if along_x:
		# Wall runs along x (z = const).
		_add_box(Vector3(width, sill_h, WALL_T), Vector3(cx, y0 + sill_h * 0.5, cz), "wall")
		_add_box(Vector3(width, 2.7 - header_h, WALL_T), Vector3(cx, y0 + header_h + (2.7 - header_h) * 0.5, cz), "wall")
		_add_box(Vector3(width + 0.18, ft, WALL_T + 0.06), Vector3(cx, sill_y, cz), "wood")
		_add_box(Vector3(width + 0.18, ft, WALL_T + 0.06), Vector3(cx, header_y, cz), "wood")
		_add_box(Vector3(ft, header_h - sill_h, WALL_T + 0.06), Vector3(cx - width * 0.5, mid_y, cz), "wood")
		_add_box(Vector3(ft, header_h - sill_h, WALL_T + 0.06), Vector3(cx + width * 0.5, mid_y, cz), "wood")
		_add_box(Vector3(glass_w, glass_h, 0.04), Vector3(cx, mid_y, cz), "glass_frosted" if frosted else "glass", 0.0, false)
		# Center mullion.
		_add_box(Vector3(0.06, glass_h, 0.06), Vector3(cx, mid_y, cz), "wood", 0.0, false)
	else:
		# Wall runs along z (x = const).
		_add_box(Vector3(WALL_T, sill_h, width), Vector3(cx, y0 + sill_h * 0.5, cz), "wall")
		_add_box(Vector3(WALL_T, 2.7 - header_h, width), Vector3(cx, y0 + header_h + (2.7 - header_h) * 0.5, cz), "wall")
		_add_box(Vector3(WALL_T + 0.06, ft, width + 0.18), Vector3(cx, sill_y, cz), "wood")
		_add_box(Vector3(WALL_T + 0.06, ft, width + 0.18), Vector3(cx, header_y, cz), "wood")
		_add_box(Vector3(WALL_T + 0.06, header_h - sill_h, ft), Vector3(cx, mid_y, cz - width * 0.5), "wood")
		_add_box(Vector3(WALL_T + 0.06, header_h - sill_h, ft), Vector3(cx, mid_y, cz + width * 0.5), "wood")
		_add_box(Vector3(0.04, glass_h, glass_w), Vector3(cx, mid_y, cz), "glass_frosted" if frosted else "glass", 0.0, false)
		# Center mullion.
		_add_box(Vector3(0.06, glass_h, 0.06), Vector3(cx, mid_y, cz), "wood", 0.0, false)


# ------------------------------------------------------------------
# Backyard + outhouse
# ------------------------------------------------------------------

func _build_backyard() -> void:
	# Dirt yard north of the house.
	_add_box(Vector3(16.0, 0.15, 7.0), Vector3(1.0, -0.075, -8.5), "dirt")
	# Worn path from the back door to the outhouse.
	_add_box(Vector3(1.2, 0.03, 4.2), Vector3(5.4, 0.015, -7.1), "dirt_path", 0.0, false)
	# Perimeter fence (1.1 m) so the player can't walk off into the dark.
	# North, west, east; the house itself closes the south side.
	_add_box(Vector3(16.0, 1.1, 0.1), Vector3(1.0, 0.55, -12.0), "wood")
	_add_box(Vector3(0.1, 1.1, 7.0), Vector3(-7.0, 0.55, -8.5), "wood")
	_add_box(Vector3(0.1, 1.1, 7.0), Vector3(9.0, 0.55, -8.5), "wood")
	# Fence posts.
	for fx in [-7.0, -3.0, 1.0, 5.0, 9.0]:
		_add_box(Vector3(0.14, 1.25, 0.14), Vector3(fx, 0.625, -12.0), "wood")
	# Outhouse: 2 x 2.4 m shed, 2.2 m walls, slanted roof. Door on south face.
	var wx0 := 5.0
	var wx1 := 7.0
	var wz0 := -11.4
	var wz1 := -9.0
	var wh := 2.2
	var wt := 0.12
	# North, west, east walls (full).
	_add_box(Vector3(wx1 - wx0, wh, wt), Vector3(6.0, wh * 0.5, wz0), "wood")
	_add_box(Vector3(wt, wh, wz1 - wz0), Vector3(wx0, wh * 0.5, -10.2), "wood")
	_add_box(Vector3(wt, wh, wz1 - wz0), Vector3(wx1, wh * 0.5, -10.2), "wood")
	# South wall with door gap x in [5.5, 6.5].
	_add_box(Vector3(0.5, wh, wt), Vector3(5.25, wh * 0.5, wz1), "wood")
	_add_box(Vector3(0.5, wh, wt), Vector3(6.75, wh * 0.5, wz1), "wood")
	# Lintel above the door.
	_add_box(Vector3(1.0, 0.2, wt), Vector3(6.0, 2.1, wz1), "wood")
	# Slanted roof (single slab, slight pitch).
	var roof := _add_box(Vector3(2.5, 0.08, 2.9), Vector3(6.0, 2.32, -10.2), "wood", 0.0, false)
	roof.rotation.x = 0.09
	# Interior bench (the seat).
	_add_box(Vector3(0.7, 0.45, 0.55), Vector3(6.0, 0.225, -10.7), "wood")
	# The door itself: hinge west jamb, swings south outward.
	_build_door("door_outhouse", Vector3(5.5, 0.0, -9.0),
		Vector3(0.96, 2.0, 0.08), Vector3(0.48, 1.0, 0), -1.75,
		Vector3(6.0, 1.2, -8.55))


# ------------------------------------------------------------------
# Mechanical doors (E to open/close). Hinged panels; not story beats.
# ------------------------------------------------------------------

func _build_door(door_id: String, hinge: Vector3, panel_size: Vector3, panel_offset: Vector3, open_angle: float, prompt_pos: Vector3) -> void:
	# hinge: pivot position at floor level. When closed (rotation 0) the panel
	# spans the doorway; open_angle is the pivot's rotation.y when open.
	var pivot := Node3D.new()
	pivot.position = hinge
	add_child(pivot)
	var panel := StaticBody3D.new()
	panel.position = panel_offset
	pivot.add_child(panel)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = panel_size
	mi.mesh = bm
	mi.material_override = _mat_by("door")
	panel.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = panel_size
	cs.shape = shape
	panel.add_child(cs)
	# Small knob near the panel's free edge (visual only).
	var knob := MeshInstance3D.new()
	var km := BoxMesh.new()
	km.size = Vector3(0.07, 0.07, 0.12)
	knob.mesh = km
	knob.material_override = _mat_by("metal")
	if panel_size.x > panel_size.z:
		knob.position = Vector3(panel_size.x * 0.5 - 0.12, 0.0, 0.0)
	else:
		knob.position = Vector3(0.0, 0.0, panel_size.z * 0.5 - 0.12)
	panel.add_child(knob)
	var inter := _add_interactable(door_id, "Open the door", prompt_pos, Vector3(0.3, 0.3, 0.3))
	inter.one_shot = false
	_doors[door_id] = {"pivot": pivot, "open": false, "open_angle": open_angle, "interactable": inter}


func _build_doors() -> void:
	# Bedroom door (upper floor, x=2.5 wall, doorway z in [-0.6, 0.6]).
	# Hinge on the south jamb; swings east into the bedroom.
	_add_box(Vector3(0.18, 0.6, 1.2), Vector3(2.5, UPPER_Y + 2.4, 0.0), "wall")
	_build_door("door_bedroom", Vector3(2.5, UPPER_Y, -0.6),
		Vector3(0.08, 2.1, 1.16), Vector3(0, 1.05, 0.58), 1.75,
		Vector3(2.05, UPPER_Y + 1.5, 0.0))
	# Basement door: freestanding frame at the top of the down-run (z=0.9).
	# Hinge on the west jamb; swings south into the stair hall, clear of the ramp.
	_add_box(Vector3(0.12, 2.1, 0.12), Vector3(0.9, 1.05, 0.9), "wood")
	_add_box(Vector3(0.12, 2.1, 0.12), Vector3(2.1, 1.05, 0.9), "wood")
	_add_box(Vector3(1.32, 0.6, 0.12), Vector3(1.5, 2.4, 0.9), "wood")
	_build_door("door_basement", Vector3(0.9, 0.0, 0.9),
		Vector3(1.16, 2.1, 0.08), Vector3(0.58, 1.05, 0), -1.75,
		Vector3(1.5, 1.5, 1.45))
	# Back door (north wall, x in [4.0, 5.2]). Hinge on the west jamb;
	# swings north out into the backyard.
	_add_box(Vector3(1.2, 0.6, WALL_T), Vector3(4.6, 2.4, -5.0), "wall")
	_build_door("door_back", Vector3(4.0, 0.0, -5.0),
		Vector3(1.16, 2.1, 0.08), Vector3(0.58, 1.05, 0), 1.75,
		Vector3(4.6, 1.5, -4.55))


func _build_interactables() -> void:
	# interact_id must match a key in StoryData.get_trigger_beats().
	_add_interactable("fridge_note", "Read the note", Vector3(5.725, 1.35, -3.95), Vector3(0.4, 0.4, 0.3))
	_add_interactable("bedroom_photo", "Look at the photo", Vector3(4.3, UPPER_Y + 0.85, -4.5), Vector3(0.35, 0.35, 0.35))
	_add_interactable("bedroom_closet", "Open the closet", Vector3(5.6, UPPER_Y + 1.1, -0.5), Vector3(0.3, 0.8, 0.7))
	_add_interactable("bathroom_mirror", "Look in the mirror", Vector3(-6.3, UPPER_Y + 1.6, -4.1), Vector3(0.45, 0.55, 0.35))
	_add_interactable("kitchen_knife", "Look at the knife", Vector3(3.2, 1.1, -4.25), Vector3(0.5, 0.4, 0.4))
	_add_interactable("breaker_box", "Flip the breaker", Vector3(6.4, BASE_Y + 1.35, -1.0), Vector3(0.35, 0.45, 0.35))
	# Checklist hotspot (routed to the GameManager, not a story beat).
	var lock := _add_interactable("front_door_lock", "Lock the front door", Vector3(0.8, 1.2, 4.7), Vector3(0.4, 0.4, 0.4))
	lock.one_shot = false


# ------------------------------------------------------------------
# Chores (optional minigames). Props + hotspots; ChoreManager owns state.
# ------------------------------------------------------------------

func _build_chores() -> void:
	# --- Trash: 3 bags around the house, bin on the porch. ---
	_add_trash_bag("trash_bag_kitchen", Vector3(2.2, 0.0, -4.0))
	_add_trash_bag("trash_bag_living", Vector3(-2.4, 0.0, -3.1))
	_add_trash_bag("trash_bag_bedroom", Vector3(3.8, UPPER_Y, -2.5))
	# Curbside bin on the porch, east side inside the railing.
	_add_box(Vector3(0.55, 0.85, 0.55), Vector3(1.55, 0.425, 6.05), "dark")
	_add_box(Vector3(0.62, 0.08, 0.62), Vector3(1.55, 0.89, 6.05), "dark", 0.0, false)
	# --- Dishes: sink + dirty stack on the counter, rack on an extension. ---
	# Counter extension east (clear of the back-door swing, which goes north).
	_add_box(Vector3(0.4, 0.9, 0.65), Vector3(4.1, 0.45, -4.62), "wood")
	# Sink basin + faucet on the counter, east of the knife.
	_add_box(Vector3(0.42, 0.14, 0.4), Vector3(3.62, 0.94, -4.62), "metal", 0.0, false)
	_add_box(Vector3(0.05, 0.32, 0.05), Vector3(3.62, 1.1, -4.83), "metal", 0.0, false)
	_add_box(Vector3(0.05, 0.05, 0.22), Vector3(3.62, 1.24, -4.73), "metal", 0.0, false)
	# 4 dirty plates stacked west of the sink.
	for i in range(4):
		var plate := _add_box(Vector3(0.3, 0.035, 0.3), Vector3(2.72, 0.92 + i * 0.04, -4.62), "appliance", 0.0, false)
		_dish_plates.append(plate)
	# Drying rack on the extension; slots for the 4 plates, standing upright.
	_add_box(Vector3(0.36, 0.05, 0.4), Vector3(4.1, 0.925, -4.62), "dark", 0.0, false)
	for i in range(4):
		_rack_slots.append(Vector3(4.1 + (i - 1.5) * 0.085, 1.12, -4.62))
	# --- Chore hotspots (routed to ChoreManager, not story beats). ---
	var b1 := _add_interactable("trash_bag_kitchen", "Grab the trash bag", Vector3(2.2, 0.6, -4.0), Vector3(0.45, 0.45, 0.45))
	var b2 := _add_interactable("trash_bag_living", "Grab the trash bag", Vector3(-2.4, 0.6, -3.1), Vector3(0.45, 0.45, 0.45))
	var b3 := _add_interactable("trash_bag_bedroom", "Grab the trash bag", Vector3(3.8, UPPER_Y + 0.6, -2.5), Vector3(0.45, 0.45, 0.45))
	var b4 := _add_interactable("trash_bin", "Toss the bag in", Vector3(1.55, 1.0, 6.05), Vector3(0.5, 0.5, 0.5))
	var s1 := _add_interactable("sink", "Wash the dishes", Vector3(3.85, 1.15, -4.35), Vector3(0.3, 0.35, 0.3))
	for inter in [b1, b2, b3, b4, s1]:
		(inter as Interactable).one_shot = false


func _add_trash_bag(bag_id: String, pos: Vector3) -> void:
	var n1 := _add_box(Vector3(0.45, 0.5, 0.45), pos + Vector3(0, 0.25, 0), "fabric_dark", 0.0, false)
	var n2 := _add_box(Vector3(0.18, 0.14, 0.18), pos + Vector3(0, 0.56, 0), "fabric_dark", 0.4, false)
	_trash_bag_nodes[bag_id] = [n1, n2]


## Chore prop API used by the ChoreManager.
func hide_trash_bag(bag_id: String) -> void:
	for n in _trash_bag_nodes.get(bag_id, []):
		(n as Node3D).visible = false


func get_dish_plate(i: int) -> Node3D:
	if i < 0 or i >= _dish_plates.size():
		return null
	return _dish_plates[i]


func dish_to_rack(i: int, instant: bool = false) -> void:
	if i < 0 or i >= _dish_plates.size() or i >= _rack_slots.size():
		return
	var plate: Node3D = _dish_plates[i]
	if instant:
		# Save/load restore: snap straight to the rack, no tween.
		plate.position = _rack_slots[i]
		plate.rotation.x = 1.35
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(plate, "position", _rack_slots[i], 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(plate, "rotation:x", 1.35, 0.6)


# ------------------------------------------------------------------
# Unpacking (core opening gameplay). Boxes + placement zones; the
# UnpackManager owns the state machine, this builds the set dressing.
# ------------------------------------------------------------------

# [box_id, label, position] — the four labeled boxes.
const UNPACK_BOXES: Array = [
	["unpack_box_kitchen", "KITCHEN", Vector3(-0.2, 0.0, 2.2)],
	["unpack_box_books", "BOOKS", Vector3(-2.0, 0.0, 1.2)],
	["unpack_box_bedroom", "BEDROOM", Vector3(1.6, 0.0, 2.6)],
	["unpack_box_bath", "BATH", Vector3(-3.2, 0.0, 0.6)],
]
# The unmarked box sits slightly apart from the others.
const UNPACK_PLAIN_POS := Vector3(-4.4, 0.0, 2.2)

# [zone_id, marker/interactable position].
const UNPACK_ZONES: Array = [
	["uzone_kitchen_sill", Vector3(6.9, 1.07, -2.0)],
	["uzone_kitchen_stove", Vector3(6.6, 0.92, -4.62)],
	["uzone_living_shelf", Vector3(-6.7, 1.22, -1.5)],
	["uzone_living_sill_south", Vector3(-1.9, 1.07, 4.95)],
	["uzone_living_sill_west", Vector3(-6.9, 1.07, 1.0)],
	["uzone_bed_nightstand", Vector3(4.3, 3.27, -4.42)],
	["uzone_bed_bed", Vector3(5.5, 3.34, -2.2)],
	["uzone_bath_tub", Vector3(-4.0, 3.27, -2.0)],
	["uzone_bath_sink", Vector3(-6.3, 3.57, -4.4)],
	["uzone_bath_toilet", Vector3(-5.2, 3.62, -4.75)],
]


func _build_unpack() -> void:
	# Low bookcase in the living room (one unpacking destination).
	_add_box(Vector3(0.35, 1.2, 1.2), Vector3(-6.7, 0.6, -1.5), "wood")
	# The four labeled boxes + the unmarked one.
	for b in UNPACK_BOXES:
		var bid: String = b[0]
		var blabel: String = b[1]
		var bpos: Vector3 = b[2]
		_build_unpack_box(bid, blabel, bpos)
	_build_unpack_box("unpack_box_plain", "", UNPACK_PLAIN_POS)
	# Placement-zone markers (hidden until the carried item needs them).
	_unpack_marker_mat = _mat(Color(0.35, 0.75, 1.0), 0.5, 0.0, Color(0.3, 0.7, 1.0))
	for z in UNPACK_ZONES:
		var zid: String = z[0]
		var zpos: Vector3 = z[1]
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.2
		cm.bottom_radius = 0.2
		cm.height = 0.02
		disc.mesh = cm
		disc.material_override = _unpack_marker_mat
		disc.position = zpos
		disc.visible = false
		add_child(disc)
		_unpack_markers[zid] = disc
		var zinter := _add_interactable(zid, "Place it here", zpos, Vector3(0.4, 0.32, 0.4))
		zinter.one_shot = false
		zinter.disable()


func _build_unpack_box(box_id: String, label: String, pos: Vector3) -> void:
	# Open-top cardboard box: floor + 4 walls + dark interior, lid on top.
	var t := 0.04
	var w := 0.55
	var h := 0.42
	_add_box(Vector3(w, t, w), pos + Vector3(0, t * 0.5, 0), "cardboard")
	_add_box(Vector3(w, h, t), pos + Vector3(0, h * 0.5, w * 0.5 - t * 0.5), "cardboard")
	_add_box(Vector3(w, h, t), pos + Vector3(0, h * 0.5, -w * 0.5 + t * 0.5), "cardboard")
	_add_box(Vector3(t, h, w), pos + Vector3(w * 0.5 - t * 0.5, h * 0.5, 0), "cardboard")
	_add_box(Vector3(t, h, w), pos + Vector3(-w * 0.5 + t * 0.5, h * 0.5, 0), "cardboard")
	var lid := _add_box(Vector3(w + 0.02, 0.05, w + 0.02), pos + Vector3(0, h + 0.025, 0), "cardboard_dark", 0.0, false)
	_unpack_lids[box_id] = lid
	# Dark interior bottom so the box reads as hollow, not solid.
	var inside := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w - 2.0 * t, w - 2.0 * t)
	inside.mesh = qm
	inside.material_override = _mat_by("dark")
	inside.position = pos + Vector3(0, t + 0.002, 0)
	inside.rotation.x = -PI * 0.5
	add_child(inside)
	if label != "":
		var lbl := Label3D.new()
		lbl.text = label
		lbl.font_size = 64
		lbl.pixel_size = 0.006
		lbl.shaded = false
		lbl.modulate = Color(0.16, 0.12, 0.09)
		lbl.position = pos + Vector3(0, 0.24, w * 0.5 + 0.001)
		add_child(lbl)
	var prompt := "Open the unmarked box" if label == "" else "Unpack the %s box" % label
	var inter := _add_interactable(box_id, prompt, pos + Vector3(0, 0.55, 0), Vector3(0.45, 0.45, 0.45))
	inter.one_shot = false
	inter.disable()


## Unpacking prop API used by the UnpackManager.
func open_unpack_box(box_id: String) -> void:
	var lid: Node3D = _unpack_lids.get(box_id)
	if lid != null:
		lid.visible = false


## Shows only the given placement-zone markers; hides the rest.
func set_unpack_zones(zone_ids: Array) -> void:
	for zid in _unpack_markers:
		(_unpack_markers[zid] as MeshInstance3D).visible = bool(zone_ids.has(zid))


func hide_unpack_zones() -> void:
	set_unpack_zones([])


## Builds a small item prop (origin at bottom-center, no collision).
## Used for both the in-hand carried mesh and the placed prop.
func make_unpack_item_mesh(kind: String) -> Node3D:
	var root := Node3D.new()
	match kind:
		"books":
			_uadd_prop_box(root, Vector3(0.28, 0.05, 0.2), Vector3(0, 0.025, 0), "fabric")
			_uadd_prop_box(root, Vector3(0.26, 0.05, 0.19), Vector3(0, 0.075, 0), "fabric_dark")
			_uadd_prop_box(root, Vector3(0.28, 0.05, 0.2), Vector3(0, 0.125, 0), "paper")
		"frame":
			_uadd_prop_box(root, Vector3(0.22, 0.28, 0.03), Vector3(0, 0.14, 0), "dark")
			_uadd_prop_box(root, Vector3(0.16, 0.22, 0.012), Vector3(0, 0.14, 0.012), "paper")
		"plant":
			_uadd_prop_cyl(root, 0.07, 0.12, Vector3(0, 0.06, 0), "clay")
			_uadd_prop_box(root, Vector3(0.16, 0.2, 0.16), Vector3(0, 0.2, 0), "leaf")
		"mug":
			_uadd_prop_cyl(root, 0.05, 0.1, Vector3(0, 0.05, 0), "appliance")
		"bowl":
			_uadd_prop_cyl(root, 0.09, 0.06, Vector3(0, 0.03, 0), "appliance")
		"pot":
			_uadd_prop_cyl(root, 0.11, 0.12, Vector3(0, 0.06, 0), "metal")
		"lamp":
			_uadd_prop_cyl(root, 0.06, 0.04, Vector3(0, 0.02, 0), "dark")
			_uadd_prop_cyl(root, 0.015, 0.22, Vector3(0, 0.14, 0), "dark")
			_uadd_prop_box(root, Vector3(0.16, 0.13, 0.16), Vector3(0, 0.28, 0), "lamp_glow")
		"clock":
			_uadd_prop_box(root, Vector3(0.14, 0.1, 0.06), Vector3(0, 0.05, 0), "dark")
			_uadd_prop_box(root, Vector3(0.1, 0.07, 0.012), Vector3(0, 0.05, 0.028), "paper")
		"clothes":
			_uadd_prop_box(root, Vector3(0.3, 0.07, 0.24), Vector3(0, 0.035, 0), "fabric")
			_uadd_prop_box(root, Vector3(0.28, 0.07, 0.22), Vector3(0, 0.105, 0), "fabric_dark")
		"towel":
			_uadd_prop_box(root, Vector3(0.32, 0.06, 0.24), Vector3(0, 0.03, 0), "bedding")
		"soap":
			_uadd_prop_box(root, Vector3(0.1, 0.05, 0.07), Vector3(0, 0.025, 0), "paper")
		"tp":
			_uadd_prop_cyl(root, 0.06, 0.12, Vector3(0, 0.06, 0), "paper")
		"note":
			_uadd_prop_box(root, Vector3(0.2, 0.012, 0.28), Vector3(0, 0.006, 0), "paper")
		_:
			_uadd_prop_box(root, Vector3(0.2, 0.2, 0.2), Vector3(0, 0.1, 0), "cardboard")
	return root


func _uadd_prop_box(parent: Node3D, size: Vector3, pos: Vector3, mat_name: String) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat_by(mat_name)
	mi.position = pos
	parent.add_child(mi)


func _uadd_prop_cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat_name: String) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = _mat_by(mat_name)
	mi.position = pos
	parent.add_child(mi)


## Spawns an unpacked item prop at its final slot; returns the node.
func spawn_unpack_prop(kind: String, pos: Vector3) -> Node3D:
	var n := make_unpack_item_mesh(kind)
	n.position = pos
	add_child(n)
	return n


func _build_lights() -> void:
	# (position, color, energy, range, flicker mode)
	_add_light(Vector3(0.8, 2.4, 5.9), Color(0.6, 0.7, 1.0), 1.0, 6.0, "steady")      # porch
	_add_light(Vector3(0.75, 2.4, 3.0), Color(1.0, 0.8, 0.6), 1.4, 7.0, "steady")     # foyer
	_add_light(Vector3(-2.6, 1.65, -4.4), Color(1.0, 0.8, 0.55), 1.4, 6.0, "steady") # TV lamp
	_add_light(Vector3(-5.8, 1.9, -0.5), Color(1.0, 0.75, 0.5), 2.2, 9.0, "dying")   # living lamp
	_add_light(Vector3(4.9, 2.4, -2.5), Color(0.85, 0.9, 1.0), 1.6, 8.0, "steady")   # kitchen
	_add_light(Vector3(0.75, 2.4, -1.5), Color(1.0, 0.85, 0.65), 1.2, 7.0, "steady") # stair hall
	_add_light(Vector3(0.75, 5.1, -1.5), Color(1.0, 0.85, 0.65), 1.2, 7.0, "steady") # upper hall
	_add_light(Vector3(4.9, 5.0, -2.5), Color(1.0, 0.8, 0.6), 1.4, 8.0, "steady")    # bedroom
	_add_light(Vector3(-5.5, 5.0, -3.0), Color(0.8, 1.0, 0.9), 1.4, 6.0, "buzz")     # bathroom
	_add_light(Vector3(-4.0, 5.0, 3.0), Color(1.0, 0.85, 0.65), 1.0, 8.0, "steady")  # landing
	_add_light(Vector3(0.0, -0.4, 0.5), Color(0.65, 0.75, 1.0), 0.9, 12.0, "buzz")   # basement
	_add_light(Vector3(1.5, -1.2, -3.2), Color(1.0, 0.82, 0.6), 0.8, 6.0, "steady") # basement stair base
