extends Control

## The main menu: a screen of its own, with no game running behind it.
##
## It used to be the live bridge with the title drawn over it, which looked
## handsome and was wrong in two ways. It kept the whole game - ocean, fleet,
## weather - turning at full cost to be a backdrop, and it gave the player no
## sense of having started anything: the game was already happening before they
## had chosen to play it.
##
## So this is a still. Nothing here runs, nothing here is loaded but one
## picture, and the bridge is not built until a match begins.

signal play_requested(mode: int)
signal quit_requested

const KEY_ART := "res://assets/menu/key_art.jpg"

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()
	_build_face()

func _build_backdrop() -> void:
	var art := TextureRect.new()
	art.texture = load(KEY_ART)
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Cover, not stretch: the picture keeps its shape and is cropped to whatever
	# window it is given, which is what a key image has to survive.
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)

	# Two washes rather than one flat scrim: a dark band up the left for the
	# words to sit on, and a gentler one along the bottom for the small print.
	# A single even scrim over the whole picture dulls it everywhere and still
	# leaves the text fighting whatever is behind it.
	var side := _gradient_rect(Vector2(0, 0.5), Vector2(1, 0.5), [
		Color(0.02, 0.05, 0.08, 0.92), Color(0.02, 0.05, 0.08, 0.62), Color(0.02, 0.05, 0.08, 0.0)
	], PackedFloat32Array([0.0, 0.34, 0.72]))
	add_child(side)
	var base := _gradient_rect(Vector2(0.5, 1), Vector2(0.5, 0), [
		Color(0.02, 0.05, 0.08, 0.80), Color(0.02, 0.05, 0.08, 0.0)
	], PackedFloat32Array([0.0, 0.42]))
	add_child(base)

func _gradient_rect(from: Vector2, to: Vector2, colours: Array, offsets: PackedFloat32Array) -> TextureRect:
	var gradient := Gradient.new()
	gradient.offsets = offsets
	var packed := PackedColorArray()
	for colour in colours:
		packed.append(colour)
	gradient.colors = packed

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = from
	texture.fill_to = to
	texture.width = 256
	texture.height = 256

	var rect := TextureRect.new()
	rect.texture = texture
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func _build_face() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.offset_left = 96.0
	column.offset_right = 780.0
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	var eyebrow := UiKit.body("A BATTLESHIPS GAME", 20, Palette.BRASS)
	eyebrow.add_theme_constant_override("line_spacing", 0)

	var title := UiKit.heading("DIRECT HIT", 104, Palette.INK)
	title.add_theme_constant_override("line_spacing", -8)

	var rule := TextureRect.new()
	rule.texture = load("res://assets/ui/brass_trim.jpg")
	rule.custom_minimum_size = Vector2(190, 7)
	rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rule.stretch_mode = TextureRect.STRETCH_SCALE

	var tagline := UiKit.body(
		"You have the bridge. Call a square on the plot,\nlay the guns on the bearing, and watch what you hit.",
		24, Palette.INK)

	column.add_child(eyebrow)
	column.add_child(UiKit.spacer(6))
	column.add_child(title)
	column.add_child(UiKit.spacer(10))
	column.add_child(rule)
	column.add_child(UiKit.spacer(22))
	column.add_child(tagline)
	column.add_child(UiKit.spacer(38))

	for entry in [
		["PLAY THE COMPUTER", func(): play_requested.emit(0)],
		["TWO PLAYERS", func(): play_requested.emit(1)],
	]:
		var button := UiKit.button(entry[0], true)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var row := HBoxContainer.new()
		row.add_child(button)
		column.add_child(row)
		column.add_child(UiKit.spacer(12))
		button.pressed.connect(entry[1])

	var leave := UiKit.button("LEAVE THE SHIP")
	leave.alignment = HORIZONTAL_ALIGNMENT_LEFT
	leave.pressed.connect(func(): quit_requested.emit())
	var leave_row := HBoxContainer.new()
	leave_row.add_child(leave)
	column.add_child(leave_row)

	var colophon := UiKit.body(
		"Godot 4.7 · five real hulls · CC0 sky and sound · built by hand", 17, Palette.INK_DIM)
	colophon.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	colophon.offset_left = 96.0
	colophon.offset_top = -52.0
	add_child(colophon)
