class_name Ship
extends RefCounted

## One vessel on the board. It knows which squares it covers and which of
## those squares have been holed, because the cutscene needs to blow up the
## right part of the right ship.

enum Kind { CARRIER, BATTLESHIP, CRUISER, SUBMARINE, DESTROYER }

const SPECS := {
	Kind.CARRIER:    {"name": "Carrier",    "length": 5},
	Kind.BATTLESHIP: {"name": "Battleship", "length": 4},
	Kind.CRUISER:    {"name": "Cruiser",    "length": 3},
	Kind.SUBMARINE:  {"name": "Submarine",  "length": 3},
	Kind.DESTROYER:  {"name": "Destroyer",  "length": 2},
}

var kind: Kind
var origin: Vector2i          ## bow square
var horizontal: bool
var damage: Array[bool] = []  ## one entry per segment, bow to stern

func _init(p_kind: Kind, p_origin: Vector2i, p_horizontal: bool) -> void:
	kind = p_kind
	origin = p_origin
	horizontal = p_horizontal
	damage.resize(length())
	damage.fill(false)

func display_name() -> String:
	return SPECS[kind]["name"]

func length() -> int:
	return SPECS[kind]["length"]

func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in length():
		out.append(origin + (Vector2i(i, 0) if horizontal else Vector2i(0, i)))
	return out

## Which segment of the hull sits on this square, or -1 if the ship isn't there.
func segment_at(cell: Vector2i) -> int:
	var i := cells().find(cell)
	return i

func is_sunk() -> bool:
	return not damage.has(false)

func hits_taken() -> int:
	return damage.count(true)
