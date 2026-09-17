class_name BridgeHud
extends Control

## What the player is told while they are on the bridge.
##
## Deliberately thin. The game's whole argument is that you are standing
## somewhere real, and a screen full of panels undoes that. So: a reticle, a
## bearing ribbon, a range, and one line saying what the key under your finger
## does. Everything else the player needs is a thing on the ship - the plot on
## the table, your own fall of shot on the water, the enemy burning.
##
## The bearing ribbon is the piece that matters. The plotting table gives a
## square; the square gives a bearing; the ribbon is how the player gets the
## guns onto that bearing, which is exactly the job a director sight did.

const RIBBON_SPAN := 40.0   ## degrees of bearing shown across the ribbon

var mode: int = 0
var on_target := false
var marked := Vector2i(-1, -1)
var range_metres := 0.0
var aim_bearing := 0.0       ## where the guns point, relative to the ship's head
var target_bearing := 0.0    ## where the marked square lies, same reference
var target_screen := Vector2.ZERO
var target_visible := false
var message := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit()
	get_viewport().size_changed.connect(_fit)

## A Control whose parent is a CanvasLayer has no anchors to obey, so it keeps
## a size of zero forever unless it is told otherwise - and every measurement
## taken from that size lands in the top-left corner of the screen.
func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size

func _draw() -> void:
	_fit()
	var font := get_theme_default_font()
	if mode == 2:  # Bridge.Mode.SIGHT
		_draw_reticle(size * 0.5)
		_draw_designator(font)
		_draw_ribbon(font)
		_draw_readout(font)
	_draw_hint(font)
	if message != "":
		var width := size.x * 0.7
		var left := (size.x - width) * 0.5
		# High, clear of the plotting table. At a fifth of the way down it sat
		# across the column numbers along the top of the board.
		var top := size.y * 0.075
		draw_rect(Rect2(left, top - 34.0, width, 52.0), Color(0, 0, 0, 0.38))
		draw_string(font, Vector2(left, top), message,
			HORIZONTAL_ALIGNMENT_CENTER, width, 34, Palette.INK)

func _draw_reticle(middle: Vector2) -> void:
	var colour: Color = Palette.GOOD if on_target else Palette.INK_DIM
	var reach: float = size.y * 0.17
	var gap: float = size.y * 0.024
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(middle + direction * gap, middle + direction * reach, colour, 1.5)
	draw_arc(middle, gap * 0.6, 0.0, TAU, 32, colour, 1.5)

	# The elevation ladder a director sight carries. It does nothing
	# mechanically; without it the crosshair reads as a mouse cursor.
	for i in range(1, 7):
		var y: float = middle.y + float(i) * size.y * 0.028
		var width: float = size.y * (0.015 if i % 2 == 0 else 0.008)
		draw_line(Vector2(middle.x - width, y), Vector2(middle.x + width, y),
			colour * Color(1, 1, 1, 0.55), 1.0)

## Where the marked square actually lies, drawn on the sea itself.
##
## Without this there is nothing in the world to aim at: the enemy is hull down
## in the haze and one patch of open water looks like the next. It is drawn as
## a fire-control designation - an open diamond with the square's name - rather
## than as a solid marker, because nobody on that bridge can see a ship there.
## They have been told where to shoot.
func _draw_designator(font: Font) -> void:
	if not target_visible or not Board.in_bounds(marked):
		return
	var reach := size.y * 0.020
	var colour: Color = Palette.GOOD if on_target else Palette.BRASS
	var points := PackedVector2Array([
		target_screen + Vector2(0, -reach), target_screen + Vector2(reach, 0),
		target_screen + Vector2(0, reach), target_screen + Vector2(-reach, 0),
		target_screen + Vector2(0, -reach),
	])
	draw_polyline(points, colour, 1.6)
	draw_string(font, target_screen + Vector2(reach * 1.6, reach * 0.5),
		_square_name(marked), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, colour)

