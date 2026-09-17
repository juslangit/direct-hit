extends Node3D

## The three seconds that this whole game exists for.
##
## The board hands over one dictionary - which ship, how far along her hull,
## and whether that shot finished her - and this scene stages it on open water
## with the real vessel. Nothing here decides anything; if it disagrees with
## the board, the board is right.
##
## It is built in code rather than clicked together in the editor so that the
## whole performance - where the camera starts, when the shell lands, how long
## the smoke lasts - reads top to bottom in one file and can be retimed by
## changing a number.

signal finished

const OCEAN_SHADER := "res://assets/shaders/ocean.gdshader"

# The beats, in seconds from the top.
const T_SHELL := 0.75    ## the incoming round becomes visible
const T_IMPACT := 1.05   ## it lands
const T_HIT_END := 4.20  ## a ship that survived
const T_SUNK_END := 7.60 ## a ship that did not

var _ship: Node3D
var _ship_pivot: Node3D
var _camera_rig: Node3D
var _camera: Camera3D
var _sun: DirectionalLight3D
var _flash: OmniLight3D
var _shell: Node3D
var _fire: GPUParticles3D
var _smoke: GPUParticles3D
var _spray: GPUParticles3D
var _debris: GPUParticles3D
var _steam: GPUParticles3D
var _impact_point := Vector3.ZERO
var _shake := 0.0
var _sailing := 0.0
var _playing := false

func _ready() -> void:
	_build_world()

# ---------------------------------------------------------------- the world

func _build_world() -> void:
	var env := WorldEnvironment.new()
	env.environment = _make_environment()
	add_child(env)

	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(deg_to_rad(-22.0), deg_to_rad(125.0), 0.0)
	_sun.light_energy = 1.5
	_sun.light_color = Color(1.0, 0.94, 0.84)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 600.0
	add_child(_sun)

	# Two sheets of water: a fine one around the action where the camera can
	# see individual waves, and a coarse one out to the horizon. One shader
	# drives both, and its own distance fade flattens the far one so the
	# coarse mesh never has to hold a wave it cannot draw.
	add_child(_make_ocean(2000.0, 600))
	# Beyond the fade the waves are flat anyway, so the horizon is one big
	# still sheet. It costs nothing and there is no seam to see, because the
	# sheet it meets has already gone flat by the time they touch.
	var horizon := _make_ocean(24000.0, 2)
	var flat: ShaderMaterial = horizon.material_override
	flat.set_shader_parameter("wave_scale", 0.0)
	add_child(horizon)

	_ship_pivot = Node3D.new()
	add_child(_ship_pivot)

	# The camera keeps pace with the ship so the framing holds while the sea
	# streams past - but it rides its own rig at sea level, not the hull. Hang
	# it on the hull instead and it rolls when she rolls and follows her under
	# when she sinks, which is how the first sinking was filmed from inside
	# the wreck. The rig copies only where she is, never how she is lying.
	_camera_rig = Node3D.new()
	add_child(_camera_rig)
	_camera = Camera3D.new()
	_camera.far = 24000.0
	_camera.fov = 44.0
	_camera_rig.add_child(_camera)

	_flash = OmniLight3D.new()
	_flash.light_energy = 0.0
	_flash.light_color = Color(1.0, 0.75, 0.42)
	_flash.omni_range = 260.0
	_ship_pivot.add_child(_flash)

	_shell = _make_shell()
	add_child(_shell)

	_fire = _make_fire()
	_ship_pivot.add_child(_fire)
	_smoke = _make_smoke()
	_spray = _make_spray()
	_debris = _make_debris()
	_steam = _make_steam()
	for p in [_smoke, _spray, _debris, _steam]:
		add_child(p)

func _make_environment() -> Environment:
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
	env.fog_density = 0.0011
	env.fog_sky_affect = 0.3
	return env

func _make_ocean(size: float, subdivisions: int) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions

	var material := ShaderMaterial.new()
	material.shader = load(OCEAN_SHADER)
	material.set_shader_parameter("wave_scale", 1.0)
	material.set_shader_parameter("wave_speed", 0.8)
	material.set_shader_parameter("detail_normal", _ripple_texture())

	var water := MeshInstance3D.new()
	water.mesh = plane
	water.material_override = material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.extra_cull_margin = size
	return water

## Fine noise, read as a normal map, for the ripple between the waves.
func _ripple_texture() -> NoiseTexture2D:
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
	tex.bump_strength = 3.0
	return tex

