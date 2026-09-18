extends Node

## Is everything the game names actually there?
##
## A missing hull or a renamed sound does not stop Godot loading the project.
## It warns once, into a log nobody is reading, and then the game runs with a
## silent explosion or an invisible ship. This is the check that turns that
## into a failure.

var failures := 0

func _ready() -> void:
	print("ship models")
	for kind in Board.FLEET:
		var spec: Dictionary = ShipModels.TABLE[kind]
		var name: String = Ship.SPECS[kind]["name"]
		_check(name, ResourceLoader.exists(spec["path"]), spec["path"])

	print("sounds")
	for label in Sound.CLIPS:
		_check(label, ResourceLoader.exists(Sound.CLIPS[label]), Sound.CLIPS[label])

	print("shaders and sky")
	_check("ocean.gdshader", ResourceLoader.exists("res://assets/shaders/ocean.gdshader"))
	_check("the sky panorama", ResourceLoader.exists(Seascape.SKY_PANORAMA), Seascape.SKY_PANORAMA)

	# The sun in the game has to agree with the sun in the sky image. The angle
	# is worked out and proved by dev/checks/_sunangle, and pinned here so that
	# swapping the panorama without re-running it does not go unnoticed.
	var sun_in_image := Vector3(-0.464878, 0.61281, 0.639025)
	var sun := Seascape.make_sun()
	var shines_from: Vector3 = sun.transform.basis.z.normalized()
	_check("the sun is aimed at the sun in the sky",
		shines_from.angle_to(sun_in_image) < deg_to_rad(2.0),
		"%.1f degrees apart" % rad_to_deg(shines_from.angle_to(sun_in_image)))

	print("credit")
	# Every hull came from Sketchfab under CC Attribution, which is only free
	# for as long as the credit travels with it.
	for kind in Board.FLEET:
		var spec: Dictionary = ShipModels.TABLE[kind]
		var folder: String = spec["path"].get_base_dir()
		_check("%s is credited" % Ship.SPECS[kind]["name"],
			FileAccess.file_exists(folder + "/ATTRIBUTION.md"), folder)

	print("")
	if failures == 0:
		print("ASSETS: all checks passed")
	else:
		print("ASSETS: %d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok    %s" % label)
	else:
		failures += 1
		print("  FAIL  %s  %s" % [label, detail])
