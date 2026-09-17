extends Node3D

## A parade of all five hulls, on real water, photographed from close by.
##
## The first version of this scene had no sea in it at all - the ships floated
## over the sky's ground colour - so it could prove a hull was the right size
## and the right way round, and could say nothing at all about how deep she
## sat. Every one of them was riding with her main deck under water and nobody
## could tell until the player stood on one.

const SHOTS := "res://dev/shots/"

var camera: Camera3D

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var env := WorldEnvironment.new()
	env.environment = Seascape.make_environment()
	add_child(env)
	add_child(Seascape.make_sun())
	Seascape.build_water(self)

	camera = Camera3D.new()
	camera.far = 24000.0
	camera.current = true
	add_child(camera)
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
	print("%-11s spans %.1f  beam %.1f  keel %.1f  top %.1f" % [
		label, box.size.x, box.size.z, box.position.y, box.position.y + box.size.y])

	# Side on, bow to the left, from just above the water - the angle that
	# shows how she is sitting.
	camera.position = Vector3(length * 0.5, length * 0.055, length * 0.62)
	camera.look_at(Vector3(length * 0.5, length * 0.03, 0.0))
	await _save("%s_side" % label)

	# Close in on the bow, where too much draft shows first.
	camera.position = Vector3(length * 0.10, length * 0.05, length * 0.22)
	camera.look_at(Vector3(length * 0.12, 0.0, 0.0))
	await _save("%s_bow" % label)

	hull.queue_free()
	await get_tree().process_frame

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(SHOTS + name + ".png"))
