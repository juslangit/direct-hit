extends Node3D

## Where is the sun in the sky image, and does the game's sun agree with it?
##
## A panorama sky has its own sun painted into it. If the DirectionalLight is
## aimed somewhere else, the shadows on the ships fall one way while the sky
## says the light comes from another - a mistake nobody can name when they see
## it but everybody can feel.
##
## So the brightest point in the panorama is found, converted from its place in
## the image to a direction in the world, and then - because the mapping from
## one to the other is a convention that is easy to get backwards - the answer
## is checked by aiming a camera down that direction and confirming the sun
## really is in the middle of the picture.

const HDRI := "res://assets/hdri/kloofendal_38d_partly_cloudy_puresky_4k.hdr"
const SHOTS := "res://dev/shots/"

var camera: Camera3D
var failures := 0

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(900, 900))
	var texture: Texture2D = load(HDRI)
	var image := texture.get_image()
	var found := _brightest(image)
	var direction := _direction_from_uv(found)

	print("panorama %dx%d" % [image.get_width(), image.get_height()])
	print("brightest at uv (%.4f, %.4f)" % [found.x, found.y])
	print("sun direction  %s" % str(direction))
	print("sun rotation   %s   <- put this on the DirectionalLight3D" % str(
		Basis.looking_at(-direction).get_euler() * 180.0 / PI))

	# Now prove it, by looking straight down that direction.
	var env := WorldEnvironment.new()
	env.environment = _sky_only(texture)
	add_child(env)
	camera = Camera3D.new()
	camera.fov = 30.0
	camera.current = true
	add_child(camera)
	camera.look_at_from_position(Vector3.ZERO, direction, Vector3.UP)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var shot := get_viewport().get_texture().get_image()
	shot.save_png(ProjectSettings.globalize_path(SHOTS + "sun_check.png"))
	var on_screen := _brightest(shot)
	var off_centre := (on_screen - Vector2(0.5, 0.5)).length()
	print("brightest point on screen at (%.3f, %.3f), %.3f from the middle" % [
		on_screen.x, on_screen.y, off_centre])
	if off_centre < 0.12:
		print("  ok    the sun is where the maths said it would be")
	else:
		failures += 1
		print("  FAIL  looking down the computed direction does not find the sun")
	print("SUNANGLE: %s" % ("passed" if failures == 0 else "FAILED"))
	get_tree().quit(1 if failures > 0 else 0)

## The middle of the brightest thing in the image, as a 0..1 position.
##
## The middle, not the first brightest pixel. The sun is a disc covering many
## pixels, and on a rendered frame it blows out to pure white across all of
## them - so "the first pixel that is brighter than everything before it"
## returns the top-left corner of that blob, which is how this check first
## reported the sun to be in the corner of a picture pointed straight at it.
func _brightest(image: Image) -> Vector2:
	var small := image.duplicate()
	small.resize(mini(image.get_width(), 1024), mini(image.get_height(), 512), Image.INTERPOLATE_BILINEAR)
	var width: int = small.get_width()
	var height: int = small.get_height()

	var peak := 0.0
	for y in height:
		for x in width:
			var c: Color = small.get_pixel(x, y)
			peak = maxf(peak, c.r + c.g + c.b)
	if peak <= 0.0:
		return Vector2(0.5, 0.5)

	# Everything within a whisker of the peak, averaged.
	var floor_energy: float = peak * 0.97
	var sum := Vector2.ZERO
	var count := 0.0
	for y in height:
		for x in width:
			var c: Color = small.get_pixel(x, y)
			if c.r + c.g + c.b >= floor_energy:
				sum += Vector2(float(x) + 0.5, float(y) + 0.5)
				count += 1.0
	return Vector2(sum.x / count / float(width), sum.y / count / float(height))

## Equirectangular: u runs round the horizon, v from straight up to straight
## down. This is the exact inverse of what a panorama sky samples with, which
## in Godot is
##
##     u = atan2(dir.x, -dir.z) / 2pi   (wrapped into 0..1)
##     v = acos(dir.y) / pi
##
## Both halves of that are easy to get wrong in a way nothing complains about:
## measuring the angle from the middle of the image rather than from its edge
## mirrors the whole sky, and the sun comes out on the wrong side of the ship.
func _direction_from_uv(uv: Vector2) -> Vector3:
	var theta := uv.x * TAU
	var phi := uv.y * PI
	var radius := sin(phi)
	return Vector3(radius * sin(theta), cos(phi), -radius * cos(theta)).normalized()

func _sky_only(texture: Texture2D) -> Environment:
	var material := PanoramaSkyMaterial.new()
	material.panorama = texture
	var sky := Sky.new()
	sky.sky_material = material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	return env