func _make_shell() -> Node3D:
	var holder := Node3D.new()
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.55
	mesh.height = 7.0
	body.mesh = mesh
	body.rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.72, 0.35)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.62, 0.22)
	material.emission_energy_multiplier = 8.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body.material_override = material

	holder.add_child(body)
	holder.visible = false
	return holder

# ------------------------------------------------------------- the explosion

func _particle_material(
		direction: Vector3, spread: float, speed: Vector2,
		gravity: float, scale_range: Vector2) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = direction
	m.spread = spread
	m.initial_velocity_min = speed.x
	m.initial_velocity_max = speed.y
	m.gravity = Vector3(0.0, gravity, 0.0)
	m.scale_min = scale_range.x
	m.scale_max = scale_range.y
	m.damping_min = 1.0
	m.damping_max = 4.0
	return m

func _billboard(color: Color, emissive: bool, size: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if emissive else BaseMaterial3D.BLEND_MODE_MIX
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if emissive else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_color = color
	m.albedo_texture = _puff(0.35 if emissive else 0.2)
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = emissive
	return m

func _quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	return q

func _make_fire() -> GPUParticles3D:
	# The fireball: brief, bright, thrown up and outward from the hole.
	var p := GPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 120
	p.lifetime = 0.9
	p.explosiveness = 0.85
	p.process_material = _particle_material(Vector3(0, 1, 0), 72.0, Vector2(9.0, 26.0), -6.0, Vector2(0.8, 2.4))
	var m: ParticleProcessMaterial = p.process_material
	m.scale_curve = _rising_curve()
	m.color_ramp = _gradient([
		[0.0, Color(1.0, 0.95, 0.72, 1.0)],
		[0.18, Color(1.0, 0.65, 0.18, 1.0)],
		[0.55, Color(0.75, 0.22, 0.05, 0.75)],
		[1.0, Color(0.12, 0.08, 0.07, 0.0)],
	])
	p.draw_pass_1 = _quad(3.4)
	p.material_override = _billboard(Color(1, 1, 1), true, 3.4)
	return p

func _make_smoke() -> GPUParticles3D:
	# The column that stays behind: slow, dark, and still climbing when the
	# camera leaves. This is what makes a hit feel like it did damage.
	var p := GPUParticles3D.new()
	p.emitting = false
	p.amount = 220
	p.lifetime = 6.5
	p.explosiveness = 0.1
	p.process_material = _particle_material(Vector3(0.25, 1, 0), 34.0, Vector2(5.0, 15.0), 1.6, Vector2(1.1, 3.0))
	var m: ParticleProcessMaterial = p.process_material
	m.scale_curve = _rising_curve()
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.35
	m.turbulence_noise_scale = 1.4
	m.color_ramp = _gradient([
		[0.0, Color(0.20, 0.17, 0.16, 0.0)],
		[0.12, Color(0.16, 0.14, 0.13, 0.92)],
		[0.6, Color(0.31, 0.29, 0.28, 0.6)],
		[1.0, Color(0.46, 0.45, 0.44, 0.0)],
	])
	p.draw_pass_1 = _quad(6.0)
	p.material_override = _billboard(Color(1, 1, 1), false, 6.0)
	return p

func _make_spray() -> GPUParticles3D:
	# Sea thrown up the ship's side. Sharper and whiter than smoke, and it
	# falls back down instead of climbing.
	var p := GPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 110
	p.lifetime = 2.4
	p.explosiveness = 0.9
	p.process_material = _particle_material(Vector3(0, 1, 0), 55.0, Vector2(18.0, 46.0), -22.0, Vector2(1.0, 2.6))
	var m: ParticleProcessMaterial = p.process_material
	m.scale_curve = _rising_curve()
	m.color_ramp = _gradient([
		[0.0, Color(0.95, 0.98, 1.0, 0.95)],
		[0.5, Color(0.85, 0.91, 0.95, 0.7)],
		[1.0, Color(0.8, 0.88, 0.92, 0.0)],
	])
	p.draw_pass_1 = _quad(3.2)
	p.material_override = _billboard(Color(1, 1, 1), false, 3.2)
	return p

func _make_debris() -> GPUParticles3D:
	# Small hard pieces of the ship. They are barely visible individually,
	# but without them an explosion looks like a gas leak rather than metal
	# being torn open.
	var p := GPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 34
	p.lifetime = 2.4
	p.explosiveness = 1.0
	p.process_material = _particle_material(Vector3(0, 1, 0), 85.0, Vector2(26.0, 66.0), -30.0, Vector2(0.25, 0.8))
	var m: ParticleProcessMaterial = p.process_material
	m.angular_velocity_min = -520.0
	m.angular_velocity_max = 520.0
	m.color_ramp = _gradient([
		[0.0, Color(0.35, 0.3, 0.28, 1.0)],
		[0.8, Color(0.25, 0.22, 0.2, 1.0)],
		[1.0, Color(0.2, 0.18, 0.17, 0.0)],
	])
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.28, 0.34)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.30, 0.28, 0.26)
	steel.roughness = 0.45
	steel.metallic = 0.7
	box.material = steel
	p.draw_pass_1 = box
	return p

