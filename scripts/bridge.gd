extends Node3D

## The bridge of your flagship, and the war around her. This is the game.
##
## There is no chart on a screen any more. You stand on the bridge of a
## battleship with your own fleet in formation around you, and you fight from
## there: the plotting table beside you is where a target is chosen, and the
## gun sight is where the shot is taken.
##
## Three things the player can be doing, and the camera is the only difference
## between them:
##
##   WATCH  standing at the bulwark, free to look around the fleet
##   PLOT   bent over the plotting table, marking a square
##   SIGHT  eye to the director, laying the guns on the square that was marked
##
## What is built here and what is bought: the hull, its deck and its turrets
## are a bought model, which is what it is good at - seen from twenty metres
## and more. Everything within arm's reach of the player is built in code,
## because a model meant for half a mile away does not survive being stood on.
##
## The rules are not here. The bridge asks for a shot and is told what it did;
## it never decides anything itself.

signal shot_requested(cell: Vector2i)
signal mode_changed(mode: int)

enum Mode { WATCH, PLOT, SIGHT }

const SAIL_SPEED := 7.0        ## metres per second, about fourteen knots
const CELL := ShipModels.CELL_LENGTH
const ENEMY_RANGE := 6400.0    ## metres to the middle of the enemy's water
const ENEMY_BEARING := 34.0    ## degrees off the starboard bow
const WATCH_FOV := 62.0
const SIGHT_FOV := 8.5
const LAY_TOLERANCE := 1.6     ## degrees the sight may be off and still fire
const LOOK_SENSITIVITY := 0.0022

var fleet: Node3D              ## everything that steams together
var flagship: Node3D           ## rolls and pitches; the bridge is on her
var flagship_hull: Node3D
var head: Node3D               ## the player's neck: yaw
var camera: Camera3D           ## the player's eyes: pitch
var table: PlotTable
var escorts: Node3D
var revealed: Node3D           ## enemy ships we have found, burning at range

var mode: Mode = Mode.WATCH
var marked := Vector2i(-1, -1)
var can_fire := false
var enemy_board: Board = null

var _water: Array = []
var _sailing := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _length := 0.0
var _hull_box := AABB()
var _pose_tween: Tween
var hud: BridgeHud
## Only a real game grabs the mouse. A look scene that captured the pointer
## would take the cursor away from whoever is running it.
var capture_mouse := false:
	set(value):
		capture_mouse = value
		refresh_mouse_mode()

## Put the pointer in the state this mode needs.
##
## This has to be able to run at any time, not only when the mode changes. The
## battle used to be opened by changing mode first and turning capture on
## afterwards, so the one call that would have grabbed the pointer ran while
## capture was still off - and the player spent the whole game unable to turn
## the guns, because the cursor hit the edge of the screen and stopped.
func refresh_mouse_mode() -> void:
	if not capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if mode == Mode.PLOT else Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Seascape.make_environment()
	add_child(env)
	add_child(Seascape.make_sun())
	_water = Seascape.build_water(self)

	fleet = Node3D.new()
	fleet.name = "Fleet"
	add_child(fleet)

	_build_flagship()
	_build_bridge_set()
	_build_head()
	_build_table()
	_build_guns()
	_build_escorts()
	_build_war()

	revealed = Node3D.new()
	revealed.name = "Revealed"
	fleet.add_child(revealed)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = BridgeHud.new()
	layer.add_child(hud)

	_apply_mode(Mode.WATCH)

func _build_flagship() -> void:
	flagship = Node3D.new()
	flagship.name = "Flagship"
	fleet.add_child(flagship)
	flagship_hull = ShipModels.build(Ship.Kind.BATTLESHIP)
	flagship.add_child(flagship_hull)
	_hull_box = ShipModels.measure(flagship_hull)
	_length = ShipModels.hull_length(Ship.Kind.BATTLESHIP)

# --------------------------------------------------------------- the fleet

