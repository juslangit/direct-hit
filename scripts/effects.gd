class_name Effects
extends RefCounted

## Fire, smoke, spray, debris and steam.
##
## A shell landing looks the same whether it lands on the enemy or on the ship
## the player is standing on, so both scenes build their explosions from here.
## Sizes are in metres. A particle's scale multiplies its quad, so the quad is
## the size to read: a nine-metre ball of fire, a sixteen-metre puff of smoke,
## a shell splinter the size of a suitcase.

## How much room an emitter is allowed to fill.
##
## A GPUParticles3D is culled against a visibility box that defaults to a few
## metres across, whatever its particles actually do. A smoke column rising
## eight hundred metres therefore vanishes the moment that little box leaves
## the screen - which, for something on the horizon, is most of the time. Every
## emitter here is given room to work in.
static func room_to_work(p: GPUParticles3D, reach: float) -> GPUParticles3D:
	p.visibility_aabb = AABB(Vector3(-reach, -reach * 0.25, -reach), Vector3(reach * 2.0, reach * 2.5, reach * 2.0))
	return p

static func particle_material(
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

static func billboard(color: Color, emissive: bool, size: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if emissive else BaseMaterial3D.BLEND_MODE_MIX
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if emissive else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_color = color
	m.albedo_texture = puff(0.35 if emissive else 0.2)
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = emissive
	return m

static func quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	return q

static func make_fire() -> GPUParticles3D:
	# The fireball: brief, bright, thrown up and outward from the hole.
	var p := GPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 120
	p.lifetime = 0.9
	p.explosiveness = 0.85
	p.process_material = particle_material(Vector3(0, 1, 0), 72.0, Vector2(23.0, 68.0), -16.0, Vector2(0.8, 2.4))
	var m: ParticleProcessMaterial = p.process_material
	m.scale_curve = rising_curve()
	m.color_ramp = gradient([
		[0.0, Color(1.0, 0.95, 0.72, 1.0)],
		[0.18, Color(1.0, 0.65, 0.18, 1.0)],
		[0.55, Color(0.75, 0.22, 0.05, 0.75)],
		[1.0, Color(0.12, 0.08, 0.07, 0.0)],
	])
	p.draw_pass_1 = quad(8.8)
	p.material_override = billboard(Color(1, 1, 1), true, 8.8)
	room_to_work(p, 60.0)
	return p

static func make_smoke() -> GPUParticles3D:
	# The column that stays behind: slow, dark, and still climbing when the
	# camera leaves. This is what makes a hit feel like it did damage.
	var p := GPUParticles3D.new()
	p.emitting = false
	p.amount = 220
	p.lifetime = 6.5
	p.explosiveness = 0.1
	p.process_material = particle_material(Vector3(0.25, 1, 0), 34.0, Vector2(13.0, 39.0), 4.2, Vector2(1.1, 3.0))
	var m: ParticleProcessMaterial = p.process_material
	m.scale_curve = rising_curve()
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.35
	m.turbulence_noise_scale = 1.4
	m.color_ramp = gradient([
		[0.0, Color(0.20, 0.17, 0.16, 0.0)],
		[0.12, Color(0.16, 0.14, 0.13, 0.92)],
		[0.6, Color(0.31, 0.29, 0.28, 0.6)],
		[1.0, Color(0.46, 0.45, 0.44, 0.0)],
	])
	p.draw_pass_1 = quad(15.6)
	p.material_override = billboard(Color(1, 1, 1), false, 15.6)
	room_to_work(p, 220.0)
	return p

static func make_spray() -> GPUParticles3D:
	# Sea thrown up the ship's side. Sharper and whiter than smoke, and it
	# falls back down instead of climbing.
	var p := GPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 110
	p.lifetime = 2.4
	p.explosiveness = 0.9
	p.process_material = particle_material(Vector3(0, 1, 0), 55.0, Vector2(47.0, 120.0), -57.0, Vector2(1.0, 2.6))
	var m: ParticleProcessMaterial = p.process_material
	m.scale_curve = rising_curve()
	m.color_ramp = gradient([
		[0.0, Color(0.95, 0.98, 1.0, 0.95)],
		[0.5, Color(0.85, 0.91, 0.95, 0.7)],
		[1.0, Color(0.8, 0.88, 0.92, 0.0)],
	])
	p.draw_pass_1 = quad(8.3)
	p.material_override = billboard(Color(1, 1, 1), false, 8.3)
	room_to_work(p, 120.0)
	return p

static func make_debris() -> GPUParticles3D:
	# Small hard pieces of the ship. They are barely visible individually,
	# but without them an explosion looks like a gas leak rather than metal
	# being torn open.
	var p := GPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 34
	p.lifetime = 2.4
	p.explosiveness = 1.0
	p.process_material = particle_material(Vector3(0, 1, 0), 85.0, Vector2(68.0, 172.0), -78.0, Vector2(0.25, 0.8))
	var m: ParticleProcessMaterial = p.process_material
	m.angular_velocity_min = -520.0
	m.angular_velocity_max = 520.0
	m.color_ramp = gradient([
		[0.0, Color(0.35, 0.3, 0.28, 1.0)],
		[0.8, Color(0.25, 0.22, 0.2, 1.0)],
		[1.0, Color(0.2, 0.18, 0.17, 0.0)],
	])
	var box := BoxMesh.new()
	box.size = Vector3(1.3, 0.73, 0.88)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.30, 0.28, 0.26)
	steel.roughness = 0.45
	steel.metallic = 0.7
	box.material = steel
	p.draw_pass_1 = box
	room_to_work(p, 150.0)
	return p

static func make_steam() -> GPUParticles3D:
	# Only for a sinking: white steam where hot steel meets the sea as she
	# goes under.
	var p := GPUParticles3D.new()
	p.emitting = false
	p.amount = 70
	p.lifetime = 4.0
	p.process_material = particle_material(Vector3(0, 1, 0), 60.0, Vector2(10.0, 34.0), 3.1, Vector2(1.3, 3.2))
	var m: ParticleProcessMaterial = p.process_material
	m.scale_curve = rising_curve()
	m.color_ramp = gradient([
		[0.0, Color(0.95, 0.96, 0.97, 0.0)],
		[0.2, Color(0.9, 0.92, 0.94, 0.8)],
		[1.0, Color(0.85, 0.88, 0.9, 0.0)],
	])
	p.draw_pass_1 = quad(15.6)
	p.material_override = billboard(Color(1, 1, 1), false, 15.6)
	room_to_work(p, 200.0)
	return p

static func rising_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.25))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(1.0, 0.75))
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex

static func gradient(points: Array) -> GradientTexture1D:
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
static func puff(hardness: float = 0.0) -> GradientTexture2D:
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