func _make_steam() -> GPUParticles3D:
	# Only for a sinking: white steam where hot steel meets the sea as she
	# goes under.
	var p := GPUParticles3D.new()
	p.emitting = false
	p.amount = 70
	p.lifetime = 4.0
	p.process_material = _particle_material(Vector3(0, 1, 0), 60.0, Vector2(4.0, 13.0), 1.2, Vector2(1.3, 3.2))
	var m: ParticleProcessMaterial = p.process_material
	m.scale_curve = _rising_curve()
	m.color_ramp = _gradient([
		[0.0, Color(0.95, 0.96, 0.97, 0.0)],
		[0.2, Color(0.9, 0.92, 0.94, 0.8)],
		[1.0, Color(0.85, 0.88, 0.9, 0.0)],
	])
	p.draw_pass_1 = _quad(6.0)
	p.material_override = _billboard(Color(1, 1, 1), false, 6.0)
	return p

func _rising_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.25))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(1.0, 0.75))
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex

func _gradient(points: Array) -> GradientTexture1D:
	# A Gradient refuses to hold fewer than two points, so emptying it before
	# filling it silently leaves the default black-to-white ramp in place and
	# every particle comes out the wrong colour. Hand it both arrays instead.
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for point in points:
		offsets.append(float(point[0]))
		colors.append(point[1])
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex

## A soft round puff to draw each particle with.
##
## A billboarded quad with no texture is a hard-edged square, and a hundred
## hard-edged squares look like paper, not smoke. This is the alpha falloff
## that turns each one back into a cloud.
func _puff(hardness: float = 0.0) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, hardness, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.75),
		Color(1, 1, 1, 0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex

# ----------------------------------------------------------- the performance

const SAIL_SPEED := 7.0   ## metres per second, so the sea moves past her

var _sunk := false
var _hull_box := AABB()
var _length := 0.0
var _skipped := false

## Stage one hit. `report` is the dictionary Board.fire() returned.
func play(report: Dictionary) -> void:
	if _playing:
		return
	_playing = true
	_skipped = false
	_sunk = report.get("outcome", "hit") == "sunk"
	var kind: Ship.Kind = report.get("ship_kind", Ship.Kind.DESTROYER)
	var segment: int = report.get("segment", 0)

	_stage_ship(kind)
	var hit_local := _hit_position(kind, segment)
	_impact_point = hit_local

	_fire.position = hit_local
	_flash.position = hit_local
	_sailing = 0.0
	_shake = 0.0

	await _approach(hit_local)
	if _skipped: return
	await _incoming(hit_local)
	if _skipped: return
	_detonate(hit_local)
	await _aftermath()
	_finish()

func _stage_ship(kind: Ship.Kind) -> void:
	if _ship != null:
		_ship.queue_free()
	_ship = ShipModels.build(kind)
	_ship_pivot.add_child(_ship)
	_ship_pivot.transform = Transform3D.IDENTITY
	_hull_box = ShipModels.measure(_ship)
	_length = ShipModels.hull_length(kind)
	# Put her in the middle of the fine sheet of water, sailing up +X.
	_ship_pivot.position = Vector3(-_length * 0.5, 0.0, 0.0)
	_camera_rig.position = _ship_pivot.position
	_camera_rig.rotation = Vector3.ZERO

## Where on the hull the shell lands: so many squares back from the bow, at
## the near side of the beam, a little above the waterline.
func _hit_position(kind: Ship.Kind, segment: int) -> Vector3:
	var beam: float = max(_hull_box.size.z, 4.0)
	return Vector3(
		ShipModels.segment_offset(kind, segment),
		beam * 0.28,
		-beam * 0.45
	)

func _approach(target: Vector3) -> void:
	# Open wide and low, quartering from ahead, and close in. The ship is
	# already under way before the player sees her.
	_camera.position = target + Vector3(-_length * 0.48, _length * 0.16, -_length * 0.95)
	_camera.look_at(_ship_pivot.to_global(target))
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_camera, "position",
		target + Vector3(-_length * 0.18, _length * 0.09, -_length * 0.55), T_SHELL)
	await get_tree().create_timer(T_SHELL).timeout