## Where each of your other four ships steams, in the flagship's own frame:
## -X is ahead, -Z is to starboard. Far enough off not to crowd the picture,
## close enough that a shell landing on one of them is plainly your fleet
## being hit rather than something happening on the horizon.
const STATION := {
	Ship.Kind.CARRIER: Vector3(1400.0, 0.0, 620.0),
	Ship.Kind.CRUISER: Vector3(-1250.0, 0.0, -540.0),
	Ship.Kind.DESTROYER: Vector3(-900.0, 0.0, 780.0),
	Ship.Kind.SUBMARINE: Vector3(820.0, 0.0, -980.0),
}

func _build_escorts() -> void:
	escorts = Node3D.new()
	escorts.name = "Escorts"
	fleet.add_child(escorts)
	for kind in STATION:
		var ship := ShipModels.build(kind)
		var station := Node3D.new()
		station.position = STATION[kind]
		# A hull is built with its bow on the origin, so it has to be pushed
		# back half its length to sit on its station rather than trail from it.
		ship.position.x = ShipModels.hull_length(kind) * 0.5
		station.add_child(ship)
		station.set_meta("kind", kind)
		escorts.add_child(station)

# ------------------------------------------------------- the enemy's water

## The middle of the enemy's box of sea, in the fleet's frame.
func enemy_centre() -> Vector3:
	var bearing := deg_to_rad(ENEMY_BEARING)
	# Ahead is -X and starboard is -Z, so a bearing off the starboard bow
	# swings from one towards the other.
	return Vector3(-cos(bearing), 0.0, -sin(bearing)) * ENEMY_RANGE

## The middle of one square of the enemy's water.
func cell_centre(cell: Vector2i) -> Vector3:
	var span := CELL * float(Board.SIZE)
	var corner := enemy_centre() - Vector3(span, 0.0, span) * 0.5
	return corner + Vector3((float(cell.x) + 0.5) * CELL, 0.0, (float(cell.y) + 0.5) * CELL)

## There is deliberately nothing drawn on the enemy's water.
##
## The first version laid a lit ten-by-ten grid over the sea where the enemy
## was, and it could not work: a flat plane six hundred metres across, seen
## from a bridge twenty-four metres up at a range of six kilometres, stands
## about a tenth of a degree tall. It collapsed into a single hairline above
## the horizon. No amount of colour fixes that - it is the geometry.
##
## Which is why real gunnery never worked that way. The plot is on the table,
## below decks and flat in front of the people reading it, and what reaches the
## guns is a bearing and a range. So the sight gives the player a bearing to
## lay on, and the sea carries only things that are really there: the fall of
## your own shot, and the ships you have set on fire.

func refresh_plot() -> void:
	if table != null:
		table.refresh()

func set_enemy_board(board: Board) -> void:
	enemy_board = board
	if table != null:
		table.set_board(board)
	refresh_plot()

# ---------------------------------------------------------------- the head

func _build_head() -> void:
	head = Node3D.new()
	head.name = "Head"
	flagship.add_child(head)

	camera = Camera3D.new()
	camera.far = 40000.0
	camera.fov = WATCH_FOV
	# Said explicitly: whichever camera enters the tree first otherwise wins,
	# and a stray one in a test scene will happily film empty water.
	camera.current = true
	head.add_child(camera)
	_place_head_for(Mode.WATCH)

func _build_table() -> void:
	table = PlotTable.new()
	table_anchor.add_child(table)
	table.cell_picked.connect(_on_cell_picked)

# ---------------------------------------------------------------- the modes

func set_mode(next: Mode) -> void:
	if mode == next:
		return
	_apply_mode(next)

func _apply_mode(next: Mode) -> void:
	mode = next
	_place_head_for(next)
	refresh_mouse_mode()
	if hud != null:
		hud.mode = int(next)
		hud.queue_redraw()
	mode_changed.emit(next)

