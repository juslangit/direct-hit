class_name GridView
extends Control

## One 10x10 chart: the water, the ruled lines, the letters down the side and
## whatever has been found in it so far.
##
## It draws and it reports clicks. It does not decide anything - it is handed a
## Board to read and tells whoever is listening which square was pressed.

signal cell_pressed(cell: Vector2i)
signal cell_hovered(cell: Vector2i)

const LETTERS: Array[String] = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"]

## Show the ships sitting in the water, or only what has been shot at.
@export var reveal_ships := false
@export var interactive := true

var board: Board = null
var hovered := Vector2i(-1, -1)
var preview_cells: Array[Vector2i] = []
var preview_legal := true
var last_shot := Vector2i(-1, -1)

var _margin := 34.0
var _paper: Texture2D = load("res://assets/ui/chart_paper.jpg")
var _cell := 48.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)

func set_board(p_board: Board) -> void:
	board = p_board
	queue_redraw()

## The chart is always square and always fits, with room down the left and
## along the top for the letters and numbers.
func _layout() -> void:
	var usable: float = min(size.x, size.y) - _margin
	_cell = floor(usable / float(Board.SIZE))

func chart_size() -> float:
	_layout()
	return _cell * float(Board.SIZE) + _margin

func _origin() -> Vector2:
	return Vector2(_margin, _margin)

func cell_rect(cell: Vector2i) -> Rect2:
	var o := _origin()
	return Rect2(o + Vector2(cell) * _cell, Vector2(_cell, _cell))

func cell_at(point: Vector2) -> Vector2i:
	var o := _origin()
	if point.x < o.x or point.y < o.y:
		return Vector2i(-1, -1)
	var cell := Vector2i((point - o) / _cell)
	return cell if Board.in_bounds(cell) else Vector2i(-1, -1)

func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseMotion:
		var cell := cell_at(event.position)
		if cell != hovered:
			hovered = cell
			cell_hovered.emit(cell)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := cell_at(event.position)
		if Board.in_bounds(cell):
			cell_pressed.emit(cell)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hovered = Vector2i(-1, -1)
		queue_redraw()

func _draw() -> void:
	_layout()
	var o := _origin()
	var span := _cell * float(Board.SIZE)

	# The chart itself: aged paper, with the whole sheet showing under the
	# margins so the letters and numbers sit on it rather than beside it.
	var sheet := Rect2(o - Vector2(_margin, _margin), Vector2(span + _margin * 1.4, span + _margin * 1.4))
	if _paper != null:
		draw_texture_rect(_paper, sheet, false)
	else:
		draw_rect(sheet, Palette.PAPER_SHEET)
	# A pencil box round the plotted water.
	draw_rect(Rect2(o, Vector2(span, span)), Palette.PAPER_SHEET * Color(1, 1, 1, 0.25))

	_draw_labels(o, span)
	_draw_ships()
	_draw_rules(o, span)
	_draw_shots()
	_draw_preview()
	_draw_hover()

func _draw_labels(o: Vector2, span: float) -> void:
	var font := get_theme_default_font()
	var size_px := int(clamp(_cell * 0.42, 12.0, 26.0))
	for i in Board.SIZE:
		var letter: String = LETTERS[i]
		var number := str(i + 1)
		# Letters run down the left, numbers along the top - the way a chart
		# is read aloud: "B7".
		var letter_pos := Vector2(o.x - _margin + 6.0, o.y + i * _cell + _cell * 0.5 + size_px * 0.36)
		draw_string(font, letter_pos, letter, HORIZONTAL_ALIGNMENT_LEFT, _margin - 10.0, size_px, Palette.PAPER_INK)
		var number_pos := Vector2(o.x + i * _cell, o.y - 9.0)
		draw_string(font, number_pos, number, HORIZONTAL_ALIGNMENT_CENTER, _cell, size_px, Palette.PAPER_INK)

