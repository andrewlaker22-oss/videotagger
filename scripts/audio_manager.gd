class_name AudioManager
extends Node
## Placeholder audio system.
##
## Every sound in the game goes through play_sfx() / play_music() so that
## adding real audio later means touching ONE file, not the whole codebase.
## Right now the hooks just print; see audio/README.md for the full list of
## sfx names the game requests and how to wire real files up.
##
## TODO(audio): implement for real. Suggested approach:
##   1. Drop .ogg/.wav files into audio/sfx/ and audio/music/ (see audio/README.md).
##   2. Give this node a pool of AudioStreamPlayer children (say 8) created in
##      _ready(), plus one dedicated AudioStreamPlayer for music.
##   3. In play_sfx(): load("res://audio/sfx/%s.ogg" % sfx_name) once, cache it
##      in a Dictionary, and play it on the first free player in the pool.
##   4. In play_music(): assign to the music player and play(); stop_music()
##      stops it. Consider a short fade via tween on volume_db.
##   5. Delete the print() calls below once real playback exists.

var _cache: Dictionary = {}  # sfx_name -> AudioStream. TODO(audio): fill me.


func play_sfx(sfx_name: String) -> void:
	# TODO(audio): replace with pooled AudioStreamPlayer playback.
	print("[AudioManager] sfx: ", sfx_name)


func play_music(track_name: String) -> void:
	# TODO(audio): replace with music AudioStreamPlayer playback.
	print("[AudioManager] music: ", track_name)


func stop_music() -> void:
	# TODO(audio): replace with music player stop (with fade).
	print("[AudioManager] music stopped")
