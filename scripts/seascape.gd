class_name Seascape
extends RefCounted

## The sea, the sky and the light over them.
##
## Two scenes need an ocean now - the cutscene beside a ship taking a shell, and
## the bridge the player stands on - and they must be the same ocean, lit the
## same way, or cutting between them would read as two different afternoons.
## So it is built here once and both ask for it.

const OCEAN_SHADER := "res://assets/shaders/ocean.gdshader"

## How big the swell runs. One value for the whole game, because the cutscene
## and the bridge have to be the same afternoon. At this setting the longest
## wave is about 180 m from crest to crest and roughly two metres high - a
## moderate sea that a battleship with five metres of freeboard rides through
## without shipping water over her own bow.
const WAVE_SCALE := 2.0
const SKY_SHADER := "res://assets/shaders/sky.gdshader"

## The sun, aimed so its glare lies across the water rather than behind the
## camera, which is what gives the sea its highlights.
static func make_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-22.0), deg_to_rad(125.0), 0.0)
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600.0
	return sun

static func make_environment() -> Environment:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://assets/shaders/sky.gdshader")

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 4.0
	env.ssao_enabled = false
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.1
	# Haze over the sea. It sells the distance and, usefully, hides the far
	# edge of the water long before the player can reach it.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.60, 0.67, 0.74)
	env.fog_light_energy = 1.0
	# Thin enough to see the enemy's water at six kilometres. At the density
	# this started with, anything past about three was gone completely, which
	# included the entire battle.
	env.fog_density = 0.00012
	env.fog_sky_affect = 0.3
	return env

static func make_ocean(size: float, subdivisions: int) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions

	var material := ShaderMaterial.new()
	material.shader = load(OCEAN_SHADER)
	material.set_shader_parameter("wave_scale", WAVE_SCALE)
	material.set_shader_parameter("wave_speed", 0.8)
	material.set_shader_parameter("detail_normal", ripple_texture())

	var water := MeshInstance3D.new()
	water.mesh = plane
	water.material_override = material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.extra_cull_margin = size
	return water

## Fine noise, read as a normal map, for the ripple between the waves.

static func ripple_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.014
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 1.4
	return tex

## A fine sheet of water around the action and a still one out to the horizon.
## Beyond the wave fade the near sheet is flat anyway, so there is no seam to
## see where they meet.
## Returns [near sheet, horizon sheet] so the caller can keep them under the
## camera. Both are plain meshes; the waves are worked out from world position,
## so sliding a sheet along does not slide the sea with it - the swell stays
## exactly where it was and only the patch of mesh drawing it moves.
static func build_water(into: Node3D, near_size: float = 5000.0, near_subdivisions: int = 700) -> Array:
	var near := make_ocean(near_size, near_subdivisions)
	into.add_child(near)
	# Big enough that its own edge is sixty kilometres away and sits within a
	# fiftieth of a degree of eye level. At a quarter of this the edge showed
	# as a bright line across the sky, because the sea is flat here and there
	# is no curvature to hide it behind.
	var horizon := make_ocean(120000.0, 2)
	var flat: ShaderMaterial = horizon.material_override
	flat.set_shader_parameter("wave_scale", 0.0)
	# Well below the near sheet - deeper than the deepest trough, so it never
	# shows through. The two overlap for kilometres; at the same height they
	# fight for the same pixels, and a metre apart the near sheet's troughs
	# still dip through it. Either way the sea breaks into drifting mottled
	# patches that read as an oil slick. Eight metres down, the step where they
	# meet is two kilometres away and subtends a fifth of a degree.
	horizon.position.y = -8.0
	into.add_child(horizon)
	return [near, horizon]

## Keep the water under the camera. The near sheet is snapped to whole quads so
## its vertices always land on the same world positions; slide it smoothly and
## the wave crests crawl across the mesh instead of standing still.
static func follow(sheets: Array, focus: Vector3, near_size: float = 5000.0, near_subdivisions: int = 700) -> void:
	if sheets.size() < 2:
		return
	var quad := near_size / float(near_subdivisions)
	var near: Node3D = sheets[0]
	near.position.x = round(focus.x / quad) * quad
	near.position.z = round(focus.z / quad) * quad
	var horizon: Node3D = sheets[1]
	horizon.position.x = focus.x
	horizon.position.z = focus.z
