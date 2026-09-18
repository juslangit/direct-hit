class_name PlotTable
extends Node3D

## The plotting table on the bridge: a lit glass plot with the enemy's water on
## it, and the only place a target is chosen.
##
## The chart drawn on the glass is the same GridView the game used when it was
## played on a flat screen - rendered into a viewport and used as the table's
## surface, rather than drawn a second time in 3D. That keeps one piece of code
## responsible for what a hit, a miss and a sunk ship look like, so the table
## and any other chart can never disagree.
##
## Picking is done by intersecting the camera's ray with the table's own plane
## rather than through physics. The table is one flat rectangle that never
## moves relative to the bridge; a collision shape and a physics query would be
## a great deal of machinery to answer a question that is four lines of maths.

signal cell_picked(cell: Vector2i)

## Metres. Deliberately smaller than the first one, which was two and a half
## metres across - a fine table for a room with space around it, and far too big
## for this one. To read a board that size square-on you have to stand nearly
## two metres back from it, and a wheelhouse two and a half metres high has
## nowhere to put a reader that far away: the camera ended up pushed through the
## port bulkhead, looking back into the room at the edge of the plot.
const TOP := Vector2(1.75, 1.30)
const HEIGHT := 0.92
## Tipped well up towards whoever is reading it, like the angled face of a
## console rather than a flat table top. Lying almost flat, the far rows are
## badly foreshortened: the squares at the top of the plot are a third the size
## of the ones at the bottom, which makes them hard to read and hard to hit.
const TILT := 40.0
const RESOLUTION := 700

var chart: GridView
var _viewport: SubViewport
var _surface: MeshInstance3D
var _plane_node: Node3D
var hovered := Vector2i(-1, -1)

func _ready() -> void:
	_build()

func _build() -> void:
	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = Color(0.22, 0.24, 0.26)
	frame_material.roughness = 0.55
	frame_material.metallic = 0.3

	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.40, 0.33, 0.20)
	brass.roughness = 0.4
	brass.metallic = 0.7

	# Legs.
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var leg := CylinderMesh.new()
			leg.top_radius = 0.035
			leg.bottom_radius = 0.045
			leg.height = HEIGHT
			var node := MeshInstance3D.new()
			node.mesh = leg
			node.material_override = frame_material
			node.position = Vector3(x * (TOP.x * 0.5 - 0.18), HEIGHT * 0.5, z * (TOP.y * 0.5 - 0.16))
			add_child(node)

	# The plot itself, tipped towards whoever is reading it.
	_plane_node = Node3D.new()
	_plane_node.position = Vector3(0.0, HEIGHT, 0.0)
	# Tipped towards the reader, not away. The sign matters: the plot is a
	# single-sided surface, so tipping it the other way at any real angle shows
	# the player the back of it - which culls to nothing, leaving them looking
	# at the table's casing and legs and wondering where the chart went.
	_plane_node.rotation.x = deg_to_rad(TILT)
	add_child(_plane_node)

	var casing := BoxMesh.new()
	casing.size = Vector3(TOP.x + 0.14, 0.1, TOP.y + 0.14)
	var casing_node := MeshInstance3D.new()
	casing_node.mesh = casing
	casing_node.material_override = frame_material
	casing_node.position.y = -0.05
	_plane_node.add_child(casing_node)

	var lip := BoxMesh.new()
	lip.size = Vector3(TOP.x + 0.16, 0.03, TOP.y + 0.16)
	var lip_node := MeshInstance3D.new()
	lip_node.mesh = lip
	lip_node.material_override = brass
	# Kept below the glass. It is a solid slab and it is wider than the plot on
	# every side, so a millimetre too high and it does not edge the chart - it
	# covers it completely, and the table reads as a blank brass tray.
	lip_node.position.y = -0.010
	_plane_node.add_child(lip_node)

	# The live chart.
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(RESOLUTION, RESOLUTION)
	_viewport.transparent_bg = false
	# ALWAYS, not WHEN_VISIBLE. A SubViewport only counts as visible when it
	# sits inside a SubViewportContainer; used as a texture on a surface in the
	# world there is nothing to make it visible, so it never draws a frame and
	# the table comes out blank.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	chart = GridView.new()
	chart.interactive = false      ## picked in 3D, not by its own mouse events
	# Anchored to fill the viewport rather than given a size. A Control that is
	# handed a size and no anchors can be laid back out to nothing, and a
	# GridView with no size draws no chart at all - which looks exactly like a
	# viewport that never rendered.
	chart.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(chart)

	var glass := StandardMaterial3D.new()
	glass.albedo_texture = _viewport.get_texture()
	# The plot carries its own light, the way a backlit glass table does. It
	# also means the chart stays readable whatever the weather is doing.
	glass.emission_enabled = true
	glass.emission_texture = _viewport.get_texture()
	# Paper lit by the table's lamp, not a screen. Left at screen brightness the
	# sheet glows like a lightbox and stops reading as paper at all.
	glass.emission_energy_multiplier = 0.32
	# Paper, not glass. At a low roughness the sheet holds a mirror image of the
	# deckhead lamp above it - a soft white blob right through the middle of the
	# board, which survived removing the table's own lamp because it was never
	# that lamp making it.
	glass.roughness = 0.92
	glass.metallic = 0.0
	glass.metallic_specular = 0.05

	var top := QuadMesh.new()
	top.size = TOP
	_surface = MeshInstance3D.new()
	_surface.mesh = top
	_surface.material_override = glass
	# A QuadMesh faces +Z, so it is laid flat with its top upward.
	_surface.rotation.x = -PI / 2.0
	_surface.position.y = 0.014
	_plane_node.add_child(_surface)

	# No lamp over the plot any more. It made sense over a dark glass screen;
	# over pale paper it only ever burned a soft white hole through the middle
	# of the board, and the chart already carries its own light through the
	# material's emission.

