extends Node

## Every sound the game makes, in one place.
##
## Each clip is named for what happens rather than for the file it came from,
## so swapping a sound out is one line here and nothing anywhere else. All of
## them are CC0, downloaded with the `sfx` tool, and their provenance is in
## assets/audio/freesound/SOURCES.md.

const CLIPS := {
	"sea": "res://assets/audio/freesound/gentle_ocean_waves_loop.wav",
	"whistle": "res://assets/audio/freesound/incoming_mortar_1.ogg",
	"hit": "res://assets/audio/freesound/explosion05_wav.wav",
	"sink": "res://assets/audio/freesound/explosion01_wav.wav",
	# Converted from the FLAC it was downloaded as: this build of Godot has no
	# FLAC importer and drops the file without saying so, which is exactly the
	# kind of silence the asset check exists to break.
	"splash": "res://assets/audio/freesound/shell_splash.wav",
	"click": "res://assets/audio/freesound/dullthud_wav.wav",
}

const VOICES := 8

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _sea: AudioStreamPlayer

func _ready() -> void:
	for name in CLIPS:
		var path: String = CLIPS[name]
		if ResourceLoader.exists(path):
			_streams[name] = load(path)
		else:
			push_warning("missing sound: %s" % path)

	# A handful of players shared round-robin, so several sounds can overlap -
	# a shell landing while the sea is still running - without a player being
	# created for every single noise.
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_voices.append(player)

	_sea = AudioStreamPlayer.new()
	_sea.volume_db = -60.0
	add_child(_sea)
	if _streams.has("sea"):
		var stream = _streams["sea"]
		# A .wav arrives as a one-shot; the ambience has to be told to loop.
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = stream.data.size() / 2
		_sea.stream = stream

func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _streams.has(name):
		return
	var player := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	player.stream = _streams[name]
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()

## The sea comes up when the cutscene opens and goes away with it, rather than
## cutting in and out, which would announce every edit.
func sea(on: bool, seconds: float = 0.6) -> void:
	if _sea.stream == null:
		return
	if on and not _sea.playing:
		_sea.play()
	var tween := create_tween()
	tween.tween_property(_sea, "volume_db", -13.0 if on else -60.0, seconds)
	if not on:
		tween.tween_callback(_sea.stop)
