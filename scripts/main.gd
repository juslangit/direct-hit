extends Node

## The stage manager.
##
## The game is the bridge: a 3D world that exists from the moment the program
## starts, and which the title screen is simply drawn over. This file decides
## which screen is up and what happens after a shot has been shown, and nothing
## else. The rules live in Game, the staging lives on the bridge, and the close
## view of a ship taking a shell lives in the cutscene.

const PLAYER_NAMES := ["Player 1", "Player 2"]

var bridge: Node3D
var ui: CanvasLayer
var screens: Dictionary = {}
var banner: Label
var turn_line: Label
var over_title: Label
var over_detail: Label
var handover_note: Label
var place_hint: Label
var ready_button: Button

var cutscene_layer: CanvasLayer
var cutscene_viewport: SubViewport
var cutscene: Node3D
var cut_banner: Label
var cut_sub: Label

var _handover_next: Callable = Callable()
var _current := "menu"
var _paused_from := ""
var _placing_player := 0

func _ready() -> void:
	# No bridge yet. It is built when a match starts and torn down when the
	# player goes back to port, so the menu is a screen rather than a window
	# onto a game that is already running.
	ui = CanvasLayer.new()
	ui.layer = 2
	add_child(ui)
	_build_menu()
	_build_pause()
	_build_placement_bar()
	_build_handover()
	_build_over()
	_build_cutscene_layer()

	Game.match_over.connect(_on_match_over)
	_show("menu")

func _show(which: String) -> void:
	_current = which
	for name in screens:
		screens[name].visible = name == which
	# With no bridge built there is nothing to hand the pointer to.
	if bridge == null:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	# The bridge only takes the mouse while the game is actually being played.
	# A captured pointer over a menu is a trap.
	bridge.capture_mouse = which == ""
	# The bridge's own instruments belong to the bridge. With a menu up they
	# are telling the player about keys that do nothing yet.
	bridge.hud.visible = which == ""

func _new_screen(name: String, centred := true) -> VBoxContainer:
	var holder := VBoxContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The holder covers the whole screen, and a Control that covers the whole
	# screen swallows every click before it reaches the world behind it. The
	# buttons inside it still get their own clicks; the empty space must not.
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.alignment = BoxContainer.ALIGNMENT_CENTER if centred else BoxContainer.ALIGNMENT_END
	holder.add_theme_constant_override("separation", 18)
	ui.add_child(holder)
	screens[name] = holder
	holder.visible = false
	return holder

# -------------------------------------------------------------------- menu

## A way out, at any moment.
##
## Once the battle starts the bridge takes the pointer, and a captured pointer
## with no pause and no quit is a trap: the cursor is gone, nothing on screen
## says how to get it back, and the only way out is to kill the program. ESC
## now always reaches this, whatever the player is in the middle of.
func _build_pause() -> void:
	var screen := _new_screen("pause")
	var scrim := ColorRect.new()
	scrim.color = Color(Palette.PAPER.r, Palette.PAPER.g, Palette.PAPER.b, 0.78)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(scrim)
	screen.move_child(scrim, 0)

	var title := UiKit.heading("STAND EASY", 62, Palette.BRASS)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var keys := UiKit.body(
		"mouse  look around the bridge\n" +
		"T  the plotting table, and back\n" +
		"SPACE  the gun sight, then fire\n" +
		"R or right click  turn a ship while laying out\n" +
		"ESC  this screen", 26)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	var resume := UiKit.button("CARRY ON", true)
	resume.pressed.connect(_resume)
	var port := UiKit.button("BACK TO PORT")
	port.pressed.connect(_to_port)
	var quit := UiKit.button("LEAVE THE SHIP")
	quit.pressed.connect(func(): get_tree().quit())
	row.add_child(resume)
	row.add_child(port)
	row.add_child(quit)

	screen.add_child(title)
	screen.add_child(keys)
	screen.add_child(UiKit.spacer(24))
	screen.add_child(row)

func _pause() -> void:
	if screens["pause"].visible or screens["menu"].visible or screens["over"].visible:
		return
	_paused_from = _current
	_show("pause")

func _resume() -> void:
	_show(_paused_from)
	if _paused_from == "":
		bridge.refresh_mouse_mode()

func _build_menu() -> void:
	var menu: Control = (load("res://scenes/menu.tscn") as PackedScene).instantiate()
	menu.play_requested.connect(func(mode: int): _begin(mode as Game.Mode))
	menu.quit_requested.connect(func(): get_tree().quit())
	ui.add_child(menu)
	screens["menu"] = menu
	menu.visible = false

