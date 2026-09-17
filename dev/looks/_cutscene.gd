extends Node

## Photographs of a hit, beat by beat.
##
## The cutscene is three seconds long and the interesting parts are a tenth of
## a second each, so watching it is a poor way to find out whether the shell
## lands on the right part of the ship. This drives it from the outside and
## saves a frame at each beat.

const SHOTS := "res://dev/shots/"
const BEATS := [0.35, 0.80, 1.10, 1.35, 2.10, 3.60]
const SINK_BEATS := [1.10, 2.40, 4.00, 5.60, 7.20]

var _scene: Node3D

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await get_tree().process_frame

	# A hit amidships on the battleship, then a carrier going down.
	await _run("hit", {"outcome": "hit", "ship_kind": Ship.Kind.BATTLESHIP, "segment": 1, "length": 4}, BEATS)
	await _run("sunk", {"outcome": "sunk", "ship_kind": Ship.Kind.CARRIER, "segment": 3, "length": 5}, SINK_BEATS)
	# And the smallest ship taking one on the bow, to check the framing holds
	# when the hull is a quarter the length.
	await _run("small", {"outcome": "hit", "ship_kind": Ship.Kind.DESTROYER, "segment": 0, "length": 2}, [1.10, 1.60])
	print("cutscene photos written to dev/shots/")
	get_tree().quit()

func _run(label: String, report: Dictionary, beats: Array) -> void:
	_scene = (load("res://scenes/cutscene.tscn") as PackedScene).instantiate()
	add_child(_scene)
	await get_tree().process_frame
	_scene.play(report)

	var elapsed := 0.0
	for beat in beats:
		var wait: float = float(beat) - elapsed
		if wait > 0.0:
			await get_tree().create_timer(wait).timeout
			elapsed = float(beat)
		await _save("%s_%0.2f" % [label, beat])
	_scene.queue_free()
	await get_tree().process_frame

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(SHOTS + "cut_" + name.replace(".", "p") + ".png"))