## The bearing ribbon across the top: where the guns point, and where they are
## wanted. Turn until the two marks meet.
func _draw_ribbon(font: Font) -> void:
	var width := size.x * 0.62
	var left := (size.x - width) * 0.5
	var y := size.y * 0.085
	var per_degree := width / RIBBON_SPAN

	draw_line(Vector2(left, y), Vector2(left + width, y), Palette.INK_DIM * Color(1, 1, 1, 0.55), 1.0)

	# A tick every two degrees, numbered every ten, sliding under a fixed mark.
	var first := int(floor((aim_bearing - RIBBON_SPAN * 0.5) / 2.0)) * 2
	for step in range(0, int(RIBBON_SPAN / 2.0) + 2):
		var degrees := float(first + step * 2)
		var x := left + width * 0.5 + (degrees - aim_bearing) * per_degree
		if x < left or x > left + width:
			continue
		var major: bool = int(round(degrees)) % 10 == 0
		draw_line(Vector2(x, y), Vector2(x, y + (14.0 if major else 7.0)),
			Palette.INK_DIM, 1.0)
		if major:
			# Labelled the same way the readout calls it - red to port, green
			# to starboard - so the ribbon and the readout cannot disagree.
			var off := _shortest_angle(degrees)
			var label := "%s%02d" % ["G" if off >= 0.0 else "R", int(round(absf(off)))]
			draw_string(font, Vector2(x - 26.0, y + 34.0), label,
				HORIZONTAL_ALIGNMENT_CENTER, 52.0, 17,
				Palette.GOOD if off >= 0.0 else Palette.HIT)

	# Where the guns are: a fixed caret at the middle of the ribbon.
	var middle_x := left + width * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(middle_x, y - 3.0), Vector2(middle_x - 8.0, y - 17.0), Vector2(middle_x + 8.0, y - 17.0),
	]), Palette.GOOD if on_target else Palette.INK)

	# Where they are wanted.
	if Board.in_bounds(marked):
		var offset := _shortest_angle(target_bearing - aim_bearing)
		var x := clampf(middle_x + offset * per_degree, left, left + width)
		var off_scale: bool = absf(offset) > RIBBON_SPAN * 0.5
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, y + 3.0), Vector2(x - 7.0, y + 17.0), Vector2(x + 7.0, y + 17.0),
		]), Palette.INK_DIM if off_scale else Palette.BRASS)
		if off_scale:
			# Which way to turn, when the target is off the end of the ribbon.
			var arrow := 1.0 if offset > 0.0 else -1.0
			draw_string(font, Vector2(middle_x + arrow * width * 0.42 - 20.0, y + 46.0),
				">>" if arrow > 0.0 else "<<", HORIZONTAL_ALIGNMENT_CENTER, 40.0, 22, Palette.BRASS)

func _draw_readout(font: Font) -> void:
	var lines := [
		"BRG  %s" % _relative_bearing(aim_bearing),
		"RNG  %5d" % int(round(range_metres)),
		"SQR  %s" % (_square_name(marked) if Board.in_bounds(marked) else "--"),
	]
	var y := size.y * 0.70
	for line in lines:
		draw_string(font, Vector2(size.x * 0.06, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Palette.INK)
		y += 34.0
	var verdict: String = "ON TARGET - FIRE" if on_target else "LAY THE GUNS"
	draw_string(font, Vector2(size.x * 0.06, y + 14.0), verdict,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Palette.GOOD if on_target else Palette.BRASS)

## Bearings on a bridge are called red or green so many degrees off the bow,
## not as a compass course the player has no way of knowing.
func _relative_bearing(degrees: float) -> String:
	var off := _shortest_angle(degrees)
	var side := "GREEN" if off >= 0.0 else "RED"
	return "%s %03d" % [side, int(round(absf(off)))]

func _shortest_angle(degrees: float) -> float:
	return fposmod(degrees + 180.0, 360.0) - 180.0

## What to do next, always on screen and always legible.
##
## It used to be small grey text over whatever the sky was doing, which is no
## use to somebody who has just picked the game up and does not know that the
## plotting table exists at all.
func _draw_hint(font: Font) -> void:
	var text := ""
	match mode:
		0: text = "T  the plotting table          SPACE  the gun sight          ESC  pause"
		1: text = "click a square on the plot          T  back to the windows          ESC  pause"
		2: text = "turn until the two marks meet, then SPACE to fire          BACKSPACE  back          ESC  pause"
	var height := 44.0
	draw_rect(Rect2(0.0, size.y - height, size.x, height), Color(0, 0, 0, 0.42))
	draw_string(font, Vector2(0.0, size.y - 14.0), text,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Palette.INK)

func _square_name(cell: Vector2i) -> String:
	return "%s%d" % [GridView.LETTERS[cell.y], cell.x + 1]
