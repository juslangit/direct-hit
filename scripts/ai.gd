class_name AiGunner
extends RefCounted

## The computer opponent. It never peeks at the board — it only sees the
## results of its own shots, the same as you do. Two moods:
##
##   HUNT   - nothing wounded out there, so sweep the water in a checkerboard.
##            Every ship is at least 2 long, so skipping every other square
##            still cannot miss one, and it halves the shots wasted.
##   TARGET - something is wounded. Work outward from the hit, and once two
##            hits line up, stop poking around and follow that line.

enum Mood { HUNT, TARGET }

var rng := RandomNumberGenerator.new()
var tried: Dictionary = {}          ## Vector2i -> true
var wounded: Array[Vector2i] = []   ## hits on the ship currently being chased
var candidates: Array[Vector2i] = []

func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value

func mood() -> Mood:
	return Mood.TARGET if not wounded.is_empty() else Mood.HUNT

func choose_shot() -> Vector2i:
	_refresh_candidates()
	while not candidates.is_empty():
		var cell: Vector2i = candidates.pop_front()
		if not tried.has(cell) and Board.in_bounds(cell):
			return cell
	return _hunt_cell()

## Rebuild the follow-up list from what we know about the wounded ship.
func _refresh_candidates() -> void:
	if wounded.is_empty():
		candidates.clear()
		return
	if candidates.is_empty() and wounded.size() >= 1:
		_seed_candidates()

func _seed_candidates() -> void:
	candidates.clear()
	if wounded.size() >= 2:
		# Two or more hits in a row tell us the ship's heading. Extend both ends.
		var horizontal := wounded[0].y == wounded[1].y
		var sorted := wounded.duplicate()
		sorted.sort_custom(func(a, b): return (a.x < b.x) if horizontal else (a.y < b.y))
		var step := Vector2i(1, 0) if horizontal else Vector2i(0, 1)
		_offer(sorted[0] - step)
		_offer(sorted[-1] + step)
		if candidates.is_empty():
			# Both ends are walled off or already shot: the line was a dead end,
			# so fall back to poking around every hit we have.
			for hit in wounded:
				_offer_neighbours(hit)
	else:
		_offer_neighbours(wounded[0])

func _offer_neighbours(cell: Vector2i) -> void:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	dirs.shuffle()
	for d in dirs:
		_offer(cell + d)

func _offer(cell: Vector2i) -> void:
	if Board.in_bounds(cell) and not tried.has(cell) and not candidates.has(cell):
		candidates.append(cell)

func _hunt_cell() -> Vector2i:
	var parity_cells: Array[Vector2i] = []
	var any_cells: Array[Vector2i] = []
	for y in Board.SIZE:
		for x in Board.SIZE:
			var cell := Vector2i(x, y)
			if tried.has(cell):
				continue
			any_cells.append(cell)
			if (x + y) % 2 == 0:
				parity_cells.append(cell)
	var pool := parity_cells if not parity_cells.is_empty() else any_cells
	if pool.is_empty():
		return Vector2i(-1, -1)
	return pool[rng.randi_range(0, pool.size() - 1)]

## Tell the gunner what its shot did. This is the only information it gets.
func learn(cell: Vector2i, result: Dictionary) -> void:
	tried[cell] = true
	candidates.erase(cell)
	match result.get("outcome", "miss"):
		"hit":
			wounded.append(cell)
			_seed_candidates()
		"sunk":
			wounded.append(cell)
			_forget_sunk_ship(cell, result.get("length", 0))
		_:
			pass

## A ship went down. Work out which of our hits made up that hull - the
## straight run of hits through the killing blow - and forget only those.
## Any hit left over belongs to a second ship parked alongside the first,
## and dropping it would mean finding that ship all over again.
func _forget_sunk_ship(killing_cell: Vector2i, length: int) -> void:
	candidates.clear()
	for cell in _hull_through(killing_cell, length):
		wounded.erase(cell)
	if not wounded.is_empty():
		_seed_candidates()

func _hull_through(cell: Vector2i, length: int) -> Array[Vector2i]:
	var axes: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
	for step in axes:
		var run: Array[Vector2i] = [cell]
		var directions: Array[Vector2i] = [step, -step]
		for direction in directions:
			var probe: Vector2i = cell + direction
			while wounded.has(probe):
				run.append(probe)
				probe += direction
		if run.size() == length:
			return run
	return [cell]
