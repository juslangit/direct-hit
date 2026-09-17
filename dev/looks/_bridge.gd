extends Node

## The bridge, in each of the three things the player can be doing.
##
## Everything here is a judgement a person has to make: whether the foredeck
## reads as your own ship, whether the fleet around you looks like a fleet,
## whether the plot on the water can be found at six kilometres, and whether
## the gun sight feels like an optic rather than a cursor.

const SHOTS := "res://dev/shots/"

var bridge: Node3D

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await get_tree().process_frame
	bridge = (load("res://scenes/bridge.tscn") as PackedScene).instantiate()
	add_child(bridge)
	await get_tree().create_timer(0.5).timeout

	# An enemy board part way through a battle, so the plot has something on it.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var board := Board.new()
	board.random_layout(rng)
	for cell in [Vector2i(2, 3), Vector2i(7, 1), Vector2i(4, 6), Vector2i(5, 6), Vector2i(9, 9)]:
		board.fire(cell)
	bridge.set_enemy_board(board)
	bridge._on_cell_picked(Vector2i(6, 4))
	await get_tree().process_frame

	await _watch("br_ahead", 0.0, -2.0)
	await _watch("br_enemy_bearing", -34.0, -1.0)
	await _watch("br_port_beam", 78.0, -4.0)
	await _watch("br_astern", 175.0, -3.0)

	bridge.set_mode(1)  # PLOT
	await get_tree().create_timer(0.8).timeout
	await _save("br_plot_table")

	bridge.set_mode(2)  # SIGHT
	await get_tree().create_timer(0.8).timeout
	await _save("br_sight")

	print("bridge views written")
	get_tree().quit()

## Point the head somewhere, in degrees off the bow, and photograph it.
func _watch(name: String, off_bow: float, pitch: float) -> void:
	bridge.set_mode(0)
	await get_tree().process_frame
	bridge._yaw = deg_to_rad(90.0 - off_bow)
	bridge._pitch = deg_to_rad(pitch)
	bridge.head.rotation.y = bridge._yaw
	bridge.camera.rotation.x = bridge._pitch
	await _save(name)

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(SHOTS + name + ".png"))
