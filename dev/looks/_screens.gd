extends Node

## Every screen the player passes through, in order, menu first.
##
## The menu gets photographed first and deliberately: it is the one screen
## everybody sees, and it is the easiest to leave broken while polishing the
## parts that are more fun to work on.

const SHOTS := "res://dev/shots/"

var game: Node
var _report: Array = []

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await get_tree().process_frame
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(0.6).timeout
	await _save("ui_menu")

	game._begin(Game.Mode.VS_AI)
	await get_tree().create_timer(0.9).timeout
	game.bridge._preview(Vector2i(3, 4))
	await get_tree().process_frame
	await _save("ui_placement")

	game.bridge.scatter_fleet(Game.rng)
	game._update_place_hint()
	await get_tree().process_frame
	await _save("ui_placement_full")

	game._finish_placement()
	await get_tree().create_timer(0.9).timeout
	await _save("ui_battle_watch")

	# The war going on around the fleet: wrecks burning across the bows, and
	# somebody's aircraft going over.
	# Bearings to starboard are yaw 90 plus the bearing; the wrecks are at 22
	# and 63 degrees green.
	game.bridge._yaw = deg_to_rad(90.0 + 30.0)
	game.bridge._pitch = deg_to_rad(-1.0)
	game.bridge.head.rotation.y = game.bridge._yaw
	game.bridge.camera.rotation.x = game.bridge._pitch
	await get_tree().process_frame
	await _save("ui_war_horizon")

	game.bridge._pitch = deg_to_rad(26.0)
	game.bridge.camera.rotation.x = game.bridge._pitch
	await get_tree().process_frame
	await _save("ui_war_sky")

	game.bridge._pitch = deg_to_rad(-2.0)
	game.bridge.camera.rotation.x = game.bridge._pitch

	# Mark a square and go to the sight, the way a turn actually runs.
	game.bridge.set_mode(1)
	await get_tree().create_timer(0.8).timeout
	game.bridge._on_cell_picked(Vector2i(5, 3))
	await get_tree().process_frame
	await _save("ui_battle_plot")

	game.bridge.set_mode(2)
	await get_tree().create_timer(0.9).timeout
	await _save("ui_battle_sight")

	FileAccess.open("user://shots.txt", FileAccess.WRITE).store_string("\n".join(_report))
	print("screen photos written")
	get_tree().quit()

func _save(name: String) -> void:
	# Let the frame settle. Two post-draws is not always enough: a camera that
	# was moved this frame can still be photographed a frame behind, which
	# produced a set of pictures that disagreed with the angles recorded
	# alongside them.
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var cam: Camera3D = game.bridge.camera
	_report.append("%-22s yaw %7.1f  pitch %7.1f  mode %d  fov %5.1f" % [
		name, rad_to_deg(game.bridge.head.rotation.y), rad_to_deg(cam.rotation.x),
		game.bridge.mode, cam.fov])
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(SHOTS + name + ".png"))