func _incoming(target: Vector3) -> void:
	# The round itself, arcing down from off the bow. Short - a shell that is
	# on screen long enough to study is a shell travelling too slowly.
	var flight := T_IMPACT - T_SHELL
	var from: Vector3 = target + Vector3(-_length * 1.1, _length * 0.95, -_length * 0.55)
	_shell.position = from
	_shell.visible = true
	_shell.look_at_from_position(from, _ship_pivot.to_global(target), Vector3.UP)

	var tween := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_shell, "position", _ship_pivot.to_global(target), flight)
	await get_tree().create_timer(flight).timeout
	_shell.visible = false

func _detonate(local_point: Vector3) -> void:
	var world_point: Vector3 = _ship_pivot.to_global(local_point)
	for p in [_smoke, _spray, _debris]:
		p.position = world_point
	_smoke.position.y = max(world_point.y, 2.0)
	_steam.position = Vector3(world_point.x, 0.5, world_point.z)

	_fire.restart()
	_spray.restart()
	_debris.restart()
	_smoke.emitting = true
	_shake = 1.0

	# A flash lights the hull and the water around it for a quarter second.
	var tween := create_tween()
	tween.tween_property(_flash, "light_energy", 22.0, 0.04)
	tween.tween_property(_flash, "light_energy", 0.0, 0.45).set_ease(Tween.EASE_OUT)

	if _sunk:
		_sink()
	else:
		# She takes it and keeps going, leaning away from the blow.
		var lean := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
		lean.tween_property(_ship_pivot, "rotation:x", deg_to_rad(-3.5), 1.8)

func _sink() -> void:
	# The stern goes first: she rolls toward the hole, settles, and the sea
	# closes over her. Slow on purpose - this is the shot the player earned.
	_steam.emitting = true
	var draft: float = _hull_box.size.y
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_ship_pivot, "rotation:x", deg_to_rad(-26.0), 4.2) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE).set_delay(0.5)
	tween.tween_property(_ship_pivot, "rotation:z", deg_to_rad(7.0), 4.6) \
		.set_ease(Tween.EASE_IN).set_delay(0.8)
	tween.tween_property(_ship_pivot, "position:y", -draft * 1.35, 5.0) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD).set_delay(1.4)

func _aftermath() -> void:
	# Ride it out: pull back and let the smoke climb. A sinking gets more room
	# than a hit, both because it lasts longer and because the smoke column it
	# throws up will otherwise swallow the camera.
	var hold := (T_SUNK_END if _sunk else T_HIT_END) - T_IMPACT
	var mark := _impact_point + (
		Vector3(_length * 0.30, _length * 0.34, -_length * 1.45) if _sunk
		else Vector3(_length * 0.12, _length * 0.26, -_length * 0.92)
	)
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_camera, "position", mark, hold)
	await get_tree().create_timer(hold).timeout

func _finish() -> void:
	_smoke.emitting = false
	_steam.emitting = false
	_playing = false
	finished.emit()

## Cut it short - the player has seen enough.
func skip() -> void:
	if not _playing:
		return
	_skipped = true
	_shell.visible = false
	_finish()

func _process(delta: float) -> void:
	if _ship_pivot == null:
		return
	_sailing += delta
	if _playing:
		_ship_pivot.position.x += SAIL_SPEED * delta

	# Always keep the camera pointed at the wound, and shake it when the
	# shell lands. The shake decays rather than stopping, because a cut from
	# shaking to steady reads as a bug.
	if _camera_rig != null:
		# Follow her along the sea, but never down into it.
		_camera_rig.position = Vector3(_ship_pivot.position.x, 0.0, _ship_pivot.position.z)

	if _camera != null and _playing:
		var aim: Vector3 = _ship_pivot.to_global(_impact_point)
		_camera.look_at(aim, Vector3.UP)
		if _shake > 0.001:
			_shake = max(0.0, _shake - delta * 1.6)
			var amount: float = _shake * _shake * deg_to_rad(2.4)
			_camera.rotation += Vector3(
				randf_range(-amount, amount),
				randf_range(-amount, amount),
				randf_range(-amount, amount) * 0.6
			)
