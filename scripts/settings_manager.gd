class_name SettingsManager
extends Node
## Persistent settings in user://settings.cfg: master volume, mouse
## sensitivity multiplier, invert Y. Applied at boot and on every change.
##
## Audio is still stubbed (see audio_manager.gd), so volume is stored and
## exposed on AudioManager.volume for the real implementation to use later.

const PATH := "user://settings.cfg"

var volume: int = 80  # 0..100
var sensitivity_mult: float = 1.0  # 0.5..2.0
var invert_y: bool = false

var _player: PlayerController
var _audio: AudioManager
var _base_sens: float = 0.0024


func setup(player: PlayerController, audio: AudioManager) -> void:
	_player = player
	_audio = audio
	_base_sens = player.mouse_sensitivity


func load_and_apply() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		volume = int(cfg.get_value("audio", "master_volume", volume))
		sensitivity_mult = float(cfg.get_value("input", "sensitivity", sensitivity_mult))
		invert_y = bool(cfg.get_value("input", "invert_y", invert_y))
	volume = clampi(volume, 0, 100)
	sensitivity_mult = clampf(sensitivity_mult, 0.5, 2.0)
	_apply()


func set_volume(v: int) -> void:
	volume = clampi(v, 0, 100)
	_apply()
	_save()


func set_sensitivity(m: float) -> void:
	sensitivity_mult = clampf(m, 0.5, 2.0)
	_apply()
	_save()


func set_invert_y(b: bool) -> void:
	invert_y = b
	_apply()
	_save()


func _apply() -> void:
	if _player != null:
		_player.mouse_sensitivity = _base_sens * sensitivity_mult
		_player.invert_y = invert_y
	if _audio != null:
		_audio.volume = volume / 100.0


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", volume)
	cfg.set_value("input", "sensitivity", sensitivity_mult)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.save(PATH)