## Each mode is a place to stand and a lens to look through, and nothing else.
func _place_head_for(which: Mode) -> void:
	match which:
		Mode.PLOT:
			# Leaning over the table, worked out in the table's own frame so
			# that turning the table turns the player with it. The offsets are
			# measured from the plot surface rather than from the table's feet,
			# which is a metre of difference and the reason the first attempt
			# put the player's nose on the glass.
			var stand := Transform3D(Basis(), Vector3(0.0, PlotTable.HEIGHT, 0.0))
			var eye_local: Vector3 = (table.global_transform * stand * Vector3(0.0, 1.45, 1.75))
			var at_local: Vector3 = (table.global_transform * stand * Vector3(0.0, 0.0, -0.1))
			_move_head(flagship.to_local(eye_local), flagship.to_local(at_local), 55.0)
		Mode.SIGHT:
			var sight_eye := bridge_position() + Vector3(0.0, 0.18, -1.3)
			_move_head(sight_eye, sight_eye + _to_enemy(), SIGHT_FOV)
		_:
			var eye := bridge_position()
			_move_head(eye, eye + Vector3(-1.0, -0.08, 0.0), WATCH_FOV)

func _to_enemy() -> Vector3:
	var target := marked if Board.in_bounds(marked) else Vector2i(Board.SIZE / 2, Board.SIZE / 2)
	return (flagship.to_local(fleet.to_global(cell_centre(target))) - bridge_position()).normalized()

func _move_head(eye: Vector3, looking_at: Vector3, fov: float) -> void:
	var direction := (looking_at - eye).normalized()
	_yaw = atan2(-direction.x, -direction.z)
	_pitch = asin(clampf(direction.y, -1.0, 1.0))
	if _pose_tween != null and _pose_tween.is_running():
		_pose_tween.kill()
	_pose_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_pose_tween.tween_property(head, "position", eye, 0.55)
	_pose_tween.tween_property(camera, "fov", fov, 0.55)
	head.rotation = Vector3(0.0, _yaw, 0.0)
	camera.rotation = Vector3(_pitch, 0.0, 0.0)

# ---------------------------------------------------------------- the input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mode != Mode.PLOT:
		_look(event.relative)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Right click turns the ship being laid. R does the same, but a player
		# with one hand on the mouse should not have to find the keyboard.
		if placing:
			turn_ship()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if mode == Mode.PLOT:
			var cell := _pick_table(event.position)
			if placing:
				_place_ship(cell)
			else:
				table.choose(cell)
		elif mode == Mode.SIGHT and can_fire:
			fire()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				if placing:
					turn_ship()
			KEY_TAB, KEY_T:
				if not placing:
					set_mode(Mode.WATCH if mode == Mode.PLOT else Mode.PLOT)
			KEY_SPACE:
				if placing:
					pass
				elif mode == Mode.SIGHT and can_fire:
					fire()
				elif mode != Mode.SIGHT and Board.in_bounds(marked):
					set_mode(Mode.SIGHT)
			KEY_ESCAPE:
				set_mode(Mode.WATCH)

func _look(relative: Vector2) -> void:
	# Slower in the sight: at eight degrees across the whole view, the same
	# wrist movement would throw the guns right off the plot.
	var scale := LOOK_SENSITIVITY * (camera.fov / WATCH_FOV)
	_yaw -= relative.x * scale
	_pitch = clampf(_pitch - relative.y * scale, deg_to_rad(-62.0), deg_to_rad(45.0))
	head.rotation.y = _yaw
	camera.rotation.x = _pitch

func _pick_table(screen_point: Vector2) -> Vector2i:
	return table.pick(camera.project_ray_origin(screen_point), camera.project_ray_normal(screen_point))

func _on_cell_picked(cell: Vector2i) -> void:
	if enemy_board != null and enemy_board.already_shot(cell):
		return
	marked = cell
	table.chart.last_shot = cell
	table.refresh()

## How far the guns are off the square that was marked, in degrees.
func lay_error() -> float:
	if not Board.in_bounds(marked):
		return 999.0
	var to_target := (fleet.to_global(cell_centre(marked)) - camera.global_position).normalized()
	var aim := -camera.global_transform.basis.z
	return rad_to_deg(aim.angle_to(to_target))

func fire() -> void:
	if not Board.in_bounds(marked):
		return
	can_fire = false
	shot_requested.emit(marked)

# --------------------------------------------------------------- each frame

