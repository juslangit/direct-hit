class_name Wheelhouse
extends Node3D

## The inside of the bridge: an enclosed steel wheelhouse that the player stands
## in, rather than an open platform on top of the ship.
##
## The first version put the player on a bare platform with a bulwark round it,
## which read as standing on the roof rather than being aboard. This is a room:
## a deck underfoot, four bulkheads, a deckhead over your head, a band of
## windows forward and one each side, and the fittings a bridge actually has -
## the wheel, two engine telegraphs, the compass, voice pipes and a chart table.
##
## Every dimension is in metres and is roughly what a real one measures: ten
## metres across, five and a half deep, two and a half from deck to deckhead,
## with the window sill at a metre and the head at just over two, which is what
## lets someone 1.62 m tall see the sea and their own foredeck at the same time.
##
## Which way things face: the ship's bow is -X, so the forward bulkhead with the
## windows in it is at -DEPTH/2, and +Z is to port.

const WIDTH := 10.0        ## athwartships
const DEPTH := 5.6         ## fore and aft
const HEIGHT := 2.55       ## deck to deckhead
const WALL := 0.12
const SILL := 1.02         ## bottom of the windows
const HEAD := 2.06         ## top of the windows
const MULLION := 0.09
const FORWARD_PANES := 7
const SIDE_PANES := 2

## Where the player's eyes are: on the centre line, a pace and a half back from
## the forward windows, with the wheel and the chart table behind them.
##
## The distance is the whole difference between standing in a room and having a
## window pressed against your face. With your nose on the glass the opening
## fills the entire view and the wheelhouse might as well not be there; a pace
## and a half back and the frame, the mullions, the deckhead and the sill all
## come into view and hold the sea inside them - while the sill is still low
## enough, from this distance, to see your own foredeck under it.
const EYE := Vector3(-DEPTH * 0.5 + 1.5, 1.62, 0.0)

var table_anchor: Node3D

var _steel: StandardMaterial3D
var _dark: StandardMaterial3D
var _brass: StandardMaterial3D
var _deck: StandardMaterial3D

func _ready() -> void:
	_make_materials()
	_build_shell()
	_build_windows()
	_build_fittings()
	_build_lighting()

func _make_materials() -> void:
	_steel = StandardMaterial3D.new()
	_steel.albedo_color = Color(0.34, 0.37, 0.39)
	_steel.roughness = 0.62
	_steel.metallic = 0.25

	_dark = StandardMaterial3D.new()
	_dark.albedo_color = Color(0.17, 0.19, 0.21)
	_dark.roughness = 0.7
	_dark.metallic = 0.2

	# Bridge decks were laid in dark corticene, not bare steel.
	_deck = StandardMaterial3D.new()
	_deck.albedo_color = Color(0.20, 0.17, 0.15)
	_deck.roughness = 0.85
	_deck.metallic = 0.0

	_brass = StandardMaterial3D.new()
	# Worked brass that has been at sea, not a trophy. The first pass came out
	# as bright gold under the deckhead lamps.
	_brass.albedo_color = Color(0.33, 0.26, 0.14)
	_brass.roughness = 0.46
	_brass.metallic = 0.7

