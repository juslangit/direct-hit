extends Node

## Inside the wheelhouse, looking each way.
##
## Everything about this is a judgement a person has to make: whether it reads
## as a room rather than a floating platform, whether the window frame holds the
## sea without hiding your own foredeck, and whether the fittings behind you
## look like a bridge or like boxes on a floor.

const SHOTS := "res://dev/shots/"

var bridge: Node3D

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await get_tree().process_frame
	bridge = (load("res://scenes/bridge.tscn") as PackedScene).instantiate()
	add_child(bridge)
	await get_tree().create_timer(0.6).timeout

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var board := Board.new()
	board.random_layout(rng)
	for cell in [Vector2i(2, 3), Vector2i(7, 1), Vector2i(4, 6), Vector2i(5, 6), Vector2i(9, 9)]:
		board.fire(cell)
	bridge.set_enemy_board(board)
	bridge._on_cell_picked(Vector2i(6, 4))
	await get_tree().process_frame

	await _watch("br_ahead", 0.0, -3.0)
	await _watch("br_ahead_down", 0.0, -20.0)
	await _watch("br_port_window", 88.0, -4.0)
	await _watch("br_the_wheel", 172.0, -9.0)
	await _watch("br_aft_quarter", 128.0, -6.0)
	# Straight at the sun in the panorama. If the light and the sky agree, the
	# glitter path on the water runs from the ship to the sun's own disc; if
	# they do not, the water shines in one direction and the sky burns in
	# another, and the picture quietly stops making sense.
	await _watch("br_into_the_sun", -54.0, 22.0)

	bridge.set_mode(1)
	await get_tree().create_timer(0.9).timeout
	await _save("br_plot_table")

	bridge.set_mode(2)
	await get_tree().create_timer(0.9).timeout
	await _save("br_sight")

	print("bridge views written")
	get_tree().quit()

## Point the head so many degrees off the bow - positive to starboard - and
## photograph it.
func _watch(name: String, off_bow: float, pitch: float) -> void:
	bridge.set_mode(0)
	await get_tree().process_frame
	bridge._yaw = deg_to_rad(90.0 + off_bow)
	bridge._pitch = deg_to_rad(pitch)
	bridge.head.rotation.y = bridge._yaw
	bridge.camera.rotation.x = bridge._pitch
	await _save(name)

func _save(name: String) -> void:
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(SHOTS + name + ".png"))
