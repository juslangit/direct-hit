extends Node

## Did the cut take the right triangles?
##
## Paints each turret that was cut out a colour of its own and leaves the hull
## as it is, then photographs the foredeck from above and from the beam, at rest
## and hard over. Anything coloured that should not move, anything grey that
## should, and any hole in the deck is then a picture rather than an argument.

const SHOTS := "res://dev/shots/"
const TINTS := [Color(0.95, 0.10, 0.10), Color(0.10, 0.45, 1.0)]

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await get_tree().process_frame
	var env := WorldEnvironment.new()
	env.environment = Seascape.make_environment()
	add_child(env)
	add_child(Seascape.make_sun())

	var hull := ShipModels.build(Ship.Kind.BATTLESHIP)
	add_child(hull)
	var turrets := Turret.cut_from(hull)
	print("cut %d turrets: %s" % [turrets.size(), turrets.map(func(t): return t.name)])
	if turrets.is_empty():
		push_error("nothing was cut")
		get_tree().quit()
		return
	for i in turrets.size():
		var tint := StandardMaterial3D.new()
		tint.albedo_color = TINTS[i % TINTS.size()]
		tint.roughness = 0.6
		for skin in (turrets[i] as Turret).get_children():
			(skin as MeshInstance3D).material_override = tint

	var camera := Camera3D.new()
	camera.far = 4000.0
	camera.current = true
	add_child(camera)

	await _shot(camera, "cut_from_above", Vector3(76.0, 130.0, 0.0), Vector3(76.0, 10.0, 0.0), 40.0)
	await _shot(camera, "cut_from_the_beam", Vector3(76.0, 22.0, 120.0), Vector3(76.0, 13.0, 0.0), 40.0)
	for gun in turrets:
		(gun as Turret).snap_to(90.0)
	await _shot(camera, "cut_trained_above", Vector3(76.0, 130.0, 0.0), Vector3(76.0, 10.0, 0.0), 40.0)
	await _shot(camera, "cut_trained_beam", Vector3(76.0, 22.0, 120.0), Vector3(76.0, 13.0, 0.0), 40.0)

	print("cut views written")
	get_tree().quit()

func _shot(camera: Camera3D, name: String, eye: Vector3, at: Vector3, fov: float) -> void:
	camera.position = eye
	camera.fov = fov
	var direction := (at - eye).normalized()
	camera.look_at(at, Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD)
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path(SHOTS + name + ".png"))
