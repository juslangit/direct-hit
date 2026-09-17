class_name FleetPanel
extends Control

## The fleet list beside each chart: five vessels, one row of pips each, one
## pip per square of hull. A pip goes orange as that square is holed, and the
## whole row goes red when the last one does.
##
## This is the only place the player can see how close a ship is to going down,
## which is what turns a second hit on the same vessel into a decision rather
## than a coincidence.

var board: Board = null
var hide_intact := false  ## on the enemy's list, only sunk ships are known

const ROW_HEIGHT := 40.0

func set_board(p_board: Board) -> void:
	board = p_board
	queue_redraw()

func _ready() -> void:
	custom_minimum_size = Vector2(250, ROW_HEIGHT * float(Board.FLEET.size()) + 10.0)

func _draw() -> void:
	if board == null:
		return
	var font := get_theme_default_font()
	var y := 4.0
	for ship in board.ships:
		var sunk := ship.is_sunk()
		var known := sunk or not hide_intact
		var colour: Color = Palette.SUNK if sunk else (Palette.INK if known else Palette.INK_DIM)
		draw_string(font, Vector2(2.0, y + 21.0), ship.display_name(),
			HORIZONTAL_ALIGNMENT_LEFT, 150.0, 19, colour)

		var pip := 13.0
		var gap := 5.0
		var x := 150.0
		for segment in ship.length():
			var rect := Rect2(Vector2(x, y + 8.0), Vector2(pip, pip))
			var holed: bool = ship.damage[segment]
			if sunk:
				draw_rect(rect, Palette.SUNK)
			elif holed and not hide_intact:
				draw_rect(rect, Palette.HIT)
			else:
				draw_rect(rect, Palette.PANEL_EDGE)
				draw_rect(rect, Palette.RULE, false, 1.0)
			x += pip + gap
		if sunk:
			draw_line(Vector2(2.0, y + 15.0), Vector2(x - gap, y + 15.0), Palette.HIT, 2.0)
		y += ROW_HEIGHT