func _process(delta: float) -> void:
	_sailing += delta
	# Bow first: the hulls are built with the bow at x = 0 running aft up +X.
	fleet.position.x -= SAIL_SPEED * delta
	Seascape.follow(_water, camera.global_position)
	_tick_war(delta)

	# She works in the swell. Small and slow - a ship this size barely notices
	# a moderate sea, but she must not look welded to the water either.
	flagship.rotation.z = sin(_sailing * 0.42) * deg_to_rad(0.9)
	flagship.rotation.x = sin(_sailing * 0.31 + 1.2) * deg_to_rad(0.5)
	flagship.position.y = sin(_sailing * 0.37) * 0.35

	if mode == Mode.PLOT:
		var under := _pick_table(get_viewport().get_mouse_position())
		table.hover(under)
		if placing:
			_preview(under)

	if mode == Mode.SIGHT:
		can_fire = lay_error() <= LAY_TOLERANCE

	if _shake > 0.001:
		_shake = maxf(0.0, _shake - delta * 0.9)
		var amount := _shake * _shake * deg_to_rad(2.2)
		camera.rotation.x = _pitch + randf_range(-amount, amount)
		head.rotation.y = _yaw + randf_range(-amount, amount)

	if hud != null:
		_update_hud()

func _update_hud() -> void:
	hud.on_target = can_fire
	hud.marked = marked
	# The ship's head is -X in her own frame, because hulls are built bow-first
	# at the origin.
	var forward := -flagship.global_transform.basis.x
	var ship_heading := atan2(forward.x, forward.z)
	var aim := -camera.global_transform.basis.z
	hud.aim_bearing = rad_to_deg(atan2(aim.x, aim.z) - ship_heading)

	if Board.in_bounds(marked):
		var target := fleet.to_global(cell_centre(marked))
		var to_target := target - camera.global_position
		hud.range_metres = to_target.length()
		hud.target_bearing = rad_to_deg(atan2(to_target.x, to_target.z) - ship_heading)
		hud.target_visible = not camera.is_position_behind(target)
		hud.target_screen = camera.unproject_position(target)
	else:
		hud.range_metres = 0.0
		hud.target_visible = false
	hud.queue_redraw()
# -------------------------------------------------------------- the wheelhouse

## The room the player stands in.
##
## A hull model bought for use at half a mile has no bridge worth standing in,
## so the wheelhouse is built in code and mounted on the ship where her real one
## was: forward on the superstructure, on the centre line, with its deck
## twenty-four metres above the sea. What the bought hull provides is everything
## beyond the windows - the foredeck and the turrets - which is the distance it
## is good at.

var wheelhouse: Wheelhouse
var table_anchor: Node3D

## Where the wheelhouse's own deck sits on the ship.
func deck_position() -> Vector3:
	return Vector3(_length * 0.40, 24.0 - Wheelhouse.EYE.y, 0.0)

## Where the player's eyes are: inside the wheelhouse, at the forward windows.
func bridge_position() -> Vector3:
	return deck_position() + Wheelhouse.EYE

func _build_bridge_set() -> void:
	wheelhouse = Wheelhouse.new()
	wheelhouse.name = "Wheelhouse"
	wheelhouse.position = deck_position()
	flagship.add_child(wheelhouse)
	table_anchor = wheelhouse.table_anchor

# --------------------------------------------------------------- the guns

## The forward turret, in the flagship's own frame. The bought hull's turrets
## do not traverse, so the muzzle flash is staged where her forward guns
## actually are and the shell departs from there.
const MUZZLE := Vector3(58.0, 14.0, 0.0)
const SHELL_FLIGHT := 2.6     ## seconds from muzzle to fall of shot
const SHELL_APEX := 220.0     ## metres above the straight line, at the top

signal shot_landed(result: Dictionary)

var _muzzle_flash: OmniLight3D
var _muzzle_smoke: GPUParticles3D
var _shell: MeshInstance3D
var _splash: GPUParticles3D
var _firing := false

