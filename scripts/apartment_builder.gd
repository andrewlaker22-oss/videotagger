class_name ApartmentBuilder
extends Node3D
## Procedurally builds the WATCHED apartment from data tables.
##
## All geometry is primitives (boxes, quads) with dark, moody materials —
## pure placeholder art. Nothing here is load-bearing for the story: the
## GameManager only calls open_front_door(), set_blackout() and
## disable_all_interactables(). To replace placeholders with real art, see
## assets/README.md.
##
## Floor plan (meters, XZ plane, y-up). Apartment: x in [-6, 6], z in [-4, 4].
## Hallway stub: x in [-10, -6], z in [-1.5, 1.5]. Front door in the west wall.
## Rooms: entry/living (west, open), kitchen (east-north), bedroom
## (east-south), bathroom (small, carved out of the living area).

const WALL_H := 3.0
const WALL_T := 0.18

# Wall segments as [Vector2, Vector2] in the XZ plane. Door gaps are made by
# splitting a wall into two segments; see the plan above.
const WALLS: Array = [
	# Outer shell (west wall has the front-door gap, z in [-0.55, 0.55]).
	[Vector2(-6, -4), Vector2(6, -4)],
	[Vector2(-6, 4), Vector2(6, 4)],
	[Vector2(6, -4), Vector2(6, 4)],
	[Vector2(-6, -4), Vector2(-6, -0.55)],
	[Vector2(-6, 0.55), Vector2(-6, 4)],
	# Hallway stub.
	[Vector2(-10, -1.5), Vector2(-6, -1.5)],
	[Vector2(-10, 1.5), Vector2(-6, 1.5)],
	[Vector2(-10, -1.5), Vector2(-10, 1.5)],
	# Partition x=2 (living | kitchen/bedroom). Gaps: kitchen door z in
	# [-2.6, -1.4], bedroom door z in [1.6, 2.8].
	[Vector2(2, -4), Vector2(2, -2.6)],
	[Vector2(2, -1.4), Vector2(2, 1.6)],
	[Vector2(2, 2.8), Vector2(2, 4)],
	# Partition z=0 (kitchen | bedroom).
	[Vector2(2, 0), Vector2(6, 0)],
	# Bathroom (x in [-1, 2], z in [-4, -1.5]). Door gap z in [-3.2, -2.2].
	[Vector2(-1, -4), Vector2(-1, -3.2)],
	[Vector2(-1, -2.2), Vector2(-1, -1.5)],
	[Vector2(-1, -1.5), Vector2(2, -1.5)],
]

var _mats: Dictionary = {}
var _lights: Array = []  # Dictionaries: {node, base, mode, phase}.
var _blackout: bool = false
var _door_pivot: Node3D = null
var _door_open: bool = false


func _ready() -> void:
	_make_materials()
	_build_shell()
	_build_hallway_props()
	_build_living_room()
	_build_kitchen()
	_build_bedroom()
	_build_bathroom()
	_build_front_door()
	_build_interactables()
	_build_lights()


func _process(delta: float) -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	for entry in _lights:
		var l: OmniLight3D = entry["node"]
		if _blackout:
			l.light_energy = maxf(0.0, l.light_energy - delta * 6.0)
			continue
		var base: float = entry["base"]
		var phase: float = entry["phase"]
		var e := base
		match String(entry["mode"]):
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


# ------------------------------------------------------------------
# Public API used by the GameManager
# ------------------------------------------------------------------

func open_front_door() -> void:
	if _door_open or _door_pivot == null:
		return
	_door_open = true
	var tw := create_tween()
	tw.tween_property(_door_pivot, "rotation:y", 1.85, 1.6).set_trans(Tween.TRANS_SINE)


func set_blackout(value: bool) -> void:
	_blackout = value


func disable_all_interactables() -> void:
	for child in get_children():
		if child is Interactable:
			(child as Interactable).disable()


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


func _add_wall(a: Vector2, b: Vector2) -> void:
	var length := a.distance_to(b)
	var center := (a + b) * 0.5
	var angle := atan2(b.x - a.x, b.y - a.y)
	_add_box(Vector3(WALL_T, WALL_H, length), Vector3(center.x, WALL_H * 0.5, center.y), "wall", angle)


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
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = extents * 2.0
	cs.shape = shape
	inter.add_child(cs)
	add_child(inter)
	return inter


# ------------------------------------------------------------------
# Rooms
# ------------------------------------------------------------------