func _draw_rules(o: Vector2, span: float) -> void:
	for i in range(Board.SIZE + 1):
		var at: float = o.x + i * _cell
		var down: float = o.y + i * _cell
		var heavy: bool = i == 0 or i == Board.SIZE
		var colour: Color = Palette.PAPER_RULE if heavy else Palette.PAPER_RULE_FAINT
		var width: float = 2.0 if heavy else 1.0
		draw_line(Vector2(at, o.y), Vector2(at, o.y + span), colour, width)
		draw_line(Vector2(o.x, down), Vector2(o.x + span, down), colour, width)

func _draw_ships() -> void:
	if board == null or not reveal_ships:
		return
	for ship in board.ships:
		var cells := ship.cells()
		var first := cell_rect(cells[0])
		var last := cell_rect(cells[-1])
		var hull := first.merge(last).grow(-_cell * 0.16)
		var sunk := ship.is_sunk()
		draw_rect(hull, (Palette.SUNK if sunk else Palette.PAPER_PENCIL) * Color(1, 1, 1, 0.30), true)
		draw_rect(hull, Palette.SUNK if sunk else Palette.PAPER_PENCIL, false, 2.0)
		# A line down the spine, so a five-square carrier reads as one vessel
		# rather than five boxes.
		var spine_from := hull.position + (Vector2(0, hull.size.y * 0.5) if ship.horizontal else Vector2(hull.size.x * 0.5, 0))
		var spine_to := spine_from + (Vector2(hull.size.x, 0) if ship.horizontal else Vector2(0, hull.size.y))
		draw_line(spine_from, spine_to, Palette.PAPER_PENCIL, 1.0)

func _draw_shots() -> void:
	if board == null:
		return
	var font := get_theme_default_font()
	for cell in board.shots:
		var result: int = board.shots[cell]
		var rect := cell_rect(cell)
		var middle := rect.get_center()
		if result == Board.Shot.MISS:
			# A miss is a small flat disc: the splash, and nothing else.
			# A miss is pencilled, not lit: an open ring the way a plot is marked.
			draw_arc(middle, _cell * 0.20, 0.0, TAU, 28, Palette.PAPER_INK_SOFT, 2.0)
			draw_circle(middle, _cell * 0.05, Palette.PAPER_INK_SOFT)
		elif result == Board.Shot.HIT:
			var ship := board.ship_at(cell)
			var finished: bool = ship != null and ship.is_sunk()
			draw_rect(rect.grow(-2.0), (Palette.SUNK if finished else Palette.HIT) * Color(1, 1, 1, 0.35))
			_draw_burst(middle, _cell * 0.30, Palette.HIT_GLOW if not finished else Palette.HIT)
	if Board.in_bounds(last_shot):
		draw_rect(cell_rect(last_shot).grow(-1.0), Palette.BRASS, false, 2.5)

## An eight-pointed star, drawn rather than stamped, so it scales with the
## chart and never turns into a blurry sprite.
func _draw_burst(middle: Vector2, radius: float, colour: Color) -> void:
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var reach := radius if i % 2 == 0 else radius * 0.55
		draw_line(middle, middle + Vector2(cos(angle), sin(angle)) * reach, colour, 2.0)
	draw_circle(middle, radius * 0.28, colour)

func _draw_preview() -> void:
	if preview_cells.is_empty():
		return
	var colour: Color = (Palette.GOOD if preview_legal else Palette.HIT) * Color(1, 1, 1, 0.45)
	for cell in preview_cells:
		if Board.in_bounds(cell):
			draw_rect(cell_rect(cell).grow(-3.0), colour)

func _draw_hover() -> void:
	if not interactive or not Board.in_bounds(hovered) or not preview_cells.is_empty():
		return
	var rect := cell_rect(hovered)
	draw_rect(rect.grow(-2.0), Palette.BRASS * Color(1, 1, 1, 0.22))
	draw_rect(rect.grow(-2.0), Palette.BRASS, false, 2.0)
	# Cross-hairs out to the edges of the chart, the way a range is plotted.
	var o := _origin()
	var span := _cell * float(Board.SIZE)
	var faint := Palette.BRASS * Color(1, 1, 1, 0.42)
	draw_line(Vector2(rect.get_center().x, o.y), Vector2(rect.get_center().x, o.y + span), faint, 1.0)
	draw_line(Vector2(o.x, rect.get_center().y), Vector2(o.x + span, rect.get_center().y), faint, 1.0)