func _build_guns() -> void:
	_muzzle_flash = OmniLight3D.new()
	_muzzle_flash.position = MUZZLE
	_muzzle_flash.light_color = Color(1.0, 0.78, 0.45)
	_muzzle_flash.light_energy = 0.0
	_muzzle_flash.omni_range = 220.0
	flagship.add_child(_muzzle_flash)

	_muzzle_smoke = Effects.make_smoke()
	_muzzle_smoke.position = MUZZLE
	_muzzle_smoke.emitting = false
	flagship.add_child(_muzzle_smoke)

	var round_mesh := SphereMesh.new()
	round_mesh.radius = 2.6
	round_mesh.height = 5.2
	var tracer := StandardMaterial3D.new()
	tracer.albedo_color = Color(1.0, 0.82, 0.45)
	tracer.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer.emission_enabled = true
	tracer.emission = Color(1.0, 0.7, 0.3)
	tracer.emission_energy_multiplier = 6.0
	_shell = MeshInstance3D.new()
	_shell.mesh = round_mesh
	_shell.material_override = tracer
	_shell.visible = false
	fleet.add_child(_shell)

	# The fall of shot: a column of sea thrown up where the round lands. At six
	# kilometres this is the only thing that tells you what your shot did, so
	# it is built much larger than a shell splash would be at arm's length.
	_splash = Effects.make_spray()
	var throw: ParticleProcessMaterial = _splash.process_material
	throw.initial_velocity_min = 85.0
	throw.initial_velocity_max = 190.0
	throw.spread = 16.0
	throw.gravity = Vector3(0.0, -68.0, 0.0)
	_splash.amount = 150
	_splash.lifetime = 5.0
	_splash.draw_pass_1 = Effects.quad(26.0)
	_splash.material_override = Effects.billboard(Color(1, 1, 1), false, 26.0)
	Effects.room_to_work(_splash, 400.0)
	_splash.emitting = false
	fleet.add_child(_splash)

## Fire at the marked square and show what happened. `result` is the dictionary
## the rules returned; the bridge only stages it.
func play_shot(result: Dictionary) -> void:
	if _firing:
		return
	_firing = true
	var target := cell_centre(result.get("cell", marked))

	_muzzle_flash.light_energy = 0.0
	var flash := create_tween()
	flash.tween_property(_muzzle_flash, "light_energy", 26.0, 0.03)
	flash.tween_property(_muzzle_flash, "light_energy", 0.0, 0.5).set_ease(Tween.EASE_OUT)
	_muzzle_smoke.restart()
	_muzzle_smoke.emitting = true
	Sound.play("hit", -3.0, 0.62)

	var from := flagship.to_global(MUZZLE)
	await _fly(fleet.to_local(from), target)

	_muzzle_smoke.emitting = false
	if result.get("outcome", "miss") == "miss":
		_splash.position = target
		_splash.restart()
		Sound.play("splash", -8.0, 0.5)
	_firing = false
	shot_landed.emit(result)

## The round, arcing. A shell fired at six kilometres spends most of its flight
## well above the line of sight, which is what makes watching one land feel
## like waiting rather than like pointing.
func _fly(from: Vector3, to: Vector3) -> void:
	_shell.visible = true
	var elapsed := 0.0
	while elapsed < SHELL_FLIGHT:
		elapsed += get_process_delta_time()
		var t: float = clampf(elapsed / SHELL_FLIGHT, 0.0, 1.0)
		var along: Vector3 = from.lerp(to, t)
		along.y += SHELL_APEX * 4.0 * t * (1.0 - t)
		_shell.position = along
		await get_tree().process_frame
	_shell.visible = false

## An enemy ship we have found. She stays on the horizon afterwards, burning,
## which is the only record of your hits that exists outside the plotting table.
func reveal(result: Dictionary) -> void:
	if not result.has("ship_kind"):
		return
	var kind: Ship.Kind = result["ship_kind"]
	var cell: Vector2i = result["cell"]
	var segment: int = result.get("segment", 0)
	var horizontal: bool = result.get("horizontal", true)
	var bow_cell := cell - (Vector2i(segment, 0) if horizontal else Vector2i(0, segment))

	var name := "ship_%d_%d" % [bow_cell.x, bow_cell.y]
	var existing := revealed.get_node_or_null(name)
	if existing == null:
		existing = Node3D.new()
		existing.name = name
		existing.position = cell_centre(bow_cell) - Vector3(CELL, 0.0, CELL) * 0.5
		# The grid runs +X across and +Z down, and a hull is built bow-first
		# along +X, so a ship lying down the grid is turned a quarter turn.
		if not horizontal:
			existing.rotation.y = -PI / 2.0
		existing.add_child(ShipModels.build(kind))
		revealed.add_child(existing)

	# Fire where the shell went in.
	var burn := Effects.make_fire()
	burn.one_shot = false
	burn.position = Vector3(ShipModels.segment_offset(kind, segment), 6.0, 0.0)
	existing.add_child(burn)
	var smoke := Effects.make_smoke()
	smoke.position = burn.position
	smoke.emitting = true
	existing.add_child(smoke)

