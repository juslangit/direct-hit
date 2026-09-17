extends Control

## The game as the player meets it: a menu, a chart to lay your fleet out on,
## two charts to fight over, and the cutscene dropped on top whenever a shell
## finds something.
##
## The rules live in Game (match_state.gd) and the staging lives in the
## cutscene. This file is the stage manager - it decides which screen is up and
## what happens after a shot has finished being shown, and nothing else.

const PLAYER_NAMES := ["Player 1", "Player 2"]

var _screens: Dictionary = {}
var _grid_place: GridView
var _grid_own: GridView
var _grid_enemy: GridView
var _fleet_own: FleetPanel
var _fleet_enemy: FleetPanel
var _message: Label
var _turn_label: Label
var _place_title: Label
var _place_hint: Label
var _ready_button: Button
var _handover_title: Label
var _handover_note: Label
var _over_title: Label
var _over_detail: Label
var _scrim: ColorRect
var _skip_hint: Label
var _title_sea_running := false

var _cutscene_layer: Control
var _cutscene_viewport: SubViewport
var _cutscene: Node3D
var _banner: Label
var _banner_sub: Label

# Placement, which happens once against the computer and twice for two players.
var _placing_player := Board.SIZE  # set properly when placement starts
var _placing_index := 0
var _placing_horizontal := true
var _placement_boards: Array[Board] = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Palette.PAPER
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	_build_cutscene_layer()
	_build_menu()
	_build_placement()
	_build_battle()
	_build_handover()
	_build_over()

	Game.match_over.connect(_on_match_over)
	_show("menu")

func _show(which: String) -> void:
	for name in _screens:
		_screens[name].visible = name == which
	_set_title_sea(which == "menu")

## The sea runs behind the title screen and nowhere else. It is a third of a
## million vertices; leaving it turning behind the charts would cost a great
## deal to show nobody anything.
func _set_title_sea(on: bool) -> void:
	if on == _title_sea_running:
		return
	_title_sea_running = on
	_cutscene_layer.visible = on
	_scrim.visible = on
	_banner.visible = not on
	_banner_sub.visible = not on
	_skip_hint.visible = not on
	if on:
		_cutscene_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_cutscene.process_mode = Node.PROCESS_MODE_INHERIT
		_cutscene.showcase(Board.FLEET[Game.rng.randi_range(0, Board.FLEET.size() - 1)])
	else:
		_cutscene.stop_showcase()
		_cutscene_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_cutscene.process_mode = Node.PROCESS_MODE_DISABLED

func _new_screen(name: String) -> VBoxContainer:
	var holder := VBoxContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_theme_constant_override("separation", 18)
	add_child(holder)
	_screens[name] = holder
	holder.visible = false
	return holder

# ------------------------------------------------------------------- menu

func _build_menu() -> void:
	var screen := _new_screen("menu")
	var title := UiKit.heading("DIRECT HIT", 96, Palette.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tagline := UiKit.body("Every hit is a real ship taking a real shell.", 26)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	var versus_ai := UiKit.button("PLAY THE COMPUTER", true)
	versus_ai.pressed.connect(func(): _begin(Game.Mode.VS_AI))
	var two_player := UiKit.button("TWO PLAYERS", true)
	two_player.pressed.connect(func(): _begin(Game.Mode.PASS_AND_PLAY))
	row.add_child(versus_ai)
	row.add_child(two_player)

	screen.add_child(title)
	screen.add_child(tagline)
	screen.add_child(UiKit.spacer(40))
	screen.add_child(row)

func _begin(mode: Game.Mode) -> void:
	Game.start_match(mode)
	_placement_boards = Game.boards
	_start_placement(Game.HUMAN)

# -------------------------------------------------------------- placement

func _build_placement() -> void:
	var screen := _new_screen("placement")
	_place_title = UiKit.heading("POSITION YOUR FLEET", 44)
	_place_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place_hint = UiKit.body("Click to lay a ship down. R turns her.", 22)
	_place_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var middle := HBoxContainer.new()
	middle.alignment = BoxContainer.ALIGNMENT_CENTER
	middle.add_theme_constant_override("separation", 40)

	_grid_place = GridView.new()
	_grid_place.reveal_ships = true
	_grid_place.custom_minimum_size = Vector2(620, 620)
	_grid_place.cell_pressed.connect(_on_place_pressed)
	_grid_place.cell_hovered.connect(_on_place_hovered)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 12)
	side.custom_minimum_size = Vector2(300, 0)
	_fleet_own = FleetPanel.new()
	var rotate := UiKit.button("TURN  (R)")
	rotate.pressed.connect(_rotate_placement)
	var shuffle := UiKit.button("SCATTER THEM")
	shuffle.pressed.connect(_random_placement)
	var clear := UiKit.button("START OVER")
	clear.pressed.connect(func(): _start_placement(_placing_player))
	_ready_button = UiKit.button("PUT TO SEA")
	_ready_button.disabled = true
	_ready_button.pressed.connect(_finish_placement)

	side.add_child(UiKit.heading("FLEET", 26, Palette.BRASS))
	side.add_child(_fleet_own)
	side.add_child(UiKit.spacer(10))
	side.add_child(rotate)
	side.add_child(shuffle)
	side.add_child(clear)
	side.add_child(UiKit.spacer(10))
	side.add_child(_ready_button)

	middle.add_child(_grid_place)
	middle.add_child(side)

	screen.add_child(_place_title)
	screen.add_child(_place_hint)
	screen.add_child(middle)

