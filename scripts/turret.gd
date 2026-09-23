class_name Turret
extends Node3D

## One of the flagship's forward turrets, cut out of her hull so that it can
## train.
##
## The Littorio is a bought model and her turrets are welded on: the file is a
## Sketchfab materialmerger export, ten meshes merged by material and named
## Object_2 to Object_11, with no node called anything like a turret and no
## bone to drive. For most of this game that does not matter - a hull seen from
## half a mile does not need moving parts. It matters here because the player
## stands thirty metres behind these guns and looks straight down them, and
## guns that point down the centre line while the plot says thirty-four degrees
## to starboard say, plainly, that none of this is real.
##
## So the turrets are separated from the hull at load time. Every triangle
## whose centre falls inside one of a turret's boxes is moved into a mesh of
## its own, hung on a node that can rotate, and taken out of the mesh it came
## from. Each mesh's vertex array is handed over untouched and only its index
## array is shortened, so nothing else about the ship moves and there is no
## seam; the turret's own vertices are re-indexed into a mesh of their own, so
## its bounding box is the turret and not the whole ship.
##
## What stays behind is the barbette - the armoured drum a turret sits in,
## which on a real ship does not rotate either. That is why every box has a
## floor: below the line is drum, above it is gunhouse.
##
## **Merged by material means merged across the ship.** This is the thing that
## makes the work fiddly and it is worth stating plainly, because the first
## attempt got it wrong twice. A name like "Object_10" is not a part of the
## ship; it is every part that happened to share one texture. Object_10 holds
## the whole of A turret, *and* B turret's three barrels, *and* both triple
## secondaries out at the ship's sides - and B turret's gunhouse is not in it
## at all, it is in Object_11. So a turret is not one box in one mesh. It is a
## list of boxes in named meshes, and the only way to get the list right is to
## look: `dev/probe/_cut.gd` paints each merged mesh a different colour and
## photographs her, which is how the table below was written.

## The two forward turrets, in the hull holder's own frame: metres aft of the
## bow (the bow is x = 0 and -X is ahead), metres above the sea, metres either
## side of the centre line.
##
## Every bound was measured off the painted renders and the vertex probe rather
## than guessed, and several of them are load-bearing:
##
##   A's floor at 9.8    the foredeck is at 10.2, so this clears deck and drum
##   A's roof at 14.4    her gunhouse roof is at 14.0
##   A's beam at 7.0     her gunhouse is 11 m across; the inboard edge of the
##                       triple secondaries is at 8.0, and they are in the same
##                       merged mesh, so there is less than a metre of margin
##                       here and it is the reason this is 7.0 and not 7.5
##   B's barrel floor    14.5, which is what keeps A's gunhouse roof, at 14.0,
##                       out of B's barrels: the two overlap completely in
##                       length and in beam, and height is the only thing that
##                       separates them. B superfires over A, so her barrels
##                       lie above A's roof from x 69.5 to x 83.5
##   B's gunhouse floor  13.0, because Object_11 also has deck-level structure
##                       under her at 10.8 that must not come with her
##
## The pivot of each is the middle of its own gunhouse box, which is where the
## barbette is. Get it wrong and the gunhouse slides off its drum as it trains,
## which `dev/looks/_fleet.gd` photographs at 90 degrees for exactly this
## reason - hard over is where a bad pivot is unmissable.
const FORWARD := [
	{
		"name": "TurretA",
		"muzzle": Vector3(49.2, 11.3, 0.0),
		"gunhouse": AABB(Vector3(61.5, 9.8, -7.0), Vector3(12.0, 4.6, 14.0)),
		"pieces": [
			# Her barrels, then her gunhouse. Both in Object_10.
			["Object_10", AABB(Vector3(46.0, 9.8, -4.0), Vector3(15.5, 4.6, 8.0))],
			["Object_10", AABB(Vector3(61.5, 9.8, -7.0), Vector3(12.0, 4.6, 14.0))],
		],
	},
	{
		"name": "TurretB",
		"muzzle": Vector3(69.8, 16.0, 0.0),
		"gunhouse": AABB(Vector3(83.0, 13.0, -8.0), Vector3(13.5, 6.0, 16.0)),
		"pieces": [
			# Her barrels are in Object_10 with A's; her gunhouse is not.
			["Object_10", AABB(Vector3(68.0, 14.5, -3.4), Vector3(16.0, 3.0, 6.8))],
			["Object_11", AABB(Vector3(83.0, 13.0, -8.0), Vector3(13.5, 6.0, 16.0))],
		],
	},
]

