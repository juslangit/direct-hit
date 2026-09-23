extends Node

## The fleet under way: her guns, her wake and the wrecks on the horizon.
##
## The three things this scene photographs are the three that cannot be checked
## by assertion, only looked at. A test can prove the turret's bearing is 34.0
## degrees; only a person can say whether the gunhouse stayed on its barbette
## while it got there. A test can prove a wake emitter exists; only a person can
## say whether the ship looks like she is moving.
##
## It films from outside the wheelhouse on purpose. The player never stands
## here, and that is the point - from the bridge you see a quarter of your own
## turret and none of your wake, so judging either from the player's own view is
## judging them through a letterbox.

const SHOTS := "res://dev/shots/"

var bridge: Node3D

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await get_tree().process_frame
	bridge = (load("res://scenes/bridge.tscn") as PackedScene).instantiate()
	add_child(bridge)
	# Long enough for the wakes to have laid themselves down even if preprocess
	# is ever turned off, and for the swell to have moved off its first frame.
	await get_tree().create_timer(1.2).timeout

	if bridge.turrets.size() < 2:
		push_error("expected two forward turrets cut out of the hull, got %d - see turret.gd"
			% bridge.turrets.size())

	# ---------------------------------------------------------- the guns
	# From above and abaft her starboard quarter, which is the one angle that
	# shows the barbette, the gunhouse and all three barrels at once. If the
	# pivot in turret.gd is wrong, the gunhouse slides off its drum between
	# these two pictures and it is obvious at a glance.
	_snap(0.0)
	await _from("gun_fore_and_aft", Vector3(150.0, 52.0, -78.0), Vector3(63.0, 12.0, 0.0), 38.0)
	_snap(34.0)
	await _from("gun_trained_34", Vector3(150.0, 52.0, -78.0), Vector3(63.0, 12.0, 0.0), 38.0)
	# Hard over, which is the worst case for the cut: anything that was taken
	# out of the hull by mistake is now thirty metres from where it belongs.
	_snap(90.0)
	await _from("gun_trained_90", Vector3(150.0, 52.0, -78.0), Vector3(63.0, 12.0, 0.0), 38.0)
	# Down the barrels from over the roof, for the gap between the gunhouse and
	# the deck around it.
	_snap(34.0)
	await _from("gun_from_above", Vector3(66.0, 62.0, 0.0), Vector3(60.0, 10.0, -10.0), 52.0)

	# ---------------------------------------------------------- the wake
	# Her own, from astern and above: the whole track at once, from the churn
	# under the stern to where it disperses.
	await _from("wake_astern", Vector3(560.0, 120.0, 150.0), Vector3(300.0, 0.0, 30.0), 50.0)
	# And from the beam at sea level, which is how the player sees an escort's -
	# a wake read edge on is mostly a bright line, and a bright line in the
	# wrong place is worse than no wake at all.
	await _from("wake_from_the_beam", Vector3(300.0, 26.0, -260.0), Vector3(240.0, 0.0, 0.0), 46.0)

	# ------------------------------------------------------- the wrecks
	# The near wreck, three kilometres off the starboard bow. Framed narrow,
	# because the question is the shape of the column and at 62 degrees it is
	# forty pixels tall.
	var near := _wreck_at(22.0, 3100.0)
	await _from("wreck_column", Vector3(0.0, 24.0, 0.0), near + Vector3(0.0, 300.0, 0.0), 26.0)
	# All three together, for whether they read as three burning ships at three
	# distances or as three copies of one effect.
	await _from("wreck_horizon", Vector3(0.0, 24.0, 0.0), _wreck_at(34.0, 6200.0), 62.0)

	print("fleet views written")
	get_tree().quit()

func _snap(degrees: float) -> void:
	for gun in bridge.turrets:
		(gun as Turret).snap_to(degrees)

## Where a wreck stands, in the flagship's own frame. Kept in step with
## `_build_wrecks` by hand: bearings 22, -26 and 63 degrees at 3100, 6200 and
## 9400 metres.
func _wreck_at(bearing: float, distance: float) -> Vector3:
	var b := deg_to_rad(bearing)
	return Vector3(-cos(b), 0.0, -sin(b)) * distance

## Photograph the ship from a point in her own frame, looking at another.
##
## The bridge's camera hangs on the player's head, which hangs on the flagship,
## so moving the head is how the camera gets anywhere - and it means every
## position here is in the ship's own frame, where the bow is -X, starboard is
## -Z and the sea is y = 0. The mode is left alone: WATCH draws nothing over
## the picture, which is what a look scene wants.
func _from(name: String, eye: Vector3, at: Vector3, fov: float) -> void:
	bridge.set_mode(0)
	# The pose tween is what normally moves the head, and it would drag the
	# camera away from where this puts it over the next half second.
	if bridge._pose_tween != null and bridge._pose_tween.is_running():
		bridge._pose_tween.kill()
	bridge.head.position = eye
	bridge.camera.fov = fov
	var direction := (at - eye).normalized()
	bridge.head.rotation = Vector3(0.0, atan2(-direction.x, -direction.z), 0.0)
	bridge.camera.rotation = Vector3(asin(clampf(direction.y, -1.0, 1.0)), 0.0, 0.0)
	await _save(name)

func _save(name: String) -> void:
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(SHOTS + name + ".png"))
