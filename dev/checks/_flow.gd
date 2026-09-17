extends Node

## Can a whole match be played from the menu to the last ship, and does the
## bridge ever show something the player is not entitled to see?
##
## The rules check proves the fleet and the gunner are right. This one drives
## the real thing, because the bugs that survive a correct rule set are the
## ones where the right answer is put in the wrong place - above all, the
## enemy's fleet appearing on the plotting table.

var failures := 0
var game: Node

func _ready() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(0.4).timeout

	await _opening()
	await _laying_out()
	await _battle()
	await _two_players()

	# Give the pointer back to whoever is running this.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	print("")
	if failures == 0:
		print("FLOW: all checks passed")
	else:
		print("FLOW: %d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok    %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL  %s %s" % [label, detail])

func _opening() -> void:
	print("the first thing anybody sees")
	_check("the menu is up", game.screens["menu"].visible)
	_check("the bridge is already there behind it", game.bridge != null and game.bridge.flagship != null)
	_check("the mouse is not captured on a menu", not game.bridge.capture_mouse)
	_check("the fleet has its escorts", game.bridge.escorts.get_child_count() == 4,
		"%d escorts" % game.bridge.escorts.get_child_count())

func _laying_out() -> void:
	print("laying out your own fleet")
	game._begin(Game.Mode.VS_AI)
	await get_tree().process_frame
	_check("the placement bar is up", game.screens["placement"].visible)
	_check("the player is at the plotting table", game.bridge.mode == 1)
	_check("the table carries your own water", game.bridge.table.chart.board == Game.boards[Game.HUMAN])
	_check("your own ships are shown while you lay them", game.bridge.table.chart.reveal_ships)
	_check("you cannot put to sea with no fleet", game.ready_button.disabled)

	# One ship by hand, to prove a click on the table places it.
	var before: int = Game.boards[Game.HUMAN].ships.size()
	game.bridge._place_ship(Vector2i(1, 1))
	_check("a click lays a ship down", Game.boards[Game.HUMAN].ships.size() == before + 1)

	# Nothing may cover the world and eat the clicks meant for the table.
	var swallowing := []
	for name in game.screens:
		if game.screens[name].mouse_filter != Control.MOUSE_FILTER_IGNORE:
			swallowing.append(name)
	_check("no full-screen panel swallows clicks meant for the plot",
		swallowing.is_empty(), "%s would" % str(swallowing))

	# A ship has to be layable up and down as well as across.
	var was: bool = game.bridge.placing_horizontal
	game.bridge.turn_ship()
	_check("turning her changes how she lies", game.bridge.placing_horizontal != was)
	game.bridge._preview(Vector2i(4, 4))
	var ghost: Array = game.bridge.table.chart.preview_cells
	var down: bool = ghost.size() > 1 and ghost[0].x == ghost[1].x
	_check("turned, she lies up and down the plot", down,
		"ghost ran %s" % ("down" if down else "across"))
	var placed_vertically: bool = game.bridge.own_board.place(
		game.bridge.placing_kind(), Vector2i(8, 2), false)
	_check("she can be laid up and down", placed_vertically)
	game.bridge.turn_ship()

	game.bridge.scatter_fleet(Game.rng)
	game._update_place_hint()
	_check("scattering fills the fleet", game.bridge.fleet_is_laid_out())
	_check("now you can put to sea", not game.ready_button.disabled)

func _battle() -> void:
	print("the battle")
	game._finish_placement()
	await get_tree().process_frame
	_check("no screen stands in front of the bridge", not game.screens["placement"].visible)
	# Without this the player cannot turn the guns at all: the pointer hits the
	# edge of the screen and the sight stops.
	_check("the bridge has the mouse once the battle starts", game.bridge.capture_mouse)
	_check("the pointer is actually captured",
		Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"mouse_mode was %d" % Input.mouse_mode)
	_check("the table has changed to the enemy's water",
		game.bridge.table.chart.board == Game.boards[Game.OPPONENT])
	# The one that matters: the plot must not draw the enemy's hulls.
	_check("the enemy's ships are not drawn on the plot",
		not game.bridge.table.chart.reveal_ships,
		"the plot would have shown their whole fleet")
	_check("placing is over", not game.bridge.placing)

	var first := _first_unshot(Game.boards[Game.OPPONENT])
	game.bridge.marked = first
	game._on_shot_requested(first)
	await get_tree().process_frame
	_check("a called square is fired at", Game.boards[Game.OPPONENT].already_shot(first))

	# Play the rest out through the rules, the way the bridge would.
	var shots := 1
	while Game.phase != Game.Phase.OVER and shots < 400:
		var board: Board = Game.boards[1 - Game.current_player]
		var cell := _first_unshot(board)
		if cell.x < 0:
			break
		Game.fire_at(cell)
		shots += 1
		if Game.phase != Game.Phase.OVER:
			Game.end_turn()
	_check("a match reaches an ending", Game.phase == Game.Phase.OVER, "after %d shots" % shots)

func _two_players() -> void:
	print("two players, one device")
	game._begin(Game.Mode.PASS_AND_PLAY)
	await get_tree().process_frame
	game.bridge.scatter_fleet(Game.rng)
	game._update_place_hint()
	game._finish_placement()
	await get_tree().process_frame
	_check("player one is asked to pass the device", game.screens["handover"].visible)
	_check("the handover hides the bridge completely",
		game.screens["handover"].get_child(0) is ColorRect
			and game.screens["handover"].get_child(0).color.a >= 0.99,
		"otherwise the other player's fleet is visible behind it")

	game._leave_handover()
	await get_tree().process_frame
	_check("player two then lays out", game.bridge.placing)
	_check("player two lays out their own board",
		game.bridge.table.chart.board == Game.boards[Game.OPPONENT])

func _first_unshot(board: Board) -> Vector2i:
	for y in Board.SIZE:
		for x in Board.SIZE:
			var cell := Vector2i(x, y)
			if not board.already_shot(cell):
				return cell
	return Vector2i(-1, -1)
