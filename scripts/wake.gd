class_name Wake
extends MeshInstance3D

## The water a ship leaves behind her.
##
## Five ships making fourteen knots across a sea with no wake on it are five
## ships at anchor, and that was the loudest thing wrong with the picture from
## the bridge: the swell moved, the funnel smoke drifted, and the hulls sat in
## the water like models on a mirror. A wake is the only thing in the frame that
## says a ship is under way.
##
## **This is a strip of mesh and not a particle system, and it is worth saying
## why, because it was a particle system first.** A wake looks like something
## particles are for - churned water dispersing - so the first version dropped
## patches of foam at the stern and let them grow. Two things went wrong. It was
## ruinously expensive: eight hundred and fifty alpha-blended quads up to eighty
## metres across, with depth writing off so that nothing could reject a single
## fragment, took one set of screenshots from eleven seconds to over five
## minutes. And it did not even look right - at a rate that kept the cost down,
## the patches read as separate blobs of suds rather than a continuous track,
## which is worse than no wake on a sea already speckled with whitecaps.
##
## A strip has none of those problems. It is one draw call of about two hundred
## triangles, one layer of transparency deep, the same on every frame, and its
## shape is exactly the shape a wake has rather than an emergent approximation
## of it. The one thing a strip cannot do is stay where it was made when the
## ship turns - but she never turns. She steams in a straight line at a constant
## speed for the whole game, and along that line a strip fixed to her stern and
## a track left in the water are the same picture.
##
## What keeps it from reading as paint is the texture. A strip rigidly attached
## to the ship would have its foam slide along with her; instead the foam is
## scrolled astern at exactly the speed she is making, so the pattern stands
## still in the water while the strip that carries it moves. Same trick as the
## particles, done in a texture coordinate rather than in a velocity.

## How far astern the track is drawn. A real one is visible for miles; this is
## as much as is worth drawing before haze and distance take it.
const LENGTH := 190.0

## How many segments down that length. Enough that the taper is a taper rather
## than a series of steps.
const SEGMENTS := 30

## How wide the churn is at the stern and at the tail, in beams. Narrower than
## the hull where it leaves her, because what makes it is the screws and not the
## whole ship; a little under three beams by the far end, which is about ten
## degrees of divergence.
const AT_STERN := 0.38
const AT_TAIL := 1.32

const SHADER := "res://assets/shaders/wake.gdshader"

## How long a stretch of water one tile of foam covers. The texture repeats
## along the track, and this is the only thing that sets the size of the detail
## in it.
const TILE := 42.0

var speed := 0.0
var _scroll := 0.0
var _material: ShaderMaterial

## Build the track for a ship of this beam, making this speed.
static func astern_of(beam: float, speed: float) -> Wake:
	var wake := Wake.new()
	wake.name = "Wake"
	wake.speed = speed
	wake.mesh = _strip(beam)
	wake._material = _foam()
	wake.material_override = wake._material
	wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The strip is built astern of its own origin and the sea is flat, so its
	# own bounds are honest - but it is long and thin and lies in the one plane
	# the camera is usually nearly edge-on to, which is where Godot's own
	# culling is least kind. A little margin costs nothing here.
	wake.extra_cull_margin = LENGTH
	return wake

## The strip itself: five columns of vertices running astern, widening.
##
## Five rather than three because of what the alpha across them is for. A wake
## is not a uniform white band - it is two bright divergent waves with the
## screws' churn between them, and it is those two bright lines that read as a
## wake from a distance. So the outer columns fade to nothing, the two inside
## them carry the waves at full strength, and the middle sits between: churn,
## brighter than the sea and duller than the waves either side of it.
static func _strip(beam: float) -> ArrayMesh:
	var across := [-1.0, -0.55, 0.0, 0.55, 1.0]
	var weight := [0.0, 1.0, 0.55, 1.0, 0.0]

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var index := PackedInt32Array()

	for row in SEGMENTS + 1:
		var along := float(row) / float(SEGMENTS)
		var half: float = beam * lerpf(AT_STERN, AT_TAIL, along)
		# Strong where the screws are and fading all the way astern. Squared,
		# because a linear fade leaves a visible end to the track: the eye reads
		# the tail as being cut off rather than as having dispersed. The first
		# few metres ramp up instead of starting at full strength, so the track
		# begins under her stern rather than at a hard line across it.
		var fade: float = pow(1.0 - along, 1.7) * smoothstep(0.0, 0.03, along)
		for column in across.size():
			verts.append(Vector3(along * LENGTH, 0.0, across[column] * half))
			normals.append(Vector3.UP)
			uvs.append(Vector2((across[column] + 1.0) * 0.5, along * LENGTH / TILE))
			colors.append(Color(1.0, 1.0, 1.0, fade * float(weight[column])))

	var columns := across.size()
	for row in SEGMENTS:
		for column in columns - 1:
			var here := row * columns + column
			var next := here + columns
			# Wound so the faces look up at a player who is always above them.
			index.append(here)
			index.append(next)
			index.append(here + 1)
			index.append(here + 1)
			index.append(next)
			index.append(next + 1)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = index

	var strip := ArrayMesh.new()
	strip.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return strip

## The foam, on a shader rather than a standard material.
##
## It has to be a shader for one reason: the strip is built flat, and the sea it
## lies on is displaced in its own vertex shader by four Gerstner waves. A flat
## strip on a two-metre swell is cut in half by the first crest that rises above
## it - which is exactly what the first version did, and it read as the wake
## being interrupted rather than as the wake being in a sea. So the strip is
## displaced by the same waves, out of the same include, and rides the swell.
static func _foam() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	m.set_shader_parameter("tint", Color(0.90, 0.94, 0.96, 0.85))
	m.set_shader_parameter("foam", foam_texture())
	# Taken from the sea rather than repeated here. The whole point of the
	# shared include is that these two cannot be set to different values.
	m.set_shader_parameter("wave_scale", Seascape.WAVE_SCALE)
	m.set_shader_parameter("wave_speed", Seascape.WAVE_SPEED)
	return m

## Foam, as an alpha pattern to lay over the strip.
##
## It has to tile down the length of the track, because that is the direction it
## is scrolled in and a seam would march up the wake once every forty metres.
## Ordinary 2D noise does not tile, so the long axis is sampled round a circle
## in 3D instead: the last row of the image is the same noise as the first
## because it is the same place on that circle.
static func foam_texture(size: int = 192) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0
	noise.fractal_octaves = 4
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		var angle := float(y) / float(size) * TAU
		var cx := cos(angle) * 2.6
		var cy := sin(angle) * 2.6
		for x in size:
			var n: float = (noise.get_noise_3d(cx, cy, float(x) / float(size) * 5.0) + 1.0) * 0.5
			# Mostly foam with holes torn in it, rather than an even mottle.
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, smoothstep(0.30, 0.62, n)))
	return ImageTexture.create_from_image(image)

func _process(delta: float) -> void:
	if _material == null or speed <= 0.0:
		return
	# Astern at the ship's own speed, so the foam stands still in the water.
	# Sampling is v + offset, so a feature sits at v = k - offset: the offset
	# has to fall for the pattern to travel aft.
	_scroll = fmod(_scroll - speed / TILE * delta, 1.0)
	_material.set_shader_parameter("scroll", Vector2(0.0, _scroll))
