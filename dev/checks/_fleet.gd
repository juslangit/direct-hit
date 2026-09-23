extends Node

## The fleet: her guns, her wake, and the smoke around her.
##
## Every assertion here exists because the thing it asserts was wrong at some
## point on the way, and most of them were wrong invisibly - the kind of wrong
## that a screenshot shows and a stack trace never will. So this suite is
## deliberately about the numbers behind the picture, and `dev/looks/_fleet.gd`
## is about the picture. Neither replaces the other: a check can prove that the
## turret's bearing is 34.0 degrees, and only a person looking at it can say
## whether the gunhouse stayed on its barbette getting there.

var failures := 0

func _ready() -> void:
	_the_turrets()
	_the_wake()
	_the_smoke()

	print("")
	if failures == 0:
		print("FLEET: all checks passed")
	else:
		print("FLEET: %d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)

# ------------------------------------------------------------- the turrets

func _the_turrets() -> void:
	print("her forward turrets")

	# A pristine hull to measure the cut against, built before anything is cut
	# out of anything.
	var pristine := ShipModels.build(Ship.Kind.BATTLESHIP)
	add_child(pristine)
	var before := _triangles(pristine)

	var hull := ShipModels.build(Ship.Kind.BATTLESHIP)
	add_child(hull)
	var turrets := Turret.cut_from(hull)

	_check("both forward turrets come out of the hull", turrets.size() == 2,
		"got %d" % turrets.size())
	if turrets.size() != 2:
		return

	# The one that matters most. Every triangle is moved, never copied and never
	# dropped: the hull plus its turrets has to have exactly as many triangles
	# as the hull did before it was cut. A cut that took nothing would pass the
	# count and fail the checks below; a cut that duplicated a surface - which
	# is what handing the same arrays to two meshes would do if the index array
	# were not replaced - fails here and nowhere else, because on screen it
	# looks perfect until the turret trains and the copy stays behind.
	var after := _triangles(hull)
	_check("nothing is lost or duplicated in the cut", after == before,
		"%d triangles before, %d after" % [before, after])

	for gun in turrets:
		var turret := gun as Turret
		var took := _triangles(turret)
		_check("%s is made of something" % turret.name, took > 200,
			"%d triangles" % took)

	# Both turrets take part of Object_10 and the second pass reads what the
	# first pass left. If the passes trod on each other, one of them would come
	# out empty or the mesh they share would come out bare.
	var left := _triangles_of(hull, "Object_10")
	_check("the hull keeps what was not cut from Object_10", left > 3000,
		"%d triangles left in Object_10" % left)

	# Bearings. The enemy sits 34 degrees off the starboard bow, and a turret
	# told to lay on the middle of his water has to arrive at that number. The
	# sign is the part worth pinning: the bow is -X and starboard is -Z, so a
	# starboard bearing is a negative rotation, and getting it backwards puts
	# the guns over the port rail while the plot says starboard.
	var bearing := deg_to_rad(34.0)
	var to_enemy := Vector3(-cos(bearing), 0.0, -sin(bearing)) * 6400.0
	for gun in turrets:
		var turret := gun as Turret
		turret.train_along(to_enemy - turret.position)
		_check("%s lays on a target 34 degrees to starboard" % turret.name,
			absf(turret.wanted - 34.0) < 0.5, "wanted %.2f degrees" % turret.wanted)

	var forward := turrets[0] as Turret
	forward.snap_to(34.0)
	# A rotation about +Y of -34 degrees is what puts the barrels to starboard.
	_check("training to starboard turns her the right way",
		absf(rad_to_deg(forward.rotation.y) + 34.0) < 0.01,
		"rotation.y is %.2f degrees" % rad_to_deg(forward.rotation.y))

	forward.centre()
	forward.snap_to(0.0)
	_check("centred, she points down the ship's head",
		absf(forward.rotation.y) < 0.001, "rotation.y is %.4f" % forward.rotation.y)

	# She may not train through her own bridge.
	forward.train_to(179.0)
	_check("she is stopped short of dead astern", absf(forward.wanted) <= Turret.LIMIT,
		"asked for 179, wanted %.1f" % forward.wanted)

	# The traverse is meant to be slow enough to watch. Six degrees a second
	# means the swing out to the enemy's bearing takes the better part of ten
	# seconds, and that wait is most of what the traverse is for.
	forward.snap_to(0.0)
	forward.train_to(34.0)
	forward._process(1.0)
	_check("she trains at six degrees a second", absf(forward.bearing - 6.0) < 0.01,
		"one second took her to %.2f degrees" % forward.bearing)
	_check("she is not there yet after a second", not forward.trained())
	for _step in 10:
		forward._process(1.0)
	_check("she is on her bearing after ten more", forward.trained(),
		"bearing %.2f, wanted %.2f" % [forward.bearing, forward.wanted])

	# The muzzle has to swing with the guns. A flash on the centre line while
	# the barrels point 34 degrees off it would be worse than a welded turret:
	# it would say out loud that the guns are decoration.
	var mount := Node3D.new()
	forward.add_child(mount)
	mount.position = forward.muzzle
	forward.snap_to(0.0)
	var fore_and_aft := mount.global_position
	forward.snap_to(90.0)
	var hard_over := mount.global_position
	_check("the muzzle swings round with the guns",
		fore_and_aft.distance_to(hard_over) > 15.0,
		"it moved %.1f m between fore-and-aft and hard over"
			% fore_and_aft.distance_to(hard_over))
	_check("the muzzle stays out of the ship",
		hard_over.y > 8.0 and absf(hard_over.x - Turret.FORWARD[0]["gunhouse"].get_center().x) < 2.0,
		"hard over the muzzle is at %s" % hard_over)

	pristine.queue_free()
	hull.queue_free()

# ---------------------------------------------------------------- the wake

func _the_wake() -> void:
	print("the water she leaves behind her")
	var bridge := (load("res://scenes/bridge.tscn") as PackedScene).instantiate()
	add_child(bridge)

	var wakes: Array = []
	_gather_wakes(bridge, wakes)
	_check("every ship in the fleet leaves a wake", wakes.size() == 5,
		"found %d wakes for 5 ships" % wakes.size())

	for wake in wakes:
		var strip: ArrayMesh = (wake as Wake).mesh
		_check("%s is a strip and not an empty node" % (wake as Node).name,
			strip != null and strip.get_surface_count() == 1
				and strip.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() > 100,
			"")
		# It has to run astern of the stern it is attached to, not forward of
		# it: hulls are built bow-first at the origin, so aft is +X, and a sign
		# error here would have the foam streaming off her bow.
		var box: AABB = strip.get_aabb()
		_check("it runs astern", box.position.x >= -0.01 and box.end.x > 100.0,
			"x from %.1f to %.1f" % [box.position.x, box.end.x])
		_check("it lies flat", absf(box.size.y) < 0.01, "%.2f m thick" % box.size.y)

		# The one that stops the wake and the sea drifting apart. The foam is
		# displaced by the same four Gerstner waves the water is, out of the
		# same shader include - but only if it is handed the same numbers. Given
		# a different swell it slides over the sea it is meant to be lying on.
		var foam: ShaderMaterial = (wake as Wake).material_override
		_check("its foam rides the same sea as the water",
			foam != null
				and is_equal_approx(foam.get_shader_parameter("wave_scale"), Seascape.WAVE_SCALE)
				and is_equal_approx(foam.get_shader_parameter("wave_speed"), Seascape.WAVE_SPEED),
			"wake has scale %s speed %s, sea has %s and %s" % [
				foam.get_shader_parameter("wave_scale"),
				foam.get_shader_parameter("wave_speed"),
				Seascape.WAVE_SCALE, Seascape.WAVE_SPEED])

	# The foam has to travel astern at the ship's own speed, which is what
	# leaves it standing still in the water rather than sliding along with her.
	var first := wakes[0] as Wake
	first._process(1.0)
	var moved: Vector2 = first.material_override.get_shader_parameter("scroll")
	var wanted: float = -bridge.SAIL_SPEED / Wake.TILE
	_check("the foam scrolls astern at the ship's speed",
		absf(moved.y - wanted) < 0.001,
		"one second moved it %.4f, wanted %.4f" % [moved.y, wanted])
	# And it must wrap rather than run away, or it loses precision in a long game.
	for _step in 400:
		first._process(1.0)
	_check("the scroll wraps instead of running away",
		absf((first.material_override.get_shader_parameter("scroll") as Vector2).y) <= 1.0,
		"after 400 more seconds it is at %s"
			% first.material_override.get_shader_parameter("scroll"))

	bridge.queue_free()

# --------------------------------------------------------------- the smoke

func _the_smoke() -> void:
	print("the smoke around the fleet")
	var bridge := (load("res://scenes/bridge.tscn") as PackedScene).instantiate()
	add_child(bridge)
	var war: Node3D = bridge.war

	var columns: Array = []
	for child in war.get_children():
		var p := child as GPUParticles3D
		if p != null:
			columns.append(p)
	_check("every wreck has a column of smoke over it",
		columns.size() == bridge.WRECK_COUNT,
		"%d columns for %d wrecks" % [columns.size(), bridge.WRECK_COUNT])

	for column in columns:
		var p := column as GPUParticles3D
		var rise: ParticleProcessMaterial = p.process_material

		# The line the whole effect turned on, and the reason it took three
		# goes. Godot's turbulence is not a jitter added to a particle's own
		# motion, it is a noise velocity field that carries the particle along
		# with it - and at any noise scale broad enough to look like weather,
		# the field is broader than the column, so every puff however hard it
		# is thrown gets swept back into one slowly churning knot. Turn this
		# back on and the column becomes a ball again, reliably, and no other
		# number in this file will tell you why.
		_check("the column is not stirred by turbulence", not rise.turbulence_enabled)

		# A column is an aspect ratio before it is anything else. It must climb
		# far further than its puffs are wide, or twenty puffs overlapping make
		# a ball whatever their velocities say.
		var climb := rise.initial_velocity_min * p.lifetime
		var widest := _widest_puff(p)
		_check("it climbs far enough to be a column", climb > 600.0,
			"%.0f m in its lifetime" % climb)
		_check("it climbs much further than it is wide", climb > widest * 4.0,
			"%.0f m tall against %.0f m wide" % [climb, widest])

		# Wind is a steady push and belongs in gravity, but it has to be a wind
		# and not a catapult: the version this replaced drifted four kilometres
		# sideways over its lifetime, so the column was a diagonal smear as long
		# as the horizon, seen end on.
		var lean := Vector2(rise.gravity.x, rise.gravity.z).length() * 0.5 * p.lifetime * p.lifetime
		_check("it leans downwind rather than being thrown downwind", lean < climb * 0.5,
			"%.0f m of lean against %.0f m of climb" % [lean, climb])

		_check("it is already burning when the player arrives",
			p.preprocess >= p.lifetime * 0.9,
			"preprocess %.1f for a lifetime of %.1f" % [p.preprocess, p.lifetime])

		# A column eight hundred metres tall is culled against its emitter's own
		# visibility box, which defaults to a few metres. Too small a box and the
		# whole column blinks out whenever its base leaves the screen - which,
		# for something on the horizon, is most of the time.
		_check("it has room to work in", p.visibility_aabb.size.y > climb * 0.5,
			"a box %.0f m tall for a column %.0f m tall" % [p.visibility_aabb.size.y, climb])

	# The escorts' funnel smoke had both the same faults, and from the bridge it
	# is the smoke the player actually sees: the escorts are a kilometre off and
	# the wrecks are three to nine, so a dark ball beside a destroyer is far
	# more obvious than one on the horizon.
	var trails := 0
	for station in bridge.escorts.get_children():
		for child in station.get_children():
			var p := child as GPUParticles3D
			if p == null:
				continue
			trails += 1
			var drift: ParticleProcessMaterial = p.process_material
			var whose: String = Ship.SPECS[station.get_meta("kind")]["name"]
			_check("%s's funnel smoke is not stirred into a ball" % whose,
				not drift.turbulence_enabled)
			var climb := drift.initial_velocity_min * p.lifetime
			var widest := _widest_puff(p)
			_check("her plume is taller than it is wide", climb > widest,
				"%.0f m against %.0f m" % [climb, widest])
			# Funnel smoke falls astern at the speed of the apparent wind and no
			# faster. The version this replaced pushed it nine hundred metres
			# over fourteen seconds, which is sixty metres a second off a ship
			# making seven.
			var astern := drift.gravity.x * 0.5 * p.lifetime * p.lifetime
			_check("her smoke falls astern no faster than the wind",
				astern < bridge.SAIL_SPEED * p.lifetime * 2.0,
				"%.0f m astern in %.1f s at %.1f m/s"
					% [astern, p.lifetime, bridge.SAIL_SPEED])
	_check("every escort that has a funnel is making smoke", trails == 3,
		"%d trails (the submarine has no funnel)" % trails)

	bridge.queue_free()

# ---------------------------------------------------------------- plumbing

## How wide a puff gets at its widest, in metres.
##
## Read off the curve rather than assumed. The first version of this check
## multiplied by a hard-coded 4.0 - the top of the wreck column's scale curve -
## and so went on reporting the column's width for a plume that had been given a
## gentler curve of its own. A check that carries its own copy of a number it is
## checking is not checking anything.
func _widest_puff(p: GPUParticles3D) -> float:
	var m: ParticleProcessMaterial = p.process_material
	var quad := p.draw_pass_1 as QuadMesh
	if quad == null:
		return 0.0
	var most := 1.0
	var curve := m.scale_curve as CurveTexture
	if curve != null and curve.curve != null:
		most = 0.0
		for step in 21:
			most = maxf(most, curve.curve.sample(float(step) / 20.0))
	return quad.size.x * m.scale_max * most

func _gather_wakes(node: Node, into: Array) -> void:
	if node is Wake:
		into.append(node)
	for child in node.get_children():
		_gather_wakes(child, into)

func _triangles(node: Node) -> int:
	var total := 0
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			total += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	for child in node.get_children():
		total += _triangles(child)
	return total

func _triangles_of(node: Node, mesh_name: String) -> int:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null and String(mi.name) == mesh_name:
		return mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3
	for child in node.get_children():
		var found := _triangles_of(child, mesh_name)
		if found > 0:
			return found
	return 0

func _check(what: String, passed: bool, detail: String = "") -> void:
	if passed:
		print("  ok    %s %s" % [what, detail])
		return
	failures += 1
	print("  FAIL  %s %s" % [what, detail])