## Build the world, once, when there is finally a reason to.
func _ensure_bridge() -> void:
	if bridge != null:
		return
	bridge = (load("res://scenes/bridge.tscn") as PackedScene).instantiate()
	add_child(bridge)
	move_child(bridge, 0)
	bridge.shot_requested.connect(_on_shot_requested)
	bridge.shot_landed.connect(_on_shot_landed)

## Back to port: the ocean, the fleet and the weather all stop existing.
func _to_port() -> void:
	if bridge != null:
		# Out of the tree first, then freed. queue_free() alone defers to the
		# end of the frame, so starting a new match in the same frame leaves two
		# bridges and two cameras alive at once and whichever entered last wins.
		remove_child(bridge)
		bridge.queue_free()
		bridge = null
	_show("menu")

func _begin(mode: Game.Mode) -> void:
	_ensure_bridge()
	Game.start_match(mode)
	_start_placement(Game.HUMAN)

# --------------------------------------------------------------- placement

func _build_placement_bar() -> void:
	var screen := _new_screen("placement", false)
	place_hint = UiKit.body("", 24, Palette.INK)
	place_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	var turn := UiKit.button("TURN HER  (R)")
	turn.pressed.connect(func(): bridge.turn_ship(); _update_place_hint())
	var scatter := UiKit.button("SCATTER THEM")
	scatter.pressed.connect(func(): bridge.scatter_fleet(Game.rng); _update_place_hint())
	ready_button = UiKit.button("PUT TO SEA")
	ready_button.pressed.connect(_finish_placement)
	row.add_child(turn)
	row.add_child(scatter)
	row.add_child(ready_button)

	screen.add_child(place_hint)
	screen.add_child(row)
	screen.add_child(UiKit.spacer(40))

func _start_placement(player: int) -> void:
	_placing_player = player
	Game.boards[player] = Board.new()
	bridge.begin_placement(Game.boards[player])
	_update_place_hint()
	_show("placement")

func _update_place_hint() -> void:
	if bridge.fleet_is_laid_out():
		place_hint.text = "The fleet is at sea."
		ready_button.disabled = false
		return
	ready_button.disabled = true
	var kind: Ship.Kind = bridge.placing_kind()
	var who := "" if Game.mode == Game.Mode.VS_AI else "%s - " % PLAYER_NAMES[_placing_player]
	var lying := "across" if bridge.placing_horizontal else "up and down"
	place_hint.text = "%sLay the %s on the plot - %d squares, lying %s. R or right click turns her." % [
		who, Ship.SPECS[kind]["name"], Ship.SPECS[kind]["length"], lying]

func _finish_placement() -> void:
	if not bridge.fleet_is_laid_out():
		return
	if Game.mode == Game.Mode.PASS_AND_PLAY and _placing_player == Game.HUMAN:
		_go_to_handover("PASS THE DEVICE", "%s lays her fleet out next." % PLAYER_NAMES[Game.OPPONENT],
			func(): _start_placement(Game.OPPONENT))
		return
	_open_battle()

# ------------------------------------------------------------------ battle

func _open_battle() -> void:
	Game.phase = Game.Phase.PLAYING
	bridge.finish_placement(Game.boards[1 - Game.current_player])
	# The screen goes first. Handing the bridge the mouse and then telling it
	# which mode it is in is the wrong way round - see refresh_mouse_mode.
	_show("")
	bridge.set_mode(0)
	_say("Find them. T for the plotting table.")

func _say(text: String) -> void:
	bridge.hud.message = text
	bridge.hud.queue_redraw()

func _on_shot_requested(cell: Vector2i) -> void:
	if Game.phase != Game.Phase.PLAYING:
		return
	var result := Game.fire_at(cell)
	if not result.get("valid", false):
		_say("You have already shot there.")
		return
	_say("")
	bridge.play_shot(result)

func _on_shot_landed(result: Dictionary) -> void:
	if result["outcome"] == "miss":
		_say("Nothing there. Just water.")
		await get_tree().create_timer(1.0).timeout
		_after_shot()
		return
	await _play_cutscene(result)
	bridge.reveal(result)
	bridge.refresh_plot()
	_say("%s hit." % result["ship_name"])
	_after_shot()

func _after_shot() -> void:
	if Game.phase == Game.Phase.OVER:
		return
	Game.end_turn()
	if Game.mode == Game.Mode.PASS_AND_PLAY:
		_go_to_handover("PASS THE DEVICE",
			"%s takes the next shot." % PLAYER_NAMES[Game.current_player],
			func(): _open_battle())
		return
	bridge.clear_mark()
	if Game.current_player == Game.OPPONENT:
		_say("They have our range.")
		await get_tree().create_timer(1.2).timeout
		var result := Game.take_ai_turn()
		if result.get("valid", false):
			var kind: int = result.get("ship_kind", -1) if result["outcome"] != "miss" else -1
			bridge.take_incoming(result, kind)
			await bridge.incoming_shown
			_say("%s hit." % result["ship_name"] if result["outcome"] != "miss" else "Short. They missed.")
		_after_shot()
	else:
		bridge.clear_mark()
		_say("Your shot. T for the plotting table.")

