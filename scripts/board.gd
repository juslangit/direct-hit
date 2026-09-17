class_name Board
extends RefCounted

## One player's 10x10 water. Holds the fleet, remembers every square that has
## been shot at, and reports what each shot did in enough detail for the
## cutscene to stage it.

const SIZE := 10
const FLEET: Array[Ship.Kind] = [
	Ship.Kind.CARRIER,
	Ship.Kind.BATTLESHIP,
	Ship.Kind.CRUISER,
	Ship.Kind.SUBMARINE,
	Ship.Kind.DESTROYER,
]

enum Shot { NONE, MISS, HIT }

var ships: Array[Ship] = []
var shots: Dictionary = {}   ## Vector2i -> Shot

static func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < SIZE and cell.y < SIZE

func occupied() -> Dictionary:
	var out := {}
	for ship in ships:
		for cell in ship.cells():
			out[cell] = ship
	return out

func ship_at(cell: Vector2i) -> Ship:
	for ship in ships:
		if ship.segment_at(cell) != -1:
			return ship
	return null

func can_place(kind: Ship.Kind, origin: Vector2i, horizontal: bool) -> bool:
	var probe := Ship.new(kind, origin, horizontal)
	var taken := occupied()
	for cell in probe.cells():
		if not in_bounds(cell):
			return false
		if taken.has(cell):
			return false
	return true

func place(kind: Ship.Kind, origin: Vector2i, horizontal: bool) -> bool:
	if not can_place(kind, origin, horizontal):
		return false
	ships.append(Ship.new(kind, origin, horizontal))
	return true

## Drop the whole fleet somewhere legal. Deterministic for a given seed so a
## failing game can be replayed exactly.
func random_layout(rng: RandomNumberGenerator) -> void:
	ships.clear()
	for kind in FLEET:
		var placed := false
		var guard := 0
		while not placed and guard < 1000:
			guard += 1
			var horizontal := rng.randi_range(0, 1) == 1
			var origin := Vector2i(rng.randi_range(0, SIZE - 1), rng.randi_range(0, SIZE - 1))
			placed = place(kind, origin, horizontal)
		assert(placed, "could not place %s" % Ship.SPECS[kind]["name"])

func already_shot(cell: Vector2i) -> bool:
	return shots.get(cell, Shot.NONE) != Shot.NONE

## The one message the rest of the game listens to. `outcome` is "miss",
## "hit" or "sunk"; the ship fields are filled in for the last two so the
## cutscene knows which hull to stage and where along it to put the hole.
func fire(cell: Vector2i) -> Dictionary:
	if not in_bounds(cell) or already_shot(cell):
		return {"valid": false, "outcome": "invalid", "cell": cell}

	var ship := ship_at(cell)
	if ship == null:
		shots[cell] = Shot.MISS
		return {"valid": true, "outcome": "miss", "cell": cell}

	shots[cell] = Shot.HIT
	var segment := ship.segment_at(cell)
	ship.damage[segment] = true
	return {
		"valid": true,
		"outcome": "sunk" if ship.is_sunk() else "hit",
		"cell": cell,
		"ship_kind": ship.kind,
		"ship_name": ship.display_name(),
		"segment": segment,
		"length": ship.length(),
		"hits": ship.hits_taken(),
		"horizontal": ship.horizontal,
	}

func fleet_sunk() -> bool:
	for ship in ships:
		if not ship.is_sunk():
			return false
	return not ships.is_empty()

func ships_remaining() -> int:
	var n := 0
	for ship in ships:
		if not ship.is_sunk():
			n += 1
	return n
