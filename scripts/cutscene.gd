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
	env.environment = Seascape.make_environment()
	add_child(env)

	_sun = Seascape.make_sun()
	add_child(_sun)

	Seascape.build_water(self)

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
	_flash.omni_range = 650.0
	_ship_pivot.add_child(_flash)

	_shell = _make_shell()
	add_child(_shell)

	_fire = Effects.make_fire()
	_ship_pivot.add_child(_fire)
	_smoke = Effects.make_smoke()
	_spray = Effects.make_spray()
	_debris = Effects.make_debris()
	_steam = Effects.make_steam()
	for p in [_smoke, _spray, _debris, _steam]:
		add_child(p)

func _make_shell() -> Node3D:
	var holder := Node3D.new()
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 1.4
	mesh.height = 18.0
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

# ----------------------------------------------------------- the performance

const SAIL_SPEED := 7.0   ## metres per second - about fourteen knots

var _sunk := false
var _hull_box := AABB()
var _length := 0.0
var _skipped := false
var _showcase := false
var _showcase_angle := 0.0

## Stage one hit. `report` is the dictionary Board.fire() returned.
func play(report: Dictionary) -> void:
	if _playing:
		return
	_playing = true
	_skipped = false
	_sunk = report.get("outcome", "hit") == "sunk"
	var kind: Ship.Kind = report.get("ship_kind", Ship.Kind.DESTROYER)
	var segment: int = report.get("segment", 0)

	Sound.sea(true)
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

	Sound.play("whistle", -4.0)
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

	Sound.play("hit", -2.0, randf_range(0.92, 1.05))
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
	# A second, deeper report under the first, so a sinking sounds like more
	# than the same hit again.
	get_tree().create_timer(0.55).timeout.connect(func(): Sound.play("sink", -1.0, 0.72))
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
	Sound.sea(false)
	_smoke.emitting = false
	_steam.emitting = false
	_playing = false
	finished.emit()

## Sail a ship past the camera with nothing happening to her, for the title
## screen. The menu used to be a dark rectangle with two buttons on it, which
## told a first-time player nothing about what the game actually is.
func showcase(kind: Ship.Kind) -> void:
	_playing = false
	_showcase = true
	_stage_ship(kind)
	_smoke.emitting = false
	_steam.emitting = false
	_fire.emitting = false
	_shell.visible = false
	_flash.light_energy = 0.0
	_showcase_angle = 0.0

func stop_showcase() -> void:
	_showcase = false

## Cut it short - the player has seen enough.
func skip() -> void:
	if not _playing:
		return
	_skipped = true
	_shell.visible = false
	_finish()

## A slow arc around the ship, plus the gentlest roll, so the title screen is
## alive without ever drawing attention to itself.
func _drift(delta: float) -> void:
	_showcase_angle += delta * 0.055
	var radius: float = _length * 1.05
	var middle := Vector3(_length * 0.5, _hull_box.size.y * 0.35, 0.0)
	_camera.position = middle + Vector3(
		cos(_showcase_angle) * radius * 0.45,
		_length * 0.16 + sin(_showcase_angle * 0.7) * _length * 0.03,
		-radius
	)
	# Aimed above her, so she rides the lower third of the title screen and
	# the words sit in clear sky rather than across her masts.
	_camera.look_at(_ship_pivot.to_global(middle + Vector3(0.0, _length * 0.20, 0.0)), Vector3.UP)
	_ship_pivot.rotation.z = sin(_sailing * 0.55) * deg_to_rad(1.4)
	_ship_pivot.rotation.x = sin(_sailing * 0.38 + 1.1) * deg_to_rad(0.8)

func _process(delta: float) -> void:
	if _ship_pivot == null:
		return
	_sailing += delta
	if _playing or _showcase:
		# Bow first. Ships are built with the bow at x = 0 and the hull running
		# aft up +X, so making way means going the other direction.
		_ship_pivot.position.x -= SAIL_SPEED * delta

	if _showcase:
		_drift(delta)
		return

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
