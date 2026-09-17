extends Node

## Every screen the player passes through, photographed in order.
##
## The menu gets photographed first and deliberately: it is the one screen
## everybody sees, and it is the easiest to leave broken while polishing the
## parts that are more fun to work on.

const SHOTS := "res://dev/shots/"

var _game: Control

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await get_tree().process_frame
	_game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_game)
	await get_tree().process_frame
	await _save("ui_menu")

	# Against the computer: lay a fleet out by hand, then scatter the rest.
	_game._begin(Game.Mode.VS_AI)
	await get_tree().process_frame
	await _save("ui_placement_empty")

	_game._on_place_hovered(Vector2i(2, 3))
	await get_tree().process_frame
	await _save("ui_placement_preview")

	_game._random_placement()
	await get_tree().process_frame
	await _save("ui_placement_full")

	_game._finish_placement()
	await get_tree().process_frame
	await _save("ui_battle_fresh")

	# Shoot at everything until a few shots have landed, so the charts have
	# misses, hits and at least one ship sunk on them.
	var enemy: Board = Game.boards[Game.OPPONENT]
	var shots := 0
	for cell in _cells_of_first_ship(enemy):
		Game.fire_at(cell)
		shots += 1
	for y in range(0, 10, 3):
		for x in range(0, 10, 4):
			Game.fire_at(Vector2i(x, y))
	_game._refresh_battle()
	_game._grid_own.queue_redraw()
	_game._grid_enemy.queue_redraw()
	await get_tree().process_frame
	await _save("ui_battle_played")

	# The cutscene as it actually appears in play, banner and all, rather than
	# on its own in the look scene.
	var target: Board = Game.boards[Game.OPPONENT]
	var victim: Ship = target.ships[1]
	_game._play_cutscene({
		"valid": true, "outcome": "hit", "cell": victim.cells()[1],
		"ship_kind": victim.kind, "ship_name": victim.display_name(),
		"segment": 1, "length": victim.length(), "hits": 1,
		"horizontal": victim.horizontal,
	})
	await get_tree().create_timer(1.25).timeout
	await _save("ui_cutscene_overlay")
	_game._cutscene.skip()
	await get_tree().process_frame

	# And the handover screen the two-player game leans on.
	_game._go_to_handover("PASS THE DEVICE", "Player 2 takes the next shot.", func(): pass)
	await get_tree().process_frame
	await _save("ui_handover")

	print("screen photos written")
	get_tree().quit()

func _cells_of_first_ship(board: Board) -> Array[Vector2i]:
	for ship in board.ships:
		if ship.length() == 3:
			return ship.cells()
	return board.ships[0].cells()

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(SHOTS + name + ".png"))
