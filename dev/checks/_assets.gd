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

	print("shaders")
	for path in ["res://assets/shaders/ocean.gdshader", "res://assets/shaders/sky.gdshader"]:
		_check(path.get_file(), ResourceLoader.exists(path))

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
