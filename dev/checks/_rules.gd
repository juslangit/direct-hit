extends Node

## Does a shot do what it says it does?
##
## Everything else in this game - the board, the camera, the explosion - is
## decoration on top of one dictionary returned by Board.fire(). If that
## dictionary lies about which ship was hit or where along its hull, the
## cutscene blows up the wrong part of the wrong boat and nobody can tell
## whether the bug is in the rules or in the art. So the rules get checked
## on their own, with nothing drawn.

var failures := 0

func _ready() -> void:
	_placement()
	_shots()
	_sinking()
	_ai_finishes()
	_ai_never_repeats()
	print("")
	if failures == 0:
		print("RULES: all checks passed")
	else:
		print("RULES: %d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok    %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL  %s %s" % [label, detail])

func _placement() -> void:
	print("placement")
	var board := Board.new()
	_check("first ship lands", board.place(Ship.Kind.CARRIER, Vector2i(0, 0), true))
	_check("overlap refused", not board.place(Ship.Kind.DESTROYER, Vector2i(2, 0), false))
	_check("off the east edge refused", not board.place(Ship.Kind.CRUISER, Vector2i(8, 5), true))
	_check("off the south edge refused", not board.place(Ship.Kind.CRUISER, Vector2i(5, 8), false))
	_check("legal neighbour allowed", board.place(Ship.Kind.DESTROYER, Vector2i(0, 1), true))

	for seed_value in range(1, 200):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var b := Board.new()
		b.random_layout(rng)
		var squares := {}
		var total := 0
		for ship in b.ships:
			for cell in ship.cells():
				if squares.has(cell) or not Board.in_bounds(cell):
					failures += 1
					print("  FAIL  random layout seed %d put %s on %s" % [seed_value, ship.display_name(), cell])
					return
				squares[cell] = true
				total += 1
		if total != 17:
			failures += 1
			print("  FAIL  seed %d laid %d squares of hull, expected 17" % [seed_value, total])
			return
	_check("200 random layouts legal, 17 squares each", true)

func _shots() -> void:
	print("shots")
	var board := Board.new()
	board.place(Ship.Kind.BATTLESHIP, Vector2i(3, 4), true)   # (3,4)..(6,4)

	var miss := board.fire(Vector2i(0, 0))
	_check("empty water misses", miss["outcome"] == "miss")

	var bow := board.fire(Vector2i(3, 4))
	_check("bow reports a hit", bow["outcome"] == "hit")
	_check("bow is segment 0", bow.get("segment") == 0, "got %s" % bow.get("segment"))
	_check("hit names the ship", bow.get("ship_name") == "Battleship")
	_check("hit reports hull length", bow.get("length") == 4)

	var stern := board.fire(Vector2i(6, 4))
	_check("stern is segment 3", stern.get("segment") == 3, "got %s" % stern.get("segment"))

	var repeat := board.fire(Vector2i(6, 4))
	_check("same square refused twice", not repeat.get("valid"))
	var off := board.fire(Vector2i(10, 4))
	_check("off the board refused", not off.get("valid"))

func _sinking() -> void:
	print("sinking")
	var board := Board.new()
	board.place(Ship.Kind.DESTROYER, Vector2i(1, 1), false)   # (1,1),(1,2)
	var first := board.fire(Vector2i(1, 1))
	_check("first of two is only a hit", first["outcome"] == "hit")
	_check("fleet not sunk yet", not board.fleet_sunk())
	var second := board.fire(Vector2i(1, 2))
	_check("second of two sinks her", second["outcome"] == "sunk")
	_check("sunk still names the segment", second.get("segment") == 1)
	_check("fleet sunk", board.fleet_sunk())
	_check("nothing left afloat", board.ships_remaining() == 0)

func _ai_finishes() -> void:
	print("the computer gunner")
	# A crashed script prints an error and carries on, which once let this
	# whole section do nothing while the run still claimed to pass. So the
	# gunner has to prove it exists before anything is asked of it.
	var probe = AiGunner.new(1)
	if probe == null or not probe.has_method("choose_shot"):
		failures += 1
		print("  FAIL  the gunner would not even start")
		return
	var worst := 0
	var total := 0
	var games := 300
	for seed_value in range(1, games + 1):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var board := Board.new()
		board.random_layout(rng)
		var gunner := AiGunner.new(seed_value)
		var shots := 0
		while not board.fleet_sunk() and shots < 100:
			var cell := gunner.choose_shot()
			var result := board.fire(cell)
			gunner.learn(cell, result)
			shots += 1
		if not board.fleet_sunk():
			failures += 1
			print("  FAIL  seed %d never finished the fleet in 100 shots" % seed_value)
			return
		worst = max(worst, shots)
		total += shots
	var average := float(total) / float(games)
	_check("%d games all finished" % games, true, "worst %d shots" % worst)
	_check("average under 60 shots", average < 60.0, "average %.1f" % average)
	_check("average over 35 shots (not clairvoyant)", average > 35.0, "average %.1f" % average)

func _ai_never_repeats() -> void:
	print("the gunner's memory")
	for seed_value in range(1, 60):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var board := Board.new()
		board.random_layout(rng)
		var gunner := AiGunner.new(seed_value)
		var seen := {}
		while not board.fleet_sunk():
			var cell := gunner.choose_shot()
			if seen.has(cell):
				failures += 1
				print("  FAIL  seed %d shot %s twice" % [seed_value, cell])
				return
			seen[cell] = true
			gunner.learn(cell, board.fire(cell))
	_check("59 games, no square shot twice", true)
