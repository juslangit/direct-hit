extends Node

## The referee. Holds both fleets, whose turn it is, and what the last shot
## did. Everything visual - the board, the cutscene - listens to this and
## never changes the rules itself.

signal shot_resolved(result: Dictionary, attacker: int)
signal turn_changed(player: int)
signal match_over(winner: int)
signal phase_changed(phase: int)

enum Mode { VS_AI, PASS_AND_PLAY }
enum Phase { MENU, PLACEMENT, PLAYING, CUTSCENE, HANDOVER, OVER }

const HUMAN := 0
const OPPONENT := 1

var mode: Mode = Mode.VS_AI
var phase: Phase = Phase.MENU
var current_player: int = HUMAN
var boards: Array[Board] = []
var gunner: AiGunner = null
var rng := RandomNumberGenerator.new()
var last_result: Dictionary = {}
var shots_fired: Array[int] = [0, 0]
var hits_landed: Array[int] = [0, 0]

func start_match(p_mode: Mode, seed_value: int = 0) -> void:
	mode = p_mode
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	boards = [Board.new(), Board.new()]
	shots_fired = [0, 0]
	hits_landed = [0, 0]
	last_result = {}
	current_player = HUMAN
	gunner = AiGunner.new(seed_value) if mode == Mode.VS_AI else null
	if mode == Mode.VS_AI:
		boards[OPPONENT].random_layout(rng)
	_set_phase(Phase.PLACEMENT)

func defending_board() -> Board:
	return boards[1 - current_player]

func attacking_board() -> Board:
	return boards[current_player]

## The only way a shot ever happens, whoever fires it.
func fire_at(cell: Vector2i) -> Dictionary:
	if phase != Phase.PLAYING:
		return {"valid": false, "outcome": "not_playing"}
	var result := defending_board().fire(cell)
	if not result.get("valid", false):
		return result

	var attacker := current_player
	shots_fired[attacker] += 1
	if result["outcome"] != "miss":
		hits_landed[attacker] += 1
	last_result = result
	if gunner != null and attacker == OPPONENT:
		gunner.learn(cell, result)

	shot_resolved.emit(result, attacker)

	if defending_board().fleet_sunk():
		_set_phase(Phase.OVER)
		match_over.emit(attacker)
	return result

## Called by the board once the shot has finished being shown - the cutscene
## for a hit, or just the splash for a miss.
func end_turn() -> void:
	if phase == Phase.OVER:
		return
	current_player = 1 - current_player
	turn_changed.emit(current_player)
	if mode == Mode.PASS_AND_PLAY:
		_set_phase(Phase.HANDOVER)
	else:
		_set_phase(Phase.PLAYING)

func take_ai_turn() -> Dictionary:
	if gunner == null or current_player != OPPONENT:
		return {"valid": false, "outcome": "not_ai_turn"}
	return fire_at(gunner.choose_shot())

func accuracy(player: int) -> float:
	if shots_fired[player] == 0:
		return 0.0
	return float(hits_landed[player]) / float(shots_fired[player])

func _set_phase(next: Phase) -> void:
	phase = next
	phase_changed.emit(phase)