## Where to stand to read the plot: straight out along its own face, far enough
## back that the whole board fits.
##
## Worked out from the surface's transform rather than written down as offsets
## from the table's feet, because the plot is tipped and those are two different
## directions.
func reading_pose(vertical_fov_degrees: float) -> Array:
	var normal: Vector3 = _surface.global_transform.basis.z.normalized()
	var centre: Vector3 = _surface.global_position
	# The margin leaves room at the bottom of the screen for the instruction
	# line and the buttons, which otherwise sit across the last row of squares.
	var reach: float = (TOP.y * 1.52) / (2.0 * tan(deg_to_rad(vertical_fov_degrees) * 0.5))
	return [centre + normal * reach, centre]

func set_board(board: Board) -> void:
	chart.set_board(board)

func refresh() -> void:
	chart.queue_redraw()

## Which square a ray from the player's eye lands on, or (-1, -1) for a ray
## that misses the plot entirely.
func pick(from: Vector3, direction: Vector3) -> Vector2i:
	var plane_origin := _surface.global_position
	# basis.z, not basis.y. A QuadMesh lies in its own XY plane and faces +Z,
	# so +Z is the way out of the chart; +Y runs up the chart's face. Taking Y
	# as the normal describes a plane at right angles to the plot, and every
	# click lands on that instead - which still returns a square, and still
	# returns the middle square when you click the middle, so it hid behind
	# every test that only ever clicked the centre.
	var normal := _surface.global_transform.basis.z.normalized()
	var facing := normal.dot(direction)
	if absf(facing) < 0.0001:
		return Vector2i(-1, -1)
	var distance := normal.dot(plane_origin - from) / facing
	if distance <= 0.0:
		return Vector2i(-1, -1)

	var local := _surface.global_transform.affine_inverse() * (from + direction * distance)
	# In the quad's own space x runs across the top and y up it; the quad is
	# laid flat, so y is the fore-aft direction on the table.
	var u := local.x / TOP.x + 0.5
	var v := 0.5 - local.y / TOP.y

	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return Vector2i(-1, -1)
	return chart.cell_at(Vector2(u, v) * float(RESOLUTION))

## The middle of one square, out in the world. The exact inverse of pick(), so
## the two can be checked against each other.
func cell_world_position(cell: Vector2i) -> Vector3:
	var u := (float(cell.x) + 0.5) / float(Board.SIZE)
	var v := (float(cell.y) + 0.5) / float(Board.SIZE)
	# The chart is drawn into a square viewport but the plot is wider than it is
	# deep, so the chart's own margins have to be undone the same way pick()
	# reads them.
	var on_chart := Vector2(u, v) * float(RESOLUTION)
	var rect := chart.cell_rect(chart.cell_at(on_chart))
	var middle := rect.get_center() / float(RESOLUTION)
	var local := Vector3((middle.x - 0.5) * TOP.x, (0.5 - middle.y) * TOP.y, 0.0)
	return _surface.global_transform * local

func hover(cell: Vector2i) -> void:
	if cell == hovered:
		return
	hovered = cell
	chart.hovered = cell
	chart.queue_redraw()

func choose(cell: Vector2i) -> void:
	if Board.in_bounds(cell):
		cell_picked.emit(cell)
