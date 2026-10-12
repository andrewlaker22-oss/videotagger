class_name PlayerController
extends CharacterBody3D
## First-person controller: WASD + mouse look, E / click to interact.
##
## The player never knows about game state. It emits raw input signals and
## the GameManager routes them based on the current state (EXPLORE / DIALOGUE /
## CHOICE / ENDING). Focus detection (what the crosshair ray hits) is reported
## via focus_changed so the GameManager can show the "[E] ..." prompt.

signal primary_action          # E key or left-click while mouse is captured.
signal choice_hotkey(index: int)  # Number keys 1-4, used for dialogue choices.
signal focus_changed(interactable)  # Interactable under the crosshair, or null.

@export var move_speed: float = 3.4
@export var mouse_sensitivity: float = 0.0024
@export var look_min: float = -1.35
@export var look_max: float = 1.35

var control_locked: bool = true   # Blocks movement + look (dialogue, choices).
var allow_capture: bool = true    # May a click re-capture the mouse? Off during choices.
var speed_factor: float = 1.0     # Movement multiplier (e.g. slower while carrying trash).
var current: Interactable = null  # Interactable currently under the crosshair.

var _shake: float = 0.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var ray: RayCast3D = $Head/Camera3D/InteractRay


func _ready() -> void:
	# The interact ray starts inside the player's own capsule; ignore it.
	ray.add_exception(self)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if look_enabled() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var mm := event as InputEventMouseMotion
			rotate_y(-mm.relative.x * mouse_sensitivity)
			head.rotate_x(-mm.relative.y * mouse_sensitivity)
			head.rotation.x = clampf(head.rotation.x, look_min, look_max)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				if allow_capture:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				primary_action.emit()
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			match k.physical_keycode:
				KEY_E:
					primary_action.emit()
				KEY_ESCAPE:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				KEY_1:
					choice_hotkey.emit(0)
				KEY_2:
					choice_hotkey.emit(1)
				KEY_3:
					choice_hotkey.emit(2)
				KEY_4:
					choice_hotkey.emit(3)


func look_enabled() -> bool:
	return not control_locked


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	elif velocity.y < 0.0:
		velocity.y = -1.0

	var dir := Vector3.ZERO
	if not control_locked:
		var ix: float = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		var iz: float = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
		dir = global_transform.basis * Vector3(ix, 0.0, iz)
		dir.y = 0.0
		if dir.length() > 0.01:
			dir = dir.normalized()
	velocity.x = dir.x * move_speed * speed_factor
	velocity.z = dir.z * move_speed * speed_factor
	move_and_slide()

	_update_focus()
	_update_shake(delta)


func _update_focus() -> void:
	var found: Interactable = null
	if not control_locked and ray.is_colliding():
		var col: Object = ray.get_collider()
		if col is Interactable:
			var inter := col as Interactable
			if inter.enabled:
				found = inter
	if found != current:
		current = found
		focus_changed.emit(current)


## Trauma-based camera shake (0..1). Used for the blackout scare.
func add_shake(amount: float) -> void:
	_shake = minf(1.0, _shake + amount)


func _update_shake(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.6)
		camera.h_offset = randf_range(-1.0, 1.0) * _shake * 14.0
		camera.v_offset = randf_range(-1.0, 1.0) * _shake * 14.0
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