## Degrees a second. The Littorio's main turrets trained at about six, and the
## number is the point rather than a detail: laying three 381 mm guns on a new
## bearing is a slow, heavy thing, and watching it take the better part of ten
## seconds is most of what the traverse is for.
const RATE := 6.0

## How far one can train either way before the guns are looking through her own
## bridge. A real forward turret is stopped well short of dead astern.
const LIMIT := 150.0

## Degrees off the bow, positive to starboard - because in this game the bow is
## -X and starboard is -Z, and every bearing on the bridge is written that way.
var wanted := 0.0
var bearing := 0.0

## Where this turret's centre gun points from, in the turret's own frame, so
## that a muzzle flash swings round with the guns.
var muzzle := Vector3.ZERO

## Cut both forward turrets out of a hull built by ShipModels and hang them on
## it. Returns them in order, A first, or an empty array if the model is not
## the one these boxes were measured against - in which case the caller carries
## on with welded turrets rather than with no ship.
static func cut_from(hull: Node3D) -> Array:
	var made: Array = []
	for spec in FORWARD:
		var turret := _cut_one(hull, spec)
		if turret != null:
			made.append(turret)
	return made

static func _cut_one(hull: Node3D, spec: Dictionary) -> Turret:
	var gunhouse: AABB = spec["gunhouse"]
	var pivot := Vector3(gunhouse.get_center().x, 0.0, 0.0)

	# Group this turret's boxes by the mesh they come out of, so each merged
	# mesh is read and rewritten once however many of its parts are taken.
	var by_mesh := {}
	for piece in spec["pieces"]:
		var mesh_name: String = piece[0]
		if not by_mesh.has(mesh_name):
			by_mesh[mesh_name] = []
		by_mesh[mesh_name].append(piece[1])

	var turret := Turret.new()
	turret.name = spec["name"]
	turret.position = pivot
	turret.muzzle = spec["muzzle"] - pivot

	for mesh_name in by_mesh:
		var skin := _take(hull, mesh_name, by_mesh[mesh_name], pivot)
		if skin != null:
			turret.add_child(skin)
	if turret.get_child_count() == 0:
		turret.free()
		push_warning("turret: the cut found nothing for %s" % spec["name"])
		return null
	hull.add_child(turret)
	return turret

## Move every triangle of one merged mesh that falls inside one of `boxes` into
## a mesh of its own, and take it out of the mesh it came from.
##
## Safe to run twice on the same mesh, which it has to be: both forward turrets
## take part of Object_10. The vertex array is handed on untouched each time and
## only the index array shortens, so the indices a later pass reads still mean
## what they meant.
static func _take(hull: Node3D, mesh_name: String, boxes: Array, pivot: Vector3) -> MeshInstance3D:
	var found := _find(hull, mesh_name, Transform3D.IDENTITY)
	if found.is_empty():
		push_warning("turret: no mesh named %s in this hull" % mesh_name)
		return null
	var from_node: MeshInstance3D = found[0]
	var to_hull: Transform3D = found[1]
	var mesh: ArrayMesh = from_node.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() != 1:
		push_warning("turret: %s is not a single-surface ArrayMesh" % mesh_name)
		return null

	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	# Sort every triangle by where its centre lands. A triangle is taken whole
	# or left whole - splitting one across a boundary would need new vertices
	# and would show as a crack the moment the turret trained.
	var mine := PackedInt32Array()
	var theirs := PackedInt32Array()
	for i in range(0, index.size(), 3):
		var a := index[i]
		var b := index[i + 1]
		var c := index[i + 2]
		var middle: Vector3 = to_hull * ((verts[a] + verts[b] + verts[c]) / 3.0)
		var taken := false
		for box in boxes:
			if (box as AABB).has_point(middle):
				taken = true
				break
		var into := mine if taken else theirs
		into.append(a)
		into.append(b)
		into.append(c)
	if mine.size() < 3:
		return null

	var material: Material = mesh.surface_get_material(0)

	var without: Array = arrays.duplicate()
	without[Mesh.ARRAY_INDEX] = theirs
	var trimmed := ArrayMesh.new()
	trimmed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, without)
	trimmed.surface_set_material(0, material)
	from_node.mesh = trimmed

	var skin := MeshInstance3D.new()
	skin.name = mesh_name
	skin.mesh = _lift(arrays, mine, to_hull, pivot, material)
	return skin