func _build_shell() -> void:
	for w in WALLS:
		_add_wall(w[0], w[1])
	# Floors and ceilings (slightly oversized to seal corners).
	_add_box(Vector3(12.6, 0.1, 8.6), Vector3(0, -0.05, 0), "floor")
	_add_box(Vector3(12.6, 0.1, 8.6), Vector3(0, 3.05, 0), "ceiling")
	_add_box(Vector3(4.6, 0.1, 3.6), Vector3(-8, -0.05, 0), "floor")
	_add_box(Vector3(4.6, 0.1, 3.6), Vector3(-8, 3.05, 0), "ceiling")


func _build_hallway_props() -> void:
	# Bare hallway: a flickering cool light is all it gets.
	pass


func _build_living_room() -> void:
	# Couch (faces +z, toward the TV on the south wall).
	_add_box(Vector3(2.2, 0.45, 0.95), Vector3(-3.5, 0.225, 1.8), "fabric")
	_add_box(Vector3(2.2, 0.75, 0.28), Vector3(-3.5, 0.7, 1.35), "fabric")
	_add_box(Vector3(0.28, 0.65, 0.95), Vector3(-4.6, 0.55, 1.8), "fabric")
	_add_box(Vector3(0.28, 0.65, 0.95), Vector3(-2.4, 0.55, 1.8), "fabric")
	# Coffee table and rug.
	_add_box(Vector3(1.2, 0.4, 0.6), Vector3(-3.5, 0.2, 2.9), "wood")
	_add_box(Vector3(3.0, 0.03, 2.0), Vector3(-3.5, 0.015, 2.4), "fabric_dark", 0.0, false)
	# TV stand + dead TV.
	_add_box(Vector3(1.8, 0.5, 0.5), Vector3(-3.5, 0.25, 3.65), "wood")
	_add_box(Vector3(1.5, 0.85, 0.12), Vector3(-3.5, 1.15, 3.65), "dark")
	_add_quad(Vector2(1.35, 0.7), Vector3(-3.5, 1.15, 3.58), "screen", PI)
	# Floor lamp beside the TV stand (placeholder boxes + emissive shade).
	_add_box(Vector3(0.3, 0.06, 0.3), Vector3(-2.3, 0.03, 3.55), "dark")
	_add_box(Vector3(0.06, 1.6, 0.06), Vector3(-2.3, 0.8, 3.55), "dark")
	_add_box(Vector3(0.4, 0.32, 0.4), Vector3(-2.3, 1.72, 3.55), "lamp_glow", 0.0, false)
	# Floor lamp (the flickering warm light lives here).
	_add_box(Vector3(0.06, 1.7, 0.06), Vector3(-5.0, 0.85, 0.6), "dark")
	_add_box(Vector3(0.35, 0.3, 0.35), Vector3(-5.0, 1.8, 0.6), "lamp_glow", 0.0, false)


func _build_kitchen() -> void:
	# Counter run along the north wall.
	_add_box(Vector3(2.6, 0.9, 0.65), Vector3(4.0, 0.45, -3.62), "wood")
	# Stove.
	_add_box(Vector3(0.7, 0.9, 0.65), Vector3(2.6, 0.45, -3.62), "dark")
	# Fridge with the note on its front (front face at z = -3.15).
	_add_box(Vector3(0.85, 1.9, 0.8), Vector3(5.45, 0.95, -3.55), "appliance")
	_add_box(Vector3(0.05, 0.5, 0.06), Vector3(5.12, 1.2, -3.13), "metal", 0.0, false)
	_add_quad(Vector2(0.28, 0.34), Vector3(5.45, 1.35, -3.14), "paper")
	# The knife, displayed in the middle of the counter.
	_add_box(Vector3(0.28, 0.015, 0.045), Vector3(4.0, 0.93, -3.62), "metal", 0.5, false)
	_add_box(Vector3(0.12, 0.03, 0.05), Vector3(3.82, 0.93, -3.55), "dark", 0.5, false)


