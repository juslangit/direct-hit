extends Node3D

## A parade of all five hulls, photographed side-on and from above.
##
## The registry in ship_models.gd claims it can take five models in five
## different scales and headings and make them all float the same way. That
## claim cannot be checked by printing numbers - a ship sailing backwards has
## exactly the same bounding box as one sailing forwards. So each one gets
## photographed, and a person looks.

const SHOTS := "res://dev/shots/"

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await get_tree().process_frame
	for kind in Board.FLEET:
		await _photograph(kind)
	print("hull photos written to dev/shots/")
	get_tree().quit()

func _photograph(kind: Ship.Kind) -> void:
	var hull := ShipModels.build(kind)
	add_child(hull)
	await get_tree().process_frame

	var length := ShipModels.hull_length(kind)
	var box := ShipModels.measure(hull)
	var label: String = Ship.SPECS[kind]["name"].to_lower()
	print("%-11s spans %.1f (asked for %.1f)  beam %.1f  height %.1f  keel %.1f  deck %.1f" % [
		label, box.size.x, length, box.size.z, box.size.y, box.position.y, box.position.y + box.size.y,
	])

	# Side on, bow to the left, sea at the horizon.
	camera.position = Vector3(length * 0.5, length * 0.10, length * 0.85)
	camera.look_at(Vector3(length * 0.5, length * 0.03, 0.0))
	await _save("%s_side" % label)

	# Straight down, to check the hull runs along +X and is centred on Z.
	camera.position = Vector3(length * 0.5, length * 0.8, 0.0)
	camera.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	await _save("%s_top" % label)

	hull.queue_free()
	await get_tree().process_frame

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(SHOTS + name + ".png"))