# ----------------------------------------------------------- laying out

## Before the battle the table carries your own water instead of the enemy's,
## and the same clicks that will later call a target lay your fleet out.
##
## Doing it here rather than on a flat screen keeps the promise the game makes:
## everything happens on the ship. It also means the player has already used
## the table once, and knows where it is and how it reads, before it starts
## mattering.

signal fleet_laid_out

var placing := false
var placing_index := 0
var placing_horizontal := true
var own_board: Board = null

func begin_placement(board: Board) -> void:
	own_board = board
	own_board.ships.clear()
	placing = true
	placing_index = 0
	placing_horizontal = true
	table.chart.reveal_ships = true
	table.set_board(own_board)
	table.chart.last_shot = Vector2i(-1, -1)
	set_mode(Mode.PLOT)
	_apply_mode(Mode.PLOT)

func placing_kind() -> Ship.Kind:
	return Board.FLEET[clampi(placing_index, 0, Board.FLEET.size() - 1)]

func turn_ship() -> void:
	placing_horizontal = not placing_horizontal
	_preview(table.hovered)

func scatter_fleet(rng: RandomNumberGenerator) -> void:
	own_board.ships.clear()
	own_board.random_layout(rng)
	placing_index = Board.FLEET.size()
	table.chart.preview_cells = []
	table.refresh()

func fleet_is_laid_out() -> bool:
	return placing_index >= Board.FLEET.size()

func finish_placement(enemy: Board) -> void:
	placing = false
	table.chart.reveal_ships = false
	table.chart.preview_cells = []
	set_enemy_board(enemy)
	fleet_laid_out.emit()

func _preview(cell: Vector2i) -> void:
	if not placing or fleet_is_laid_out() or not Board.in_bounds(cell):
		table.chart.preview_cells = []
		table.refresh()
		return
	var probe := Ship.new(placing_kind(), cell, placing_horizontal)
	table.chart.preview_cells = probe.cells()
	table.chart.preview_legal = own_board.can_place(placing_kind(), cell, placing_horizontal)
	table.refresh()

func _place_ship(cell: Vector2i) -> void:
	if fleet_is_laid_out():
		return
	if not own_board.place(placing_kind(), cell, placing_horizontal):
		return
	placing_index += 1
	table.refresh()
	_preview(cell)

# ------------------------------------------------------- taking it yourself

## A round arriving on your own fleet.
##
## The enemy's turn is not a line of text. Whatever they hit, the player is
## standing on the ship next to it: a near miss throws a column of sea up
## alongside, a hit on one of your escorts burns on your beam, and a hit on the
## flagship herself lands on the deck under your feet and shakes the bridge.

signal incoming_shown

var _shake := 0.0
var _incoming_shell: MeshInstance3D

func take_incoming(result: Dictionary, target_kind: int = -1) -> void:
	var where := _where_they_hit(result, target_kind)
	Sound.play("whistle", -6.0)
	await get_tree().create_timer(1.1).timeout

	var burst := Effects.make_fire()
	burst.position = where
	fleet.add_child(burst)
	var smoke := Effects.make_smoke()
	smoke.position = where
	smoke.emitting = true
	fleet.add_child(smoke)
	var spray := Effects.make_spray()
	spray.position = Vector3(where.x, 1.0, where.z)
	fleet.add_child(spray)

	Sound.play("hit", -1.0, randf_range(0.9, 1.05))
	# How hard the bridge is thrown about depends on how close it landed. A
	# miss half a mile off should not rattle the binnacle.
	var distance := camera.global_position.distance_to(fleet.to_global(where))
	_shake = clampf(420.0 / maxf(distance, 60.0), 0.0, 1.0)

	await get_tree().create_timer(2.2).timeout
	smoke.emitting = false
	incoming_shown.emit()

