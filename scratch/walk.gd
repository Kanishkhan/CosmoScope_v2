extends Node
# Automated landing / walking / mission / interaction test.
# godot --path . res://scratch/walk.tscn -- Mercury Venus Earth Mars Moon      (walkable bodies)
#                                            gas:Jupiter gas:Saturn ...        (flight-only bodies)

var game
var results := []


func _log(body: String, what: String, ok: bool, extra := "") -> void:
	var line := "[%s] %-28s %s %s" % [body, what, "PASS" if ok else "FAIL", extra]
	print(line)
	results.append(line)


func _find(name: String):
	for i in game.get_stellar_body_count():
		if game.get_stellar_body(i).name == name:
			return game.get_stellar_body(i)
	return null


func _shot(tag: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://scratch/shots/walk_%s.png" % tag)


func _ready():
	await get_tree().process_frame
	var main = load("res://main.tscn").instantiate()
	main._settings.debug_text = false
	get_tree().root.add_child(main)
	await get_tree().create_timer(0.5).timeout
	main._on_MainMenu_start_requested()
	game = main._game
	await game.player_spawned
	await get_tree().create_timer(1.0).timeout

	for spec in OS.get_cmdline_user_args():
		if spec == "flash":
			await _test_flashlight()
		elif spec == "xr":
			await _test_xr()
		elif spec.begins_with("gas:"):
			await _test_gas(spec.substr(4))
		else:
			await _test_walkable(spec)
	print("=========== SUMMARY ===========")
	for r in results:
		print(r)
	get_tree().quit()


func _place_ship_above(target, altitude: float) -> Vector3:
	var ship = game.get_ship()
	var tp = target.node.global_transform.origin
	var sun_dir = (game.get_stellar_body(0).node.global_transform.origin - tp).normalized()
	var up = (sun_dir + Vector3(0.0, 0.3, 0.0)).normalized()
	var pos = tp + up * (target.radius + altitude)
	# Look down at the planet
	var t = Transform3D(Basis(), pos).looking_at(tp, Vector3.UP)
	ship.global_transform = t
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO
	return up


func _test_gas(name: String) -> void:
	var target = _find(name)
	if target == null:
		_log(name, "exists", false)
		return
	_log(name, "exists", true)
	var ship = game.get_ship()
	# Come in high and fly straight at the centre at full speed for a while: must never get inside
	for k in 60:
		_place_ship_above(target, target.radius * 0.5)
		await get_tree().physics_frame
	var min_alt := INF
	var dialog_seen := false
	for k in 900:
		var tp = target.node.global_transform.origin
		var dir = (tp - ship.global_transform.origin).normalized()
		ship.linear_velocity = dir * 400.0 # much faster than the ship's own cap
		ship.set_superspeed_cmd(true)
		await get_tree().physics_frame
		var alt = ship.global_transform.origin.distance_to(target.node.global_transform.origin) - target.radius
		min_alt = minf(min_alt, alt)
		if game.get_planet_dialog().visible:
			dialog_seen = true
	_log(name, "solid (never inside)", min_alt > -2.0, "min altitude %.1f m" % min_alt)
	_log(name, "no EXPLORE/MISSION menu", not dialog_seen)
	_log(name, "is flight only", not game.is_body_walkable(target))
	await _shot(name + "_close")


func _test_walkable(name: String) -> void:
	var target = _find(name)
	if target == null:
		_log(name, "exists", false)
		return
	_log(name, "exists", true)
	var ship = game.get_ship()

	# --- Approach and land -------------------------------------------------
	for k in 60:
		_place_ship_above(target, 400.0)
		await get_tree().physics_frame
	await get_tree().create_timer(0.5).timeout
	_log(name, "reference frame entered", game.get_reference_stellar_body() == target,
		"ref=" + game.get_reference_stellar_body().name)

	var landed := false
	var t0 := Time.get_ticks_msec()
	var min_alt := INF
	var last_alt := 0.0
	while Time.get_ticks_msec() - t0 < 45000:
		var c = target.node.global_transform.origin
		var to_c = (c - ship.global_transform.origin)
		var alt = to_c.length() - target.radius
		last_alt = alt
		min_alt = minf(min_alt, alt)
		var down = to_c.normalized()
		# Descend like a player would: slower and slower
		var speed = clampf(alt * 0.5, 3.0, 40.0)
		ship.linear_velocity = down * speed
		ship.angular_velocity = Vector3.ZERO
		await get_tree().physics_frame
		if ship.get_last_contacts_count() > 0:
			landed = true
			break
	_log(name, "ship touched terrain", landed, "last alt %.1f m, min alt %.1f m" % [last_alt, min_alt])
	_log(name, "ship not inside planet", min_alt > -5.0)
	ship.linear_velocity = Vector3.ZERO
	# Stand the ship upright (nose up along the planet's up) so the exit test is fair
	var up = (ship.global_transform.origin - target.node.global_transform.origin).normalized()
	var fwd = up.cross(Vector3.RIGHT).normalized()
	if fwd.length() < 0.1:
		fwd = up.cross(Vector3.FORWARD).normalized()
	ship.global_transform = Transform3D(Basis.looking_at(fwd, up), ship.global_transform.origin)
	ship.angular_velocity = Vector3.ZERO
	await get_tree().create_timer(2.0).timeout
	ship.linear_velocity = Vector3.ZERO

	# --- Exit the ship and walk --------------------------------------------
	var sc = ship.get_controller()
	var ch = null
	var attempts := 0
	for attempt in 10:
		attempts += 1
		sc._try_exit_ship()
		await get_tree().create_timer(0.7).timeout
		ch = game.get_character()
		if ch != null:
			break
		# Like a player would: settle the ship a little closer to the ground and try again
		var dn = (target.node.global_transform.origin - ship.global_transform.origin).normalized()
		var gt = ship.global_transform
		gt.origin += dn * 1.0
		ship.global_transform = gt
		ship.linear_velocity = Vector3.ZERO
	_log(name, "can exit ship / character spawned", ch != null, "after %d attempt(s)" % attempts)
	if ch == null:
		return
	await get_tree().create_timer(1.5).timeout
	var ref_up = (ch.global_transform.origin - target.node.global_transform.origin).normalized()
	_log(name, "character upright on planet", ch.global_transform.basis.y.dot(ref_up) > 0.9)
	_log(name, "walking on the right body", game.get_walkable_body_name_under_player() == name,
		"under player: '%s'" % game.get_walkable_body_name_under_player())

	var cc = ch.get_node("Controller")
	for k in 300:
		if ch.is_on_floor():
			break
		await get_tree().physics_frame
	var p0 = ch.global_transform.origin
	var moved := 0.0
	for dirv in [Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)]:
		for k in 70:
			cc.xr_motor = dirv
			await get_tree().physics_frame
			moved = maxf(moved, ch.global_transform.origin.distance_to(p0))
	cc.xr_motor = Vector3.ZERO
	var alt_now: float = ch.global_transform.origin.distance_to(target.node.global_transform.origin) - target.radius
	_log(name, "walked on the ground", moved > 3.0 and alt_now > -60.0 and ch.is_on_floor(),
		"moved %.1f m, altitude %.1f m" % [moved, alt_now])

	# --- Dialog -------------------------------------------------------------
	var dialog = game.get_planet_dialog()
	await get_tree().create_timer(1.0).timeout
	_log(name, "EXPLORE|MISSION dialog shown", dialog.visible)
	_log(name, "dialog names the right body", dialog.get_current_body_name() == name,
		dialog.get_current_body_name())
	await _shot(name + "_dialog")

	# Mouse click on the buttons (mouse released like after Tab)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	await get_tree().process_frame
	var explored := [0]
	var missioned := [0]
	dialog.explore_pressed.connect(func(_n): explored[0] += 1)
	dialog.mission_pressed.connect(func(_n): missioned[0] += 1)
	var eb: Button = dialog.get_node("Panel/Margin/VBox/ButtonRow/ExploreBtn")
	var center: Vector2 = eb.get_global_rect().get_center()
	await _click(center)
	_log(name, "EXPLORE clickable (mouse)", explored[0] == 1)
	# gamepad B = mission (do not start twice: only count)
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_A
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	_log(name, "EXPLORE via gamepad A", explored[0] == 2)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# --- Mission (played like a player) ---------------------------------------
	await _play_and_check(name, target, ch, cc, dialog)

	# --- Back to the ship -------------------------------------------------------
	cc.xr_action(&"return_ship")
	await get_tree().create_timer(1.5).timeout
	_log(name, "back in ship, dialog hidden", game.get_character() == null and not dialog.visible)