# ---------------------------------------------------------------- cutscene

func _build_cutscene_layer() -> void:
	cutscene_layer = CanvasLayer.new()
	cutscene_layer.layer = 3
	cutscene_layer.visible = false
	add_child(cutscene_layer)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cutscene_layer.add_child(container)

	cutscene_viewport = SubViewport.new()
	cutscene_viewport.size = Vector2i(1920, 1080)
	cutscene_viewport.handle_input_locally = false
	cutscene_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(cutscene_viewport)

	cutscene = (load("res://scenes/cutscene.tscn") as PackedScene).instantiate()
	cutscene_viewport.add_child(cutscene)
	cutscene.process_mode = Node.PROCESS_MODE_DISABLED

	var caption := VBoxContainer.new()
	caption.set_anchors_preset(Control.PRESET_TOP_WIDE)
	caption.offset_top = 52.0
	caption.alignment = BoxContainer.ALIGNMENT_CENTER
	cut_banner = UiKit.heading("HIT", 78, Palette.HIT_GLOW)
	cut_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cut_sub = UiKit.body("", 30, Palette.INK)
	cut_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_child(cut_banner)
	caption.add_child(cut_sub)
	cutscene_layer.add_child(caption)

func _play_cutscene(result: Dictionary) -> void:
	var sunk: bool = result["outcome"] == "sunk"
	cut_banner.text = "SUNK" if sunk else "HIT"
	cut_banner.add_theme_color_override("font_color", Palette.HIT if sunk else Palette.HIT_GLOW)
	cut_sub.text = "%s, %s" % [result["ship_name"], _square_name(result["cell"])]

	cutscene_layer.visible = true
	cutscene_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	cutscene.process_mode = Node.PROCESS_MODE_INHERIT
	cutscene.play(result)
	await cutscene.finished
	cutscene.process_mode = Node.PROCESS_MODE_DISABLED
	cutscene_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	cutscene_layer.visible = false

func _square_name(cell: Vector2i) -> String:
	return "%s%d" % [GridView.LETTERS[cell.y], cell.x + 1]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if screens["pause"].visible:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()
		return
	if cutscene_layer.visible and event is InputEventMouseButton and event.pressed:
		cutscene.skip()
	elif screens.has("placement") and screens["placement"].visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			_update_place_hint()

# -------------------------------------------------------------- handover

func _build_handover() -> void:
	var screen := _new_screen("handover")
	var scrim := ColorRect.new()
	scrim.color = Palette.PAPER
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(scrim)
	screen.move_child(scrim, 0)
	var title := UiKit.heading("PASS THE DEVICE", 66, Palette.BRASS)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	handover_note = UiKit.body("", 28)
	handover_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var go := UiKit.button("I AM READY", true)
	go.pressed.connect(_leave_handover)
	row.add_child(go)
	screen.add_child(title)
	screen.add_child(handover_note)
	screen.add_child(UiKit.spacer(30))
	screen.add_child(row)

func _go_to_handover(title: String, note: String, next: Callable) -> void:
	handover_note.text = note
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
	var scrim := ColorRect.new()
	scrim.color = Color(Palette.PAPER.r, Palette.PAPER.g, Palette.PAPER.b, 0.72)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(scrim)
	screen.move_child(scrim, 0)
	over_title = UiKit.heading("VICTORY", 86, Palette.BRASS)
	over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_detail = UiKit.body("", 28)
	over_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	var again := UiKit.button("SAIL AGAIN", true)
	again.pressed.connect(func(): _begin(Game.mode))
	var menu := UiKit.button("BACK TO PORT", true)
	menu.pressed.connect(_to_port)
	row.add_child(again)
	row.add_child(menu)
	screen.add_child(over_title)
	screen.add_child(over_detail)
	screen.add_child(UiKit.spacer(30))
	screen.add_child(row)

func _on_match_over(winner: int) -> void:
	await get_tree().create_timer(0.3).timeout
	if cutscene_layer.visible:
		await cutscene.finished
	if Game.mode == Game.Mode.VS_AI:
		over_title.text = "VICTORY" if winner == Game.HUMAN else "YOUR FLEET IS GONE"
	else:
		over_title.text = "%s WINS" % PLAYER_NAMES[winner]
	over_detail.text = "%d shots, %d of them hits - %.0f%% accuracy." % [
		Game.shots_fired[winner], Game.hits_landed[winner], Game.accuracy(winner) * 100.0]
	_show("over")
