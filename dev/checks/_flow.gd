extends Node

## Can a whole match be played from the menu to the last ship, and does the
## screen ever show something the player is not entitled to see?
##
## The rules check proves the fleet and the gunner are right. This one drives
## the actual screens, because the bugs that survive a correct rule set are the
## ones where the right answer is put in the wrong place - most of all, the
## computer's fleet appearing face up on the player's own chart the moment it
## takes a turn.

var failures := 0
var _game: Control

func _ready() -> void:
	_game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_game)
	await get_tree().process_frame

	await _computer_game()
	await _two_player_handover()

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

func _computer_game() -> void:
	print("a game against the computer")
	_game._begin(Game.Mode.VS_AI)
	_game._random_placement()
	_game._finish_placement()
	await get_tree().process_frame

	_check("the battle screen is up", _game._screens["battle"].visible)
	_check("your own chart shows your own fleet",
		_game._grid_own.board == Game.boards[Game.HUMAN])
	_check("the chart you fire at hides its ships", not _game._grid_enemy.reveal_ships)

	# Hand the turn to the computer and look again. This is the moment the
	# viewpoint used to follow the wrong player.
	Game.end_turn()
	_game._refresh_battle()
	await get_tree().process_frame
	_check("the computer's turn does not reveal its fleet",
		_game._grid_own.board == Game.boards[Game.HUMAN],
		"left chart was %s" % ("the computer's" if _game._grid_own.board == Game.boards[Game.OPPONENT] else "yours"))
	_check("you cannot fire while the computer is aiming", not _game._is_players_turn())

	Game.end_turn()
	_game._refresh_battle()
	_check("the turn comes back to you", _game._is_players_turn())

	# Play the match out through the rules, the way the screen would.
	var shots := 0
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

func _two_player_handover() -> void:
	print("two players, one device")
	_game._begin(Game.Mode.PASS_AND_PLAY)
	_game._random_placement()
	_game._finish_placement()
	await get_tree().process_frame
	_check("player one is asked to pass the device before player two lays out",
		_game._screens["handover"].visible)

	_game._leave_handover()
	await get_tree().process_frame
	_check("player two then gets a placement screen", _game._screens["placement"].visible)
	_check("player two lays out their own board",
		_game._grid_place.board == Game.boards[Game.OPPONENT])

	_game._random_placement()
	_game._finish_placement()
	await get_tree().process_frame
	_check("the battle starts after both fleets are out", _game._screens["battle"].visible)
	_check("player one sees player one's fleet", _game._grid_own.board == Game.boards[0])

	# After a turn ends the device changes hands, and the view must follow.
	Game.end_turn()
	_game._refresh_battle()
	_check("after the handover the view follows the device",
		_game._grid_own.board == Game.boards[1])

func _first_unshot(board: Board) -> Vector2i:
	for y in Board.SIZE:
		for x in Board.SIZE:
			var cell := Vector2i(x, y)
			if not board.already_shot(cell):
				return cell
	return Vector2i(-1, -1)