func _build_bedroom() -> void:
	# Bed.
	_add_box(Vector3(1.3, 0.3, 2.1), Vector3(4.6, 0.15, 2.9), "wood")
	_add_box(Vector3(1.24, 0.25, 2.04), Vector3(4.6, 0.42, 2.9), "bedding")
	_add_box(Vector3(0.7, 0.12, 0.4), Vector3(4.6, 0.6, 2.0), "paper", 0.0, false)
	_add_box(Vector3(1.24, 0.08, 1.2), Vector3(4.6, 0.58, 3.3), "fabric_dark", 0.0, false)
	# Nightstand with the framed photo.
	_add_box(Vector3(0.55, 0.55, 0.55), Vector3(3.35, 0.275, 3.5), "wood")
	_add_box(Vector3(0.22, 0.28, 0.04), Vector3(3.35, 0.7, 3.5), "dark", 0.0, false)
	# Wardrobe / closet.
	_add_box(Vector3(1.3, 2.0, 0.6), Vector3(5.35, 1.0, 3.55), "wood")
	_add_box(Vector3(0.04, 0.18, 0.04), Vector3(5.15, 1.1, 3.23), "metal", 0.0, false)
	_add_box(Vector3(0.04, 0.18, 0.04), Vector3(5.55, 1.1, 3.23), "metal", 0.0, false)


func _build_bathroom() -> void:
	# Sink + mirror (mirror faces +z, into the room).
	_add_box(Vector3(0.35, 0.7, 0.35), Vector3(1.3, 0.35, -3.6), "appliance")
	_add_box(Vector3(0.6, 0.15, 0.5), Vector3(1.3, 0.78, -3.6), "appliance")
	_add_quad(Vector2(0.7, 0.9), Vector3(1.3, 1.7, -3.9), "mirror")
	# Toilet.
	_add_box(Vector3(0.45, 0.4, 0.6), Vector3(0.1, 0.2, -3.55), "appliance")
	_add_box(Vector3(0.45, 0.5, 0.2), Vector3(0.1, 0.65, -3.8), "appliance")
	# Tub.
	_add_box(Vector3(1.7, 0.55, 0.75), Vector3(-0.35, 0.275, -2.0), "appliance")
	# Fluorescent tube fixture.
	_add_box(Vector3(1.2, 0.06, 0.15), Vector3(0.5, 2.95, -2.75), "tube_glow", 0.0, false)


func _build_front_door() -> void:
	# Hinged at the north edge of the doorway (x=-6, z=-0.55); the panel
	# extends +z when closed. Slightly ajar at start; open_door() swings it
	# ~106 degrees into the apartment.
	_door_pivot = Node3D.new()
	_door_pivot.position = Vector3(-6, 0, -0.55)
	_door_pivot.rotation.y = 0.15
	add_child(_door_pivot)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 2.1, 1.06)
	mi.mesh = bm
	mi.material_override = _mat_by("door")
	mi.position = Vector3(0, 1.05, 0.53)
	_door_pivot.add_child(mi)


func _build_interactables() -> void:
	# interact_id must match a key in StoryData.get_trigger_beats().
	_add_interactable("fridge_note", "Read the note", Vector3(5.45, 1.35, -2.95), Vector3(0.4, 0.4, 0.3))
	_add_interactable("bedroom_photo", "Look at the photo", Vector3(3.35, 0.85, 3.5), Vector3(0.35, 0.35, 0.35))
	_add_interactable("bedroom_closet", "Open the closet", Vector3(5.35, 1.1, 3.1), Vector3(0.7, 0.8, 0.3))
	_add_interactable("bathroom_mirror", "Look in the mirror", Vector3(1.3, 1.6, -3.5), Vector3(0.45, 0.55, 0.3))
	_add_interactable("kitchen_knife", "Look at the knife", Vector3(4.0, 1.1, -3.3), Vector3(0.5, 0.4, 0.4))


func _build_lights() -> void:
	# (position, color, energy, range, flicker mode)
	_add_light(Vector3(-8, 2.6, 0), Color(0.6, 0.7, 1.0), 1.2, 7.0, "buzz")      # hallway
	_add_light(Vector3(-5.0, 1.9, 0.6), Color(1.0, 0.75, 0.5), 2.2, 9.0, "dying") # living lamp
	_add_light(Vector3(-2.3, 1.65, 3.55), Color(1.0, 0.8, 0.55), 1.4, 6.0, "steady") # TV lamp
	_add_light(Vector3(4, 2.6, -2), Color(0.85, 0.9, 1.0), 1.6, 7.0, "steady")    # kitchen
	_add_light(Vector3(4, 2.5, 2), Color(1.0, 0.8, 0.6), 1.2, 7.0, "steady")      # bedroom
	_add_light(Vector3(0.5, 2.7, -2.75), Color(0.8, 1.0, 0.9), 1.4, 6.0, "buzz")  # bathroom
