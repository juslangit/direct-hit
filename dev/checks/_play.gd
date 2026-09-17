extends Node

## Can the game be played with a keyboard and a mouse?
##
## Every other check in this folder drives the game by calling its methods, and
## every one of them passed while the game could not be played at all. They test
## whether the machine is right. This one tests whether a person can reach it:
## it synthesises real input events and pushes them through the whole input
## system - focus, GUI hit-testing, mouse filters and all - exactly as a
## keyboard and mouse would.
##
## It also measures the frame rate, because a game that runs at eight frames a
## second is unplayable no matter how correct it is.

var failures := 0
var game: Node
var notes: Array = []

func _ready() -> void:
	# The size the game actually launches at, not a small test window. A frame
	# rate measured at 1280x720 says nothing about a maximised window on a
	# retina screen, which is what the player is looking at.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	# The window takes a frame or two to actually become that size, and the
	# canvas-to-window scale is read from it. Clicking before it settles sends
	# the pointer somewhere else entirely, which made this check fail at random.
	await get_tree().process_frame
	await get_tree().process_frame
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(0.8)

	await _frame_rate("with the menu up")
	await _menu()
	await _placement()
	await _battle()

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("")
	for note in notes:
		print("  note  %s" % note)
	if failures == 0:
		print("PLAY: all checks passed")
	else:
		print("PLAY: %d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok    %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL  %s %s" % [label, detail])

func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

## Canvas coordinates to window coordinates.
##
## The project stretches a 1920x1080 canvas to fill whatever window it is given,
## so a Control's rect and the position on an injected mouse event are in two
## different spaces. Clicks synthesised in canvas coordinates land somewhere
## else entirely, which looks exactly like a button that does not work.
func _to_window(canvas_point: Vector2) -> Vector2:
	var view := get_viewport().get_visible_rect().size
	var window := Vector2(DisplayServer.window_get_size())
	if view.x <= 0.0 or view.y <= 0.0:
		return canvas_point
	return canvas_point * (window / view)

## Push an event through the real input system, not into a method.
func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame

func _press_key(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	await _send(down)
	var up := InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	await _send(up)

func _click_at(canvas_point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var where := _to_window(canvas_point)
	var move := InputEventMouseMotion.new()
	move.position = where
	move.global_position = where
	await _send(move)
	var down := InputEventMouseButton.new()
	down.button_index = button
	down.position = where
	down.global_position = where
	down.pressed = true
	await _send(down)
	var up := InputEventMouseButton.new()
	up.button_index = button
	up.position = where
	up.global_position = where
	up.pressed = false
	await _send(up)

func _click_button(button: Button) -> void:
	await _click_at(button.get_global_rect().get_center())

func _find_button(text: String) -> Button:
	var stack: Array = [game]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Button and node.text.begins_with(text) and node.is_visible_in_tree():
			return node
		for child in node.get_children():
			stack.append(child)
	return null

func _frame_rate(when: String) -> void:
	await _settle(1.2)
	var fps := Engine.get_frames_per_second()
	notes.append("frame rate %s: %d fps at %s" % [when, fps, str(DisplayServer.window_get_size())])
	_check("playable frame rate %s" % when, fps >= 24, "%d fps" % fps)

# --------------------------------------------------------------------------

func _menu() -> void:
	print("reaching the game from the menu")
	var play := _find_button("PLAY THE COMPUTER")
	_check("the menu button is there and visible", play != null)
	if play == null:
		return
	await _click_button(play)
	await _settle(0.6)
	_check("clicking it starts a match", game.screens["placement"].visible)

func _placement() -> void:
	print("laying the fleet out with the mouse")
	_check("the pointer is free to use the table",
		Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse_mode %d" % Input.mouse_mode)

	# A click on the middle of the screen should land on the plot, because the
	# plot is what fills the middle of the screen in this mode.
	var middle := get_viewport().get_visible_rect().size * 0.5
	if Game.boards.is_empty():
		_check("a match actually started", false, "no boards exist, so nothing below can work")
		return
	var before: int = Game.boards[Game.HUMAN].ships.size()
	await _click_at(middle)
	_check("a click on the plot lays a ship", Game.boards[Game.HUMAN].ships.size() > before,
		"%d ships on the board" % Game.boards[Game.HUMAN].ships.size())

	var was: bool = game.bridge.placing_horizontal
	await _press_key(KEY_R)
	_check("R turns her", game.bridge.placing_horizontal != was)

	var scatter := _find_button("SCATTER")
	if scatter != null:
		await _click_button(scatter)
	_check("scatter fills the fleet", game.bridge.fleet_is_laid_out())

	var ready_button := _find_button("PUT TO SEA")
	_check("put to sea is offered", ready_button != null and not ready_button.disabled)
	if ready_button != null:
		await _click_button(ready_button)
	await _settle(0.8)
	_check("the battle starts", not game.screens["placement"].visible)

func _battle() -> void:
	print("fighting with the keyboard")
	_check("the pointer is captured so the guns can be turned",
		Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "mouse_mode %d" % Input.mouse_mode)

	var focus := get_viewport().gui_get_focus_owner()
	_check("no leftover button is holding the keyboard", focus == null,
		"%s has focus and will eat SPACE" % (focus.name if focus != null else ""))

	await _press_key(KEY_T)
	await _settle(0.8)
	_check("T opens the plotting table", game.bridge.mode == 1, "mode %d" % game.bridge.mode)
	_check("the table frees the pointer",
		Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse_mode %d" % Input.mouse_mode)

	# Call a square by clicking the plot.
	var middle := get_viewport().get_visible_rect().size * 0.5
	await _click_at(middle)
	_check("clicking the plot calls a square", Board.in_bounds(game.bridge.marked),
		"marked %s" % str(game.bridge.marked))

	# Click squares away from the middle. Clicking the centre of the plot
	# returns the centre square whatever the picking maths is doing, so a check
	# that only ever clicks the middle proves nothing at all.
	var wrong := []
	for cell in [Vector2i(1, 1), Vector2i(8, 2), Vector2i(2, 7), Vector2i(7, 8)]:
		var world: Vector3 = game.bridge.table.cell_world_position(cell)
		if game.bridge.camera.is_position_behind(world):
			continue
		await _click_at(game.bridge.camera.unproject_position(world))
		if game.bridge.marked != cell:
			wrong.append("%s gave %s" % [str(cell), str(game.bridge.marked)])
	_check("a click lands on the square you clicked", wrong.is_empty(), str(wrong))

	await _press_key(KEY_SPACE)
	await _settle(0.8)
	_check("SPACE takes you to the gun sight", game.bridge.mode == 2, "mode %d" % game.bridge.mode)

	# Lay the guns by hand, the way the player would, then fire.
	if Board.in_bounds(game.bridge.marked):
		var aim: Vector3 = game.bridge.fleet.to_global(game.bridge.cell_centre(game.bridge.marked))
		game.bridge._move_head(game.bridge.bridge_position(),
			game.bridge.flagship.to_local(aim), 8.5)
		await _settle(0.4)
	_check("laying the guns on the square arms them", game.bridge.can_fire,
		"error %.2f degrees" % game.bridge.lay_error())

	var shots_before: int = Game.shots_fired[Game.HUMAN]
	await _press_key(KEY_SPACE)
	await _settle(0.5)
	_check("SPACE fires", Game.shots_fired[Game.HUMAN] > shots_before,
		"%d shots fired" % Game.shots_fired[Game.HUMAN])

	await _frame_rate("in the battle")
