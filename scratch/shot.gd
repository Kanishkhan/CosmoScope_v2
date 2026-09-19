extends Node
# Usage: godot --path . res://scratch/shot.tscn -- Name:factor Name:factor ...
# Puts the ship `factor` planet radii from the body (looking at it, lit side) and saves a screenshot.
# Optional third field "walk" or "land" is not used here; see walk.gd.

func _place(game, target, factor: float):
	var ship = game.get_ship()
	var tp = target.node.global_transform.origin
	var sun_dir = (game.get_stellar_body(0).node.global_transform.origin - tp).normalized()
	if game.get_reference_stellar_body().type == 0 and target.type != 0:
		pass
	var side = sun_dir.cross(Vector3.UP).normalized()
	var dir = (sun_dir * 0.9 + side * 0.45).normalized()
	var pos = tp + dir * target.radius * factor
	var t = Transform3D(Basis(), pos).looking_at(tp, Vector3.UP)
	ship.global_transform = t
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO
	return tp


func _ready():
	await get_tree().process_frame
	var main = load("res://main.tscn").instantiate()
	main._settings.debug_text = false
	get_tree().root.add_child(main)
	await get_tree().create_timer(0.5).timeout
	main._on_MainMenu_start_requested()
	var game = main._game
	await game.player_spawned
	await get_tree().create_timer(1.0).timeout
	for spec in OS.get_cmdline_user_args():
		var parts := spec.split(":")
		var body_name := parts[0]
		var factor := float(parts[1])
		var target = null
		for i in game.get_stellar_body_count():
			if game.get_stellar_body(i).name == body_name:
				target = game.get_stellar_body(i)
		if target == null:
			print("no body ", body_name)
			continue
		for k in 90:
			_place(game, target, factor)
			await get_tree().physics_frame
		await get_tree().create_timer(1.0).timeout
		var ship = game.get_ship()
		var d = ship.global_transform.origin.distance_to(target.node.global_transform.origin)
		var img := get_viewport().get_texture().get_image()
		var path := "res://scratch/shots/%s_%s.png" % [body_name, str(factor).replace(".", "_")]
		img.save_png(path)
		print("saved ", path, " ref=", game.get_reference_stellar_body().name, " dist_in_radii=", d / target.radius)
	get_tree().quit()