## Build a turret's own mesh from the triangles that were taken.
##
## The vertices are re-indexed so that the mesh holds only its own, and are
## baked into the hull holder's frame less the pivot - which is what lets the
## turret node sit at the pivot with no rotation of its own and still have
## every barrel exactly where the bought model put it.
static func _lift(
		arrays: Array, taken: PackedInt32Array, to_hull: Transform3D,
		pivot: Vector3, material: Material) -> ArrayMesh:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]

	var moved := PackedVector3Array()
	var moved_normals := PackedVector3Array()
	var moved_uvs := PackedVector2Array()
	var moved_index := PackedInt32Array()
	var seen := {}
	for old in taken:
		if not seen.has(old):
			seen[old] = moved.size()
			moved.append(to_hull * verts[old] - pivot)
			# The hull's transform is a uniform scale and a turn, so a normal
			# only has to be carried through the basis and made unit again.
			if normals.size() > 0:
				moved_normals.append((to_hull.basis * normals[old]).normalized())
			if uvs.size() > 0:
				moved_uvs.append(uvs[old])
		moved_index.append(seen[old])

	var built: Array = []
	built.resize(Mesh.ARRAY_MAX)
	built[Mesh.ARRAY_VERTEX] = moved
	if moved_normals.size() > 0:
		built[Mesh.ARRAY_NORMAL] = moved_normals
	if moved_uvs.size() > 0:
		built[Mesh.ARRAY_TEX_UV] = moved_uvs
	built[Mesh.ARRAY_INDEX] = moved_index

	var lifted := ArrayMesh.new()
	lifted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, built)
	lifted.surface_set_material(0, material)
	return lifted

static func _find(node: Node, wanted_name: String, xform: Transform3D) -> Array:
	var here: Transform3D = xform * (node.transform if node is Node3D else Transform3D.IDENTITY)
	if node is MeshInstance3D and String(node.name) == wanted_name:
		return [node, here]
	for child in node.get_children():
		var hit := _find(child, wanted_name, here)
		if not hit.is_empty():
			return hit
	return []

## Lay the guns on a bearing, in degrees off the bow, starboard positive.
func train_to(degrees: float) -> void:
	wanted = clampf(degrees, -LIMIT, LIMIT)

## Lay the guns along a direction in the hull's own frame. The height of it is
## thrown away: these guns train, they do not elevate.
func train_along(direction: Vector3) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.000001:
		return
	# The barrels point down -X with the turret at rest, and turning a node
	# about +Y by t takes -X to (-cos t, 0, sin t). Starboard is -Z, hence the
	# sign: a bearing to starboard is a negative rotation.
	train_to(-rad_to_deg(atan2(flat.z, -flat.x)))

## Fore and aft, where she sits when there is no target.
func centre() -> void:
	train_to(0.0)

## Put the guns on a bearing at once, with no traverse. For the look scenes and
## the checks, which want a known bearing rather than a wait.
func snap_to(degrees: float) -> void:
	train_to(degrees)
	bearing = wanted
	rotation.y = -deg_to_rad(bearing)

## Are the guns on the bearing they were given? The bridge does not gate firing
## on this - the player lays the sight, and that is the test - but a check can
## ask, and so can anything staged after the guns have come round.
func trained() -> bool:
	return absf(bearing - wanted) < 0.5

func _process(delta: float) -> void:
	if is_equal_approx(bearing, wanted):
		return
	bearing = move_toward(bearing, wanted, RATE * delta)
	rotation.y = -deg_to_rad(bearing)
