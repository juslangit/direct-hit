class_name UiKit
extends RefCounted

## The handful of widgets this game needs, built the same way every time.
##
## Godot's default controls are grey and small. Everything here is oversized on
## purpose - this is a game read across a room, not a settings dialog - and
## dressed as ship's instrumentation: brass on steel, wide letter spacing, hard
## edges rather than rounded ones.

static func heading(text: String, size: int = 46, colour: Color = Palette.INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label

static func body(text: String, size: int = 22, colour: Color = Palette.INK_DIM) -> Label:
	return heading(text, size, colour)

static func button(text: String, wide: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320.0 if wide else 210.0, 66.0)
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", Palette.INK)
	b.add_theme_color_override("font_hover_color", Palette.INK)
	b.add_theme_color_override("font_pressed_color", Palette.INK)
	b.add_theme_color_override("font_disabled_color", Palette.INK_DIM * Color(1, 1, 1, 0.5))
	# Painted steel with a brass edge, nine-sliced so one 256x96 plate serves a
	# button of any size. A StyleBox can carry a texture or a border but not
	# both, which is why the brass is already on the plate.
	b.add_theme_stylebox_override("normal", plate("plate"))
	b.add_theme_stylebox_override("hover", plate("plate_hover"))
	b.add_theme_stylebox_override("pressed", plate("plate_pressed"))
	b.add_theme_stylebox_override("disabled", plate("plate_off"))
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), Palette.BRASS))
	b.pressed.connect(func(): Sound.play("click", -12.0, 1.6))
	return b

## One of the composed plates in assets/ui, as a nine-sliced box.
static func plate(name: String) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = load("res://assets/ui/%s.png" % name)
	# The brass edge is four pixels; the slice has to keep more than that so the
	# corners are not stretched into smears.
	box.set_texture_margin_all(12.0)
	box.set_content_margin_all(15.0)
	return box

static func panel(colour: Color = Palette.PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(colour, Palette.PANEL_EDGE))
	return p

static func _box(fill: Color, edge: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(2)
	box.set_content_margin_all(14)
	return box

static func spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c
