class_name ShipModels
extends RefCounted

## Where the real hulls live and what has to be done to each one before it can
## float next to the others.
##
## Every model on Sketchfab arrives in its author's own units and heading: the
## battleship is 23 units long down X, the destroyer 0.16 units down Z, the
## submarine 1476. Rather than editing five downloaded files - which would have
## to be redone the moment one is replaced - each is left untouched and the
## corrections are written down here:
##
##   axis      which way the hull runs in the file, before we turn it
##   flip      true when the model's bow points the wrong way down that axis
##   waterline how far up the hull the sea sits, 0 = keel, 1 = deck
##
## In the cutscene every ship is rebuilt to CELL_LENGTH metres per grid square,
## so a 5-square carrier really is two and a half times a 2-square destroyer,
## and a hit on segment 3 of 5 lands three squares back from the bow.

const CELL_LENGTH := 26.0

const TABLE := {
	Ship.Kind.CARRIER: {
		"path": "res://assets/sketchfab/gerald_r_ford_aircraft_carrier/gerald_r_ford_aircraft_carrier.glb",
		"axis": Vector3.BACK, "flip": false, "waterline": 0.30,
	},
	Ship.Kind.BATTLESHIP: {
		"path": "res://assets/sketchfab/littorio_battleship/littorio_battleship.glb",
		"axis": Vector3.RIGHT, "flip": false, "waterline": 0.30,
	},
	Ship.Kind.CRUISER: {
		"path": "res://assets/sketchfab/ticonderoga_missile_cruiser/ticonderoga_missile_cruiser.glb",
		"axis": Vector3.BACK, "flip": false, "waterline": 0.30,
	},
	Ship.Kind.SUBMARINE: {
		"path": "res://assets/sketchfab/submarine/submarine.glb",
		"axis": Vector3.BACK, "flip": true, "waterline": 0.55,
	},
	Ship.Kind.DESTROYER: {
		"path": "res://assets/sketchfab/alreigh_burke_destroyer/alreigh_burke_destroyer.glb",
		"axis": Vector3.BACK, "flip": false, "waterline": 0.30,
	},
}

## Build one hull, bow at the origin pointing down +X, sea level at y = 0,
## scaled so it spans its number of grid squares. Returns the holder node;
## hull_length() says how long it ended up.
static func build(kind: Ship.Kind) -> Node3D:
	var spec: Dictionary = TABLE[kind]
	var holder := Node3D.new()
	holder.name = "Hull"
	if not ResourceLoader.exists(spec["path"]):
		push_warning("missing hull model: %s" % spec["path"])
		return holder

	var model: Node3D = (load(spec["path"]) as PackedScene).instantiate()
	holder.add_child(model)

	var box := measure(model)
	if box.size.length() <= 0.0:
		return holder

	var axis: Vector3 = spec["axis"]
	var along: float = abs(box.size.dot(axis))
	if along <= 0.0001:
		return holder

	var target := hull_length(kind)
	var scale_factor := target / along
	model.scale = Vector3.ONE * scale_factor

	# Turn the hull so bow-to-stern runs down +X.
	var yaw := 0.0
	if axis.is_equal_approx(Vector3.BACK) or axis.is_equal_approx(Vector3.FORWARD):
		yaw = -PI / 2.0
	if spec["flip"]:
		yaw += PI
	model.rotation = Vector3(0.0, yaw, 0.0)

	# Now that it is scaled and turned, sit it in the water: bow on the origin,
	# centred across the beam, and sunk to its waterline.
	var placed := measure(model)
	model.position -= Vector3(placed.position.x, 0.0, placed.get_center().z)
	model.position.y -= placed.position.y + placed.size.y * float(spec["waterline"])
	return holder

static func hull_length(kind: Ship.Kind) -> float:
	return float(Ship.SPECS[kind]["length"]) * CELL_LENGTH

## Where along the hull a given segment sits, bow = 0.
static func segment_offset(kind: Ship.Kind, segment: int) -> float:
	return (float(segment) + 0.5) * CELL_LENGTH

## The size of a model in its parent's space, transforms and all.
##
## Godot will not give a global transform to a node that is not yet in the
## scene tree - it prints an error and hands back the identity, which silently
## measures a nested model as though every part of it sat at the origin. A hull
## has to be measured before it is added to anything, so the transforms are
## walked by hand instead.
static func measure(root: Node) -> AABB:
	var box := AABB()
	var started := false
	var stack: Array = [[root, _local_transform(root)]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var node: Node = entry[0]
		var xform: Transform3D = entry[1]
		var mesh := node as MeshInstance3D
		if mesh != null and mesh.mesh != null:
			var piece: AABB = xform * mesh.get_aabb()
			box = piece if not started else box.merge(piece)
			started = true
		for child in node.get_children():
			stack.append([child, xform * _local_transform(child)])
	return box

static func _local_transform(node: Node) -> Transform3D:
	return node.transform if node is Node3D else Transform3D.IDENTITY