func _start_placement(player: int) -> void:
	_placing_player = player
	_placing_index = 0
	_placing_horizontal = true
	Game.boards[player] = Board.new()
	_grid_place.set_board(Game.boards[player])
	_fleet_own.board = Game.boards[player]
	_fleet_own.hide_intact = false
	_fleet_own.queue_redraw()
	_grid_place.preview_cells = []
	_ready_button.disabled = true
	_place_title.text = "POSITION YOUR FLEET"
	if Game.mode == Game.Mode.PASS_AND_PLAY:
		_place_title.text = "%s - POSITION YOUR FLEET" % PLAYER_NAMES[player]
	_update_placement_hint()
	_show("placement")

func _placing_kind() -> Ship.Kind:
	return Board.FLEET[_placing_index]

func _update_placement_hint() -> void:
	if _placing_index >= Board.FLEET.size():
		_place_hint.text = "The fleet is at sea. Put to sea when you are ready."
		return
	var kind := _placing_kind()
	_place_hint.text = "Laying the %s - %d squares. R turns her." % [
		Ship.SPECS[kind]["name"], Ship.SPECS[kind]["length"]
	]

func _rotate_placement() -> void:
	_placing_horizontal = not _placing_horizontal
	_on_place_hovered(_grid_place.hovered)

func _random_placement() -> void:
	var board: Board = Game.boards[_placing_player]
	board.ships.clear()
	board.random_layout(Game.rng)
	_placing_index = Board.FLEET.size()
	_grid_place.preview_cells = []
	_grid_place.queue_redraw()
	_fleet_own.queue_redraw()
	_ready_button.disabled = false
	_update_placement_hint()

func _on_place_hovered(cell: Vector2i) -> void:
	if _placing_index >= Board.FLEET.size() or not Board.in_bounds(cell):
		_grid_place.preview_cells = []
		_grid_place.queue_redraw()
		return
	var kind := _placing_kind()
	var probe := Ship.new(kind, cell, _placing_horizontal)
	_grid_place.preview_cells = probe.cells()
	_grid_place.preview_legal = Game.boards[_placing_player].can_place(kind, cell, _placing_horizontal)
	_grid_place.queue_redraw()

func _on_place_pressed(cell: Vector2i) -> void:
	if _placing_index >= Board.FLEET.size():
		return
	var board: Board = Game.boards[_placing_player]
	if not board.place(_placing_kind(), cell, _placing_horizontal):
		return
	_placing_index += 1
	_grid_place.preview_cells = []
	_grid_place.queue_redraw()
	_fleet_own.queue_redraw()
	_ready_button.disabled = _placing_index < Board.FLEET.size()
	_update_placement_hint()
	_on_place_hovered(cell)

func _finish_placement() -> void:
	if Game.mode == Game.Mode.PASS_AND_PLAY and _placing_player == Game.HUMAN:
		_go_to_handover("PASS THE DEVICE", "%s lays her fleet out next." % PLAYER_NAMES[Game.OPPONENT],
			func(): _start_placement(Game.OPPONENT))
		return
	_open_battle()

# ----------------------------------------------------------------- battle

func _build_battle() -> void:
	var screen := _new_screen("battle")

	_turn_label = UiKit.heading("YOUR TURN", 38, Palette.BRASS)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var charts := HBoxContainer.new()
	charts.alignment = BoxContainer.ALIGNMENT_CENTER
	charts.add_theme_constant_override("separation", 56)

	charts.add_child(_build_chart_column("YOUR WATERS", true))
	charts.add_child(_build_chart_column("ENEMY WATERS", false))

	_message = UiKit.body("Call a square.", 26, Palette.INK)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	screen.add_child(_turn_label)
	screen.add_child(charts)
	screen.add_child(_message)