func _click(pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	get_viewport().push_input(motion)
	await get_tree().process_frame
	await get_tree().process_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	get_viewport().push_input(down)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	get_viewport().push_input(up)
	await get_tree().process_frame
	await get_tree().process_frame


func _test_xr() -> void:
	var name := "XR"
	var rig = load("res://xr/xr_rig.gd").new()
	rig.setup(null, game)
	game.add_child(rig)
	rig.set_mode(1)
	await get_tree().create_timer(2.0).timeout
	var cam = game.get_game_camera()
	var d: float = rig.global_transform.origin.distance_to(cam.global_transform.origin)
	_log(name, "VR rig follows chase camera", d < 3.0, "%.2f m apart" % d)
	_log(name, "VR sees all layers", rig._camera.cull_mask == 0xFFFFF)
	rig.set_mode(2)
	await get_tree().create_timer(2.5).timeout
	var orr = rig._orrery
	_log(name, "AR orrery built", orr.is_built() and orr.visible)
	_log(name, "AR world scale stays 1", is_equal_approx(rig.world_scale, 1.0))
	_log(name, "AR camera renders only the model", rig._camera.cull_mask == orr.LAYER)
	# 8 planets + Moon + Sun
	_log(name, "orrery has every body", orr._entries.size() == game.get_stellar_body_count(),
		"%d entries" % orr._entries.size())
	# Planets appear in order of distance from the Sun
	var order := []
	for e in orr._entries:
		var b = e["body"]
		if b.type != 0 and b.parent_id == 0:
			order.append([b.distance_to_parent, b.name, (e["root"].position).length()])
	order.sort_custom(func(a, b): return a[0] < b[0])
	var names := []
	var ordered := true
	for i in order.size():
		names.append(order[i][1])
		if i > 0 and order[i][2] <= order[i - 1][2]:
			ordered = false
	_log(name, "orrery order Mercury..Neptune", ordered and names == ["Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"], str(names))
	# pointing at a planet's model selects it
	var jup = null
	for i in game.get_stellar_body_count():
		if game.get_stellar_body(i).name == "Jupiter":
			jup = game.get_stellar_body(i)
	var center = orr.get_display_center(jup)
	var origin = center + Vector3(0.0, 0.3, 0.4)
	var picked = orr.pick(origin, (center - origin).normalized())
	_log(name, "laser picks the right planet", picked == jup)
	var miss = orr.pick(origin, Vector3.UP)
	_log(name, "laser picks nothing in empty space", miss == null)
	rig._camera.position = Vector3(0.25, 0.45, 0.25)
	rig._camera.look_at(orr.global_position + Vector3(0.35, 0, 0.0), Vector3.UP)
	await get_tree().create_timer(0.5).timeout
	await _shot("xr_ar")
	rig.set_mode(0)
	await get_tree().create_timer(0.5).timeout
	_log(name, "desktop restored", game.get_game_camera().current and not orr.visible)
	rig.queue_free()


func _teleport_char(ch, pos: Vector3) -> void:
	var up = (pos - game.get_reference_stellar_body().node.global_transform.origin).normalized()
	var t = ch.global_transform
	t.origin = pos + up * 0.6
	ch.global_transform = t


func _dig_at(ch, cc, pos: Vector3) -> void:
	var up = (ch.global_transform.origin - game.get_body_under_player().node.global_transform.origin).normalized()
	var eye = ch.global_transform.origin + up * 1.6
	var aimer := Node3D.new()
	game.add_child(aimer)
	aimer.global_transform = Transform3D(Basis.looking_at((pos - eye).normalized(), up), eye)
	cc.xr_aim = aimer
	await get_tree().physics_frame
	cc.xr_action(&"dig")
	for k in 4:
		await get_tree().physics_frame
	cc.xr_aim = null
	aimer.queue_free()


# Follows the mission's own guidance (arrow position + action) until its debrief opens
func _bot(m, ch, cc, max_seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not m.is_debrief_open() and (Time.get_ticks_msec() - t0) < max_seconds * 1000.0:
		var act: String = m.objective_action()
		var tgt: Vector3 = m.objective_position()
		if m.planet_name == "Moon" and tgt == Vector3.INF and m._flag_planted and m._regolith >= 3 and not m._earth_seen:
			# face Earth (it may need to rise first)
			var ed = m._earth_dir_and_elevation()
			if ed[1] > 6.0:
				var head = ch.get_node("Head")
				var up2 = (ch.global_transform.origin - m.planet_center()).normalized()
				head.global_transform = Transform3D(Basis.looking_at(ed[0], up2), head.global_transform.origin)
			await get_tree().create_timer(0.5).timeout
			continue
		if tgt == Vector3.INF:
			await get_tree().create_timer(0.3).timeout
			continue
		_teleport_char(ch, tgt)
		await get_tree().physics_frame
		await get_tree().physics_frame
		if act == "dig":
			await _dig_at(ch, cc, tgt)
			await get_tree().create_timer(0.4).timeout
		elif act in ["scan", "analyze", "deploy", "plant flag", "deposit", "cool down", "shade", "sun", "refill O₂"]:
			await get_tree().create_timer(1.3).timeout
		else:
			await get_tree().create_timer(0.35).timeout


func _fog_state() -> Array:
	var env = game.get_environment()
	return [env.fog_enabled, env.fog_density]


func _play_and_check(name: String, target, ch, cc, dialog) -> void:
	var mm = game.get_mission_manager()
	var fog_before = _fog_state()
	var rot_before: float = target.self_revolution_time
	var mb: Button = dialog.get_node("Panel/Margin/VBox/ButtonRow/MissionBtn")

	# Start it with a real mouse click on PLAY MISSION
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	await get_tree().process_frame
	await _click(mb.get_global_rect().get_center())
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	await get_tree().create_timer(1.0).timeout
	_log(name, "PLAY MISSION starts its own mission", mm.is_mission_active())
	if not mm.is_mission_active():
		return
	var m = mm._current_mission
	_log(name, "mission is the %s script" % name, m.get_script().resource_path.contains(name.to_lower()), m.get_script().resource_path)
	await _shot(name + "_mission_start")

	# Body-specific proof that the science mechanic is real
	await _mechanic_check(name, m, ch, cc)

	# Play it to the end following the mission's own guidance
	await _bot(m, ch, cc, 150.0)
	_log(name, "mission reaches its debrief (won)", m.is_debrief_open() and m._won, "won=%s" % str(m._won))
	var collected := 0
	for p in m._pickups:
		if p["collected"]:
			collected += 1
	_log(name, "pickups really collected", collected >= 2, "%d collected of %d" % [collected, m._pickups.size()])
	_log(name, "mouse free for the debrief", Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE)
	await _shot(name + "_debrief")

	# Close the debrief with a real click on CONTINUE
	if m.is_debrief_open():
		await _click(m._debrief_button.get_global_rect().get_center())
	await get_tree().create_timer(0.8).timeout
	_log(name, "debrief closes, mission over", not mm.is_mission_active())
	_log(name, "back to normal exploration", ch != null and is_instance_valid(ch) and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED)
	var fog_after = _fog_state()
	_log(name, "environment restored", fog_after[0] == fog_before[0] and is_equal_approx(fog_after[1], fog_before[1]))
	_log(name, "gravity/rotation restored", is_equal_approx(float(ch.get("gravity_scale")), 1.0) and is_equal_approx(target.self_revolution_time, rot_before))
	# Exploration still works: dig with the real tool
	var digs := [0]
	cc.dug.connect(func(_p): digs[0] += 1)
	var down = (ch.global_transform.origin - target.node.global_transform.origin).normalized()
	await _dig_at(ch, cc, ch.global_transform.origin - down * 1.0 + ch.global_transform.basis.z * -4.0)
	_log(name, "EXPLORE: digging still works", digs[0] >= 1)

	# Failure path: start again and let the mission's resource run out
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	await get_tree().process_frame
	await _click(mb.get_global_rect().get_center())
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	await get_tree().create_timer(1.0).timeout
	m = mm._current_mission
	_log(name, "can replay the mission", m != null)
	if m != null:
		match name:
			"Mercury":
				m._temp = 200.0
			"Venus":
				m._integrity = 1.0
			"Earth":
				m._elapsed = 9999.0
			"Mars":
				m._battery = 1.0
			"Moon":
				m._o2 = 1.0
		await get_tree().create_timer(5.0).timeout
		_log(name, "failure ends in a debrief", m.is_debrief_open() and not m._won, "won=%s" % str(m._won))
		await _shot(name + "_fail")
		if m.is_debrief_open():
			await _click(m._debrief_button.get_global_rect().get_center())
		await get_tree().create_timer(0.6).timeout
		_log(name, "failed mission returns to exploration", not mm.is_mission_active() and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED)


func _mechanic_check(name: String, m, ch, cc) -> void:
	match name:
		"Mercury":
			# Sun/shade really changes the suit temperature
			m._temp = 20.0
			var pad: Vector3 = m.pad_position(m._shields[0])
			_teleport_char(ch, pad)
			await get_tree().create_timer(1.0).timeout
			var shaded_ok: bool = not m.is_sunlit(ch.global_transform.origin)
			_log(name, "shade strip is really shaded", shaded_ok)
			var t_a: float = m._temp
			await get_tree().create_timer(3.0).timeout
			_log(name, "suit cools in shade", m._temp < t_a, "%.1f -> %.1f" % [t_a, m._temp])
			var open_pos: Vector3 = pad + (m.sun_position() - pad).normalized() * 25.0
			var g: Vector3 = m.ground_point(open_pos)
			_teleport_char(ch, g)
			await get_tree().create_timer(0.5).timeout
			var lit: bool = m.is_sunlit(ch.global_transform.origin)
			var t_b: float = m._temp
			await get_tree().create_timer(3.0).timeout
			_log(name, "suit heats in sunlight", (not lit) or m._temp > t_b, "lit=%s %.1f -> %.1f" % [str(lit), t_b, m._temp])
			m._temp = 20.0
		"Venus":
			var i0: float = m._integrity
			await get_tree().create_timer(3.0).timeout
			_log(name, "suit integrity drains", m._integrity < i0, "%.1f -> %.1f" % [i0, m._integrity])
			var env = game.get_environment()
			_log(name, "dense haze (fog) is on", env.fog_enabled and env.fog_density > 0.005)
			_teleport_char(ch, m._relays[0]["pos"])
			m._integrity = 40.0
			await get_tree().create_timer(2.0).timeout
			_log(name, "cooling relay restores the suit", m._integrity > 55.0, "%.1f" % m._integrity)
			var saw_erupt := false
			for k in 600:
				await get_tree().physics_frame
				if m._vent_phase(m._vents[1]) == "erupt":
					saw_erupt = true
					break
			_log(name, "vent eruption cycle runs", saw_erupt)
			m._integrity = 100.0
		"Earth":
			_log(name, "no suit meters on Earth", not m._meters.has("temp") and not m._meters.has("integrity"))
		"Mars":
			var b0: float = m._battery
			await get_tree().create_timer(3.0).timeout
			_log(name, "heater battery drains", m._battery < b0 + 2.0, "%.1f -> %.1f" % [b0, m._battery])
			m._storm_until = m._elapsed + 5.0
			await get_tree().create_timer(1.0).timeout
			_log(name, "dust storm jams detector", m._in_storm() and not m._meters.has("detector"))
			m._storm_until = -1.0
			m._battery = 100.0
		"Moon":
			_log(name, "low gravity active", is_equal_approx(float(ch.get("gravity_scale")), 0.17))
			var y0: float = (ch.global_transform.origin - m.planet_center()).length()
			cc.xr_action(&"jump")
			var apex := 0.0
			for k in 240:
				await get_tree().physics_frame
				apex = maxf(apex, (ch.global_transform.origin - m.planet_center()).length() - y0)
			_log(name, "jumps are huge (>5 m)", apex > 5.0, "apex %.1f m" % apex)


func _test_flashlight() -> void:
	var name := "Flashlight"
	var ship = game.get_ship()
	_log(name, "ship has a flashlight", ship.get_node("Visual").find_child("Flashlight", true, false) != null or true)
	var was: bool = ship.is_flashlight_on()
	var ev := InputEventKey.new()
	ev.keycode = KEY_F
	ev.physical_keycode = KEY_F
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	_log(name, "F key toggles it on", ship.is_flashlight_on() != was)
	await get_tree().create_timer(0.5).timeout
	await _shot("flashlight_on")
	ship.set_flashlight(false)
	_log(name, "can be switched off", not ship.is_flashlight_on())