## Where on your fleet the round went in. A miss falls in open water near the
## flagship; a hit lands on whichever of your ships was found.
func _where_they_hit(result: Dictionary, target_kind: int) -> Vector3:
	if result.get("outcome", "miss") == "miss" or target_kind < 0:
		var angle := randf() * TAU
		return Vector3(cos(angle), 0.0, sin(angle)) * randf_range(140.0, 420.0)
	if target_kind == Ship.Kind.BATTLESHIP:
		# The flagship: on her own deck, forward of the bridge where it can be
		# seen without turning round.
		return flagship.position + Vector3(_length * 0.24, 12.0, 6.0)
	for station in escorts.get_children():
		if int(station.get_meta("kind", -1)) == target_kind:
			var kind: Ship.Kind = target_kind
			var along := ShipModels.segment_offset(kind, result.get("segment", 0))
			return station.position + Vector3(along - ShipModels.hull_length(kind) * 0.5, 9.0, 0.0)
	return Vector3.ZERO

# ------------------------------------------------------------- the war

## Everything that says this is a battle rather than a cruise.
##
## None of it is playable and none of it affects the rules. It is here because
## an empty sea with two ships on it reads as a demo, and the game is supposed
## to be a fleet action: wrecks burning on the horizon, aircraft going over,
## gunfire somewhere else. It is also all cheap - smoke, a handful of silhouettes
## and some lights - because it is scenery and must never cost more than the
## thing it is decorating.

const PLANES := "res://assets/sketchfab/low_poly_ww2_fighter_planes/low_poly_ww2_fighter_planes.glb"
const WRECK_COUNT := 3
const FLIGHT_HEIGHT := 620.0
const FLIGHT_SPEED := 135.0

var war: Node3D
var _flight: Node3D
var _gun_flash: OmniLight3D
var _flash_timer := 6.0

func _build_war() -> void:
	war = Node3D.new()
	war.name = "War"
	fleet.add_child(war)
	_build_wrecks()
	_build_flight()
	_build_distant_gunfire()
	_build_funnel_smoke()

## Ships already lost, burning a long way off. They are only the top of a hull
## and a column of smoke, because at eight kilometres that is all a ship is.
func _build_wrecks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260917
	for i in WRECK_COUNT:
		# Fixed bearings rather than random ones. Scenery that is only
		# sometimes in front of the player is scenery that is usually wasted,
		# and a random spread put all three of these behind the funnels twice
		# running. These three sit across the bows: one close on the starboard
		# bow, one further out to port, one hull down on the beam.
		var bearing := deg_to_rad([22.0, -26.0, 63.0][i])
		var distance: float = [3100.0, 6200.0, 9400.0][i]
		var at := Vector3(-cos(bearing), 0.0, -sin(bearing)) * distance

		var hulk := Node3D.new()
		hulk.position = at
		hulk.rotation.y = rng.randf_range(0.0, TAU)
		war.add_child(hulk)

		# A dark shape low in the water. Listing, because a ship that has
		# stopped burning upright has stopped being a wreck.
		var hull := BoxMesh.new()
		hull.size = Vector3(rng.randf_range(90.0, 150.0), 12.0, 16.0)
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.09, 0.10, 0.11)
		dark.roughness = 0.85
		var body := MeshInstance3D.new()
		body.mesh = hull
		body.material_override = dark
		body.rotation.z = deg_to_rad(rng.randf_range(6.0, 22.0))
		body.position.y = 1.5
		hulk.add_child(body)

		var column := Effects.make_smoke()
		# Many small puffs rather than a few big ones. Ninety puffs a hundred
		# and seventy metres across do not make a column - they make two brown
		# balls sitting on the horizon.
		var rise: ParticleProcessMaterial = column.process_material
		rise.initial_velocity_min = 26.0
		rise.initial_velocity_max = 52.0
		rise.gravity = Vector3(7.0, 7.0, 0.0)
		rise.spread = 14.0
		rise.turbulence_noise_strength = 0.6
		column.amount = 320
		column.lifetime = 34.0
		column.draw_pass_1 = Effects.quad(95.0)
		# Unshaded, because oily smoke a mile off is a dark shape against the
		# sky whatever the sun is doing - lit like a solid it came out a
		# cheerful tan.
		var soot := Effects.billboard(Color(1, 1, 1), false, 95.0)
		soot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		soot.albedo_color = Color(0.30, 0.29, 0.28)
		column.material_override = soot
		column.position.y = 8.0
		# Already burning when the player arrives. A particle system starts
		# empty and takes its whole lifetime to fill; without this a wreck that
		# has been on fire for an hour shows three small puffs.
		column.preprocess = 24.0
		Effects.room_to_work(column, 1400.0)
		column.emitting = true
		hulk.add_child(column)