func _build_chart_column(title: String, is_own: bool) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	var heading := UiKit.heading(title, 26, Palette.BRASS if not is_own else Palette.INK_DIM)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var grid := GridView.new()
	grid.custom_minimum_size = Vector2(560, 560)
	grid.reveal_ships = is_own
	grid.interactive = not is_own
	var fleet := FleetPanel.new()
	fleet.hide_intact = not is_own

	if is_own:
		_grid_own = grid
		_fleet_own = fleet
	else:
		_grid_enemy = grid
		_fleet_enemy = fleet
		grid.cell_pressed.connect(_on_fire_pressed)

	column.add_child(heading)
	column.add_child(grid)
	column.add_child(fleet)
	return column

func _open_battle() -> void:
	Game.phase = Game.Phase.PLAYING
	_refresh_battle()
	_show("battle")
	_message.text = "Call a square."

## Whose charts are on screen.
##
## In a two-player game the device changes hands, so the view follows whoever
## is holding it. Against the computer it must not: the view stays with the
## player even while the computer is aiming. Following current_player in both
## modes put the computer's own fleet on the left-hand chart, face up, every
## time it took a turn.
func _viewpoint() -> int:
	return Game.current_player if Game.mode == Game.Mode.PASS_AND_PLAY else Game.HUMAN

func _refresh_battle() -> void:
	var me := _viewpoint()
	_grid_own.set_board(Game.boards[me])
	_grid_enemy.set_board(Game.boards[1 - me])
	_fleet_own.set_board(Game.boards[me])
	_fleet_enemy.set_board(Game.boards[1 - me])
	_fleet_own.hide_intact = false
	_fleet_enemy.hide_intact = true
	if Game.mode == Game.Mode.VS_AI:
		_turn_label.text = "YOUR TURN" if Game.current_player == Game.HUMAN else "THE ENEMY IS AIMING"
	else:
		_turn_label.text = "%s - YOUR TURN" % PLAYER_NAMES[me]
	_grid_enemy.interactive = _is_players_turn()

func _is_players_turn() -> bool:
	if Game.phase != Game.Phase.PLAYING:
		return false
	return Game.mode == Game.Mode.PASS_AND_PLAY or Game.current_player == Game.HUMAN

func _on_fire_pressed(cell: Vector2i) -> void:
	if not _is_players_turn():
		return
	var result := Game.fire_at(cell)
	if not result.get("valid", false):
		_message.text = "You have already shot there."
		return
	_resolve(result)

func _resolve(result: Dictionary) -> void:
	if Game.current_player == _viewpoint():
		_grid_enemy.last_shot = result["cell"]
	else:
		_grid_own.last_shot = result["cell"]
	_grid_enemy.interactive = false
	_grid_own.queue_redraw()
	_grid_enemy.queue_redraw()
	_fleet_own.queue_redraw()
	_fleet_enemy.queue_redraw()

	if result["outcome"] == "miss":
		Sound.play("splash", -6.0, 0.55)
		_message.text = "Nothing there. Just water."
		await get_tree().create_timer(0.85).timeout
		_after_shot()
		return

	_message.text = "%s hit." % result["ship_name"]
	await _play_cutscene(result)
	_after_shot()

func _after_shot() -> void:
	if Game.phase == Game.Phase.OVER:
		return
	Game.end_turn()
	if Game.mode == Game.Mode.PASS_AND_PLAY:
		var next: int = Game.current_player
		_go_to_handover("PASS THE DEVICE", "%s takes the next shot." % PLAYER_NAMES[next],
			func(): _open_battle())
		return
	_refresh_battle()
	if Game.current_player == Game.OPPONENT:
		_message.text = "The enemy is aiming..."
		await get_tree().create_timer(0.9).timeout
		var result := Game.take_ai_turn()
		if result.get("valid", false):
			_resolve(result)
	else:
		_message.text = "Call a square."

# -------------------------------------------------------------- cutscene