func _box(size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	return node

# ------------------------------------------------------------------ the shell

func _build_shell() -> void:
	add_child(_box(Vector3(DEPTH, 0.12, WIDTH), Vector3(0.0, -0.06, 0.0), _deck))
	add_child(_box(Vector3(DEPTH, 0.12, WIDTH), Vector3(0.0, HEIGHT + 0.06, 0.0), _dark))

	# Aft bulkhead, with a doorway in it so the room is not a sealed box.
	var door := 1.0
	var side_width := (WIDTH - door) * 0.5
	for side in [-1.0, 1.0]:
		add_child(_box(
			Vector3(WALL, HEIGHT, side_width),
			Vector3(DEPTH * 0.5, HEIGHT * 0.5, side * (door + side_width) * 0.5), _steel))
	add_child(_box(
		Vector3(WALL, HEIGHT - 2.05, door),
		Vector3(DEPTH * 0.5, 2.05 + (HEIGHT - 2.05) * 0.5, 0.0), _steel))

## Bulkheads with a band cut out of them for the windows: a strip below the
## sill, a strip above the head, and posts between the panes. Drawn this way
## round because a hole in a box is a great deal more work than three boxes.
func _build_windows() -> void:
	# Forward.
	var front := -DEPTH * 0.5
	add_child(_box(Vector3(WALL, SILL, WIDTH), Vector3(front, SILL * 0.5, 0.0), _steel))
	add_child(_box(Vector3(WALL, HEIGHT - HEAD, WIDTH), Vector3(front, HEAD + (HEIGHT - HEAD) * 0.5, 0.0), _steel))
	for i in range(1, FORWARD_PANES):
		var z: float = -WIDTH * 0.5 + WIDTH * float(i) / float(FORWARD_PANES)
		add_child(_box(Vector3(WALL, HEAD - SILL, MULLION), Vector3(front, (SILL + HEAD) * 0.5, z), _steel))

	# Port and starboard.
	for side in [-1.0, 1.0]:
		var z: float = side * WIDTH * 0.5
		add_child(_box(Vector3(DEPTH, SILL, WALL), Vector3(0.0, SILL * 0.5, z), _steel))
		add_child(_box(Vector3(DEPTH, HEIGHT - HEAD, WALL), Vector3(0.0, HEAD + (HEIGHT - HEAD) * 0.5, z), _steel))
		for i in range(1, SIDE_PANES):
			var x: float = -DEPTH * 0.5 + DEPTH * float(i) / float(SIDE_PANES)
			add_child(_box(Vector3(MULLION, HEAD - SILL, WALL), Vector3(x, (SILL + HEAD) * 0.5, z), _steel))
		# The corner posts, so the room does not end in a knife edge.
		for x_side in [-1.0, 1.0]:
			add_child(_box(Vector3(0.16, HEAD - SILL, 0.16),
				Vector3(x_side * (DEPTH * 0.5 - 0.08), (SILL + HEAD) * 0.5, z - side * 0.08), _steel))

# --------------------------------------------------------------- the fittings

func _build_fittings() -> void:
	# The wheel, on the centre line behind the player, where the helmsman
	# stands with a clear sight through the forward windows.
	var helm := Node3D.new()
	helm.position = Vector3(0.55, 0.0, 0.0)
	add_child(helm)
	helm.add_child(_pedestal(0.62, 0.20, 0.26, _dark))
	helm.add_child(_wheel(Vector3(0.0, 0.92, 0.0)))

	# Engine telegraphs, one to each side of the wheel.
	for side in [-1.0, 1.0]:
		var telegraph := Node3D.new()
		telegraph.position = Vector3(0.45, 0.0, side * 1.45)
		add_child(telegraph)
		telegraph.add_child(_pedestal(0.78, 0.13, 0.17, _dark))
		# A dial is a dark face inside a brass rim, tipped back towards whoever
		# is reading it. Built as one brass cylinder with a darker one set
		# slightly proud of it, because a bare cylinder on a stick reads as a
		# coin rather than an instrument.
		telegraph.add_child(_dial(0.27, 0.05, _brass, 0.88))
		telegraph.add_child(_dial(0.23, 0.06, _dark, 0.885))
		for hand in [-1.0, 1.0]:
			var needle := BoxMesh.new()
			needle.size = Vector3(0.018, 0.20, 0.012)
			var pointer := MeshInstance3D.new()
			pointer.mesh = needle
			pointer.material_override = _brass
			pointer.position = Vector3(0.0, 0.90, 0.10 * hand)
			pointer.rotation = Vector3(deg_to_rad(-18.0), 0.0, deg_to_rad(28.0 * hand))
			telegraph.add_child(pointer)

	# The compass, forward and to starboard so it is not in the way of the view
	# straight ahead.
	var binnacle := Node3D.new()
	binnacle.position = Vector3(-DEPTH * 0.5 + 0.75, 0.0, -2.35)
	add_child(binnacle)
	binnacle.add_child(_pedestal(0.86, 0.15, 0.21, _dark))
	var bowl := SphereMesh.new()
	bowl.radius = 0.19
	bowl.height = 0.30
	var head_piece := MeshInstance3D.new()
	head_piece.mesh = bowl
	head_piece.material_override = _brass
	head_piece.position.y = 0.97
	binnacle.add_child(head_piece)

	# Voice pipes against the aft bulkhead.
	for side in [-1.0, 1.0]:
		add_child(_voice_pipe(Vector3(DEPTH * 0.5 - 0.45, 0.0, side * 3.1)))

	# A grab rail along under the forward windows, which is what everyone on a
	# bridge actually holds on to.
	var rail := CylinderMesh.new()
	rail.top_radius = 0.035
	rail.bottom_radius = 0.035
	rail.height = WIDTH - 0.6
	var bar := MeshInstance3D.new()
	bar.mesh = rail
	bar.material_override = _brass
	bar.position = Vector3(-DEPTH * 0.5 + 0.22, SILL - 0.12, 0.0)
	bar.rotation.x = deg_to_rad(90.0)
	add_child(bar)

	# Where the plotting table goes: aft and to port, so the player turns away
	# from the windows to read it.
	table_anchor = Node3D.new()
	table_anchor.name = "TableAnchor"
	table_anchor.position = Vector3(DEPTH * 0.5 - 1.35, 0.0, 2.55)
	table_anchor.rotation.y = deg_to_rad(-104.0)
	add_child(table_anchor)

## One face of an instrument: a flat cylinder lying on its side, tipped back
## eighteen degrees so it can be read by someone standing at it.
func _dial(radius: float, thickness: float, material: Material, height: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = thickness
	mesh.radial_segments = 48
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position.y = height
	node.rotation = Vector3(deg_to_rad(90.0 - 18.0), 0.0, 0.0)
	return node

func _pedestal(height: float, top: float, bottom: float, material: Material) -> MeshInstance3D:
	var column := CylinderMesh.new()
	column.top_radius = top
	column.bottom_radius = bottom
	column.height = height
	var node := MeshInstance3D.new()
	node.mesh = column
	node.material_override = material
	node.position.y = height * 0.5
	return node

func _wheel(at: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.position = at
	# Standing upright and facing forward, so it reads as a wheel rather than a
	# table top.
	holder.rotation.z = deg_to_rad(90.0)

	var rim := TorusMesh.new()
	rim.inner_radius = 0.30
	rim.outer_radius = 0.35
	var ring := MeshInstance3D.new()
	ring.mesh = rim
	ring.material_override = _brass
	holder.add_child(ring)

	for i in 8:
		var spoke := CylinderMesh.new()
		spoke.top_radius = 0.022
		spoke.bottom_radius = 0.022
		spoke.height = 0.80
		var bar := MeshInstance3D.new()
		bar.mesh = spoke
		bar.material_override = _brass
		bar.rotation.x = deg_to_rad(90.0)
		bar.rotation.y = TAU * float(i) / 8.0
		holder.add_child(bar)
	return holder

func _voice_pipe(at: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.position = at
	var tube := CylinderMesh.new()
	tube.top_radius = 0.04
	tube.bottom_radius = 0.04
	tube.height = 1.15
	var stem := MeshInstance3D.new()
	stem.mesh = tube
	stem.material_override = _brass
	stem.position.y = 0.58
	holder.add_child(stem)

	var mouth := CylinderMesh.new()
	mouth.top_radius = 0.11
	mouth.bottom_radius = 0.04
	mouth.height = 0.18
	var bell := MeshInstance3D.new()
	bell.mesh = mouth
	bell.material_override = _brass
	bell.position.y = 1.24
	holder.add_child(bell)
	return holder

## Inside a steel box the sun never reaches, and there is no bounced light in
## this renderer to make up for it. Two shaded lamps under the deckhead.
func _build_lighting() -> void:
	for side in [-1.0, 1.0]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0.2, HEIGHT - 0.25, side * 2.3)
		lamp.light_color = Color(1.0, 0.93, 0.82)
		lamp.light_energy = 2.4
		lamp.omni_range = 7.5
		lamp.omni_attenuation = 1.4
		add_child(lamp)
