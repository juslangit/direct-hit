extends Node

## How big is each hull, and which way is it pointing?
##
## A model downloaded from Sketchfab arrives at whatever scale and heading its
## author happened to use. The cutscene has to lay the ship along a line of
## grid squares and put the shell hole at, say, segment 3 of 5 - which is
## impossible until we know the length of the hull in metres and which axis
## runs bow to stern. This prints that, so those numbers can be written down
## once instead of guessed at in the editor.

const MODELS := {
	"Carrier": "res://assets/sketchfab/gerald_r_ford_aircraft_carrier/gerald_r_ford_aircraft_carrier.glb",
	"Battleship": "res://assets/sketchfab/littorio_battleship/littorio_battleship.glb",
	"Cruiser": "res://assets/sketchfab/ticonderoga_missile_cruiser/ticonderoga_missile_cruiser.glb",
	"Submarine": "res://assets/sketchfab/submarine/submarine.glb",
	"Destroyer": "res://assets/sketchfab/alreigh_burke_destroyer/alreigh_burke_destroyer.glb",
}

func _ready() -> void:
	for name in MODELS:
		var path: String = MODELS[name]
		if not ResourceLoader.exists(path):
			print("%-12s MISSING %s" % [name, path])
			continue
		var scene: PackedScene = load(path)
		var node: Node3D = scene.instantiate()
		add_child(node)
		await get_tree().process_frame

		var box := _bounds(node)
		var size := box.size
		var axis := "X" if size.x >= max(size.y, size.z) else ("Y" if size.y >= size.z else "Z")
		var longest: float = max(size.x, max(size.y, size.z))
		print("%-12s length %7.2f on %s  size (%6.2f, %6.2f, %6.2f)  centre (%6.2f, %6.2f, %6.2f)  meshes %d  tris %d" % [
			name, longest, axis, size.x, size.y, size.z,
			box.get_center().x, box.get_center().y, box.get_center().z,
			_count_meshes(node), _count_tris(node),
		])
		node.queue_free()
	get_tree().quit()

func _bounds(node: Node) -> AABB:
	var box := AABB()
	var started := false
	for mesh in _meshes(node):
		var world := mesh.global_transform * mesh.get_aabb()
		if not started:
			box = world
			started = true
		else:
			box = box.merge(world)
	return box

func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out

func _count_meshes(node: Node) -> int:
	return _meshes(node).size()

func _count_tris(node: Node) -> int:
	var n := 0
	for mesh in _meshes(node):
		var m := mesh.mesh
		if m == null:
			continue
		for surface in m.get_surface_count():
			var arrays := m.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.size() > 0:
				n += indices.size() / 3
			else:
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				n += verts.size() / 3
	return n