func _build_cutscene_layer() -> void:
	_cutscene_layer = Control.new()
	_cutscene_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cutscene_layer.visible = false
	_cutscene_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cutscene_layer)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cutscene_layer.add_child(container)

	_cutscene_viewport = SubViewport.new()
	_cutscene_viewport.size = Vector2i(1920, 1080)
	_cutscene_viewport.handle_input_locally = false
	# The ocean is a third of a million vertices. It renders only while it is
	# being watched; left running it would drag the board screen down for no
	# reason at all.
	_cutscene_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(_cutscene_viewport)

	_cutscene = (load("res://scenes/cutscene.tscn") as PackedScene).instantiate()
	_cutscene_viewport.add_child(_cutscene)
	_cutscene.process_mode = Node.PROCESS_MODE_DISABLED

	# Behind the title, the sea is a backdrop and the words have to stay
	# readable over it.
	_scrim = ColorRect.new()
	_scrim.color = Color(Palette.PAPER.r, Palette.PAPER.g, Palette.PAPER.b, 0.40)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cutscene_layer.add_child(_scrim)

	var caption := VBoxContainer.new()
	# TOP_WIDE, not CENTER_TOP: the centre preset anchors the box to a point
	# and then lets it grow to the right, which pushed the banner off to one
	# side of the screen.
	caption.set_anchors_preset(Control.PRESET_TOP_WIDE)
	caption.offset_top = 52.0
	caption.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner = UiKit.heading("HIT", 78, Palette.HIT_GLOW)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub = UiKit.body("", 30, Palette.INK)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_child(_banner)
	caption.add_child(_banner_sub)
	_cutscene_layer.add_child(caption)

	_skip_hint = UiKit.body("click to skip", 20, Palette.INK_DIM)
	_skip_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_hint.offset_left = -220.0
	_skip_hint.offset_top = -60.0
	_cutscene_layer.add_child(_skip_hint)

func _play_cutscene(result: Dictionary) -> void:
	var sunk: bool = result["outcome"] == "sunk"
	_banner.text = "SUNK" if sunk else "HIT"
	_banner.add_theme_color_override("font_color", Palette.HIT if sunk else Palette.HIT_GLOW)
	_banner_sub.text = "%s, %s" % [result["ship_name"], _square_name(result["cell"])]

	_cutscene_layer.visible = true
	_scrim.visible = false
	_banner.visible = true
	_banner_sub.visible = true
	_skip_hint.visible = true
	move_child(_cutscene_layer, get_child_count() - 1)
	_cutscene_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_cutscene.process_mode = Node.PROCESS_MODE_INHERIT
	_cutscene.play(result)
	await _cutscene.finished
	_cutscene.process_mode = Node.PROCESS_MODE_DISABLED
	_cutscene_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_cutscene_layer.visible = false
	move_child(_cutscene_layer, 1)

func _square_name(cell: Vector2i) -> String:
	return "%s%d" % [GridView.LETTERS[cell.y], cell.x + 1]

func _unhandled_input(event: InputEvent) -> void:
	if _cutscene_layer.visible and event is InputEventMouseButton and event.pressed:
		_cutscene.skip()
		return
	if _screens.get("placement", null) != null and _screens["placement"].visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			_rotate_placement()

# -------------------------------------------------------------- handover

func _build_handover() -> void:
	var screen := _new_screen("handover")
	_handover_title = UiKit.heading("PASS THE DEVICE", 66, Palette.BRASS)
	_handover_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_handover_note = UiKit.body("", 28)
	_handover_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var go := UiKit.button("I AM READY", true)
	go.pressed.connect(_leave_handover)
	row.add_child(go)
	screen.add_child(_handover_title)
	screen.add_child(_handover_note)
	screen.add_child(UiKit.spacer(30))
	screen.add_child(row)

var _handover_next: Callable = Callable()

func _go_to_handover(title: String, note: String, next: Callable) -> void:
	_handover_title.text = title
	_handover_note.text = note
	_handover_next = next
	_show("handover")

func _leave_handover() -> void:
	var next := _handover_next
	_handover_next = Callable()
	if next.is_valid():
		next.call()

# ------------------------------------------------------------------- over

func _build_over() -> void:
	var screen := _new_screen("over")
	_over_title = UiKit.heading("VICTORY", 86, Palette.BRASS)
	_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_detail = UiKit.body("", 28)
	_over_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	var again := UiKit.button("SAIL AGAIN", true)
	again.pressed.connect(func(): _begin(Game.mode))
	var menu := UiKit.button("BACK TO PORT", true)
	menu.pressed.connect(func(): _show("menu"))
	row.add_child(again)
	row.add_child(menu)
	screen.add_child(_over_title)
	screen.add_child(_over_detail)
	screen.add_child(UiKit.spacer(30))
	screen.add_child(row)

func _on_match_over(winner: int) -> void:
	await get_tree().create_timer(0.3).timeout
	if _cutscene_layer.visible:
		await _cutscene.finished
	if Game.mode == Game.Mode.VS_AI:
		_over_title.text = "VICTORY" if winner == Game.HUMAN else "YOUR FLEET IS GONE"
	else:
		_over_title.text = "%s WINS" % PLAYER_NAMES[winner]
	_over_detail.text = "%d shots, %d of them hits - %.0f%% accuracy." % [
		Game.shots_fired[winner], Game.hits_landed[winner], Game.accuracy(winner) * 100.0
	]
	_show("over")