## A flight going over, high and unhurried. They are somebody else's aircraft
## on somebody else's errand, which is the point: the war is bigger than you.
func _build_flight() -> void:
	if not ResourceLoader.exists(PLANES):
		return
	_flight = Node3D.new()
	_flight.position = Vector3(2600.0, FLIGHT_HEIGHT, -1600.0)
	war.add_child(_flight)
	var pack := (load(PLANES) as PackedScene).instantiate()
	var box := ShipModels.measure(pack)
	# The pack arrives at whatever size its author used; scale it so a fighter
	# is about eleven metres across, and take the whole pack as the formation.
	var wanted := 11.0
	var widest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	if widest > 0.001:
		pack.scale = Vector3.ONE * (wanted / widest * 3.0)
	_flight.add_child(pack)

## Somebody else's battle, over the horizon: a flash, and the rumble long
## afterwards, which is what distance sounds like.
func _build_distant_gunfire() -> void:
	_gun_flash = OmniLight3D.new()
	_gun_flash.position = Vector3(-4200.0, 30.0, 8800.0)
	_gun_flash.light_color = Color(1.0, 0.8, 0.5)
	_gun_flash.light_energy = 0.0
	_gun_flash.omni_range = 1800.0
	war.add_child(_gun_flash)

## Funnel smoke on the escorts. A warship under way is never clean.
func _build_funnel_smoke() -> void:
	for station in escorts.get_children():
		var kind: int = station.get_meta("kind", -1)
		if kind == Ship.Kind.SUBMARINE:
			continue
		var length := ShipModels.hull_length(kind)
		var trail := Effects.make_smoke()
		var drift: ParticleProcessMaterial = trail.process_material
		drift.initial_velocity_min = 4.0
		drift.initial_velocity_max = 11.0
		drift.gravity = Vector3(9.0, 3.0, 0.0)
		trail.amount = 40
		trail.lifetime = 14.0
		trail.draw_pass_1 = Effects.quad(26.0)
		var haze := Effects.billboard(Color(1, 1, 1), false, 26.0)
		haze.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		haze.albedo_color = Color(0.42, 0.42, 0.43, 0.55)
		trail.material_override = haze
		trail.position = Vector3(length * 0.08, length * 0.10, 0.0)
		trail.preprocess = 12.0
		Effects.room_to_work(trail, 400.0)
		trail.emitting = true
		station.add_child(trail)

func _tick_war(delta: float) -> void:
	if _flight != null:
		# Straight across the fleet and away. When it has gone, it comes round
		# again from the other quarter rather than being deleted and rebuilt.
		_flight.position.x -= FLIGHT_SPEED * delta
		if _flight.position.x < -4200.0:
			_flight.position = Vector3(3400.0, FLIGHT_HEIGHT, randf_range(-2200.0, 900.0))

	if _gun_flash != null:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_timer = randf_range(4.0, 13.0)
			var burst := create_tween()
			burst.tween_property(_gun_flash, "light_energy", randf_range(6.0, 16.0), 0.05)
			burst.tween_property(_gun_flash, "light_energy", 0.0, 0.35)
			# The sound arrives a long way behind the light.
			get_tree().create_timer(randf_range(2.5, 6.0)).timeout.connect(
				func(): Sound.play("sink", -22.0, randf_range(0.45, 0.6)))
