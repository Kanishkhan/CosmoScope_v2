extends "res://missions/mission_base.gd"
# 🌙 MOON - "Lunar Expedition"
#
# The science you experience: the Moon has about 1/6 of Earth's gravity (jumps are huge and slow),
# no air (your oxygen is finite and it is silent), razor-sharp black shadows, and crushed-rock
# regolith everywhere. You climb the crater rim by hopping, plant a flag, dig three regolith
# samples with the real digging tool, and watch Earth hang in the black sky. Your lunar day is
# compressed so Earth and the Sun visibly move while you work.
#
#   1. HOP to the highest point of the ridge (found by sampling the real terrain) and plant a flag
#   2. DIG three regolith spots around the rim
#   3. LOOK at Earth for a few seconds - it must be above the horizon

const LUNAR_GRAVITY := 0.17
const O2_DRAIN := 0.42 # % per second
const O2_REFILL := 7.0 # % per second at the lander
const FLAG_SCAN_TIME := 3.0
const EARTH_LOOK_TIME := 4.0
const LOOK_DOT := 0.975
const DAY_LENGTH := 90.0 # seconds per lunar rotation during the mission (compressed)

var _o2 := 100.0
var _rim_pos := Vector3.ZERO
var _flag_scan : Dictionary
var _flag_planted := false
var _regolith := 0
var _earth_seen := false
var _earth_progress := 0.0
var _saved_rotation := 0.0
var _regolith_sites : Array[Dictionary] = []
var _flag_node : Node3D
var _earth_body : StellarBody


func _mission_title() -> String:
	return "🌙 MOON - LUNAR EXPEDITION"


func _mission_intro() -> String:
	return "Gravity is 1/6 g - jump! Hop to the crater rim and plant the flag, dig 3 regolith samples, and photograph Earth. Watch your oxygen."


func _on_start() -> void:
	if "gravity_scale" in character:
		character.set("gravity_scale", LUNAR_GRAVITY)
	# Compress the lunar day so Earth and the Sun move while you work
	_saved_rotation = body.self_revolution_time
	body.self_revolution_time = DAY_LENGTH
	for i in game.get_stellar_body_count():
		if game.get_stellar_body(i).name == "Earth":
			_earth_body = game.get_stellar_body(i)

	var origin := player_pos()
	# The rim = the highest point (farthest from the Moon's centre) found by probing the ground
	var best_alt := -INF
	var base := _rng.randf() * TAU
	for i in 10:
		var p := point_around(origin, base + TAU * float(i) / 10.0, 70.0 + 6.0 * float(i % 3))
		var alt := (p - planet_center()).length()
		if alt > best_alt:
			best_alt = alt
			_rim_pos = p
	_flag_scan = add_scan_site(_rim_pos, 5.0, FLAG_SCAN_TIME, Color(1.0, 0.85, 0.3), "PLANT THE FLAG")

	for i in 3:
		var pos := point_around(_rim_pos, base + 1.0 + TAU * float(i) / 3.0, 22.0 + 6.0 * float(i))
		var site := add_dig_site(pos, 6.5, Color(0.8, 0.8, 0.85), "REGOLITH SAMPLE %d" % (i + 1))
		_regolith_sites.append(site)
	toast("🔇 No air here - nothing carries sound. Your suit radio is the only voice you hear.", 6.0)


func _on_cleanup() -> void:
	if body != null and _saved_rotation > 0.0:
		body.self_revolution_time = _saved_rotation
		_saved_rotation = 0.0


func _earth_dir_and_elevation() -> Array:
	var pos := player_pos()
	if _earth_body == null:
		return [Vector3.UP, -90.0]
	var dir := (_earth_body.node.global_transform.origin - pos).normalized()
	var elev := rad_to_deg(asin(clampf(up_at(pos).dot(dir), -1.0, 1.0)))
	return [dir, elev]


func _on_tick(delta: float) -> void:
	var pos := player_pos()

	# Oxygen: finite, refilled at the lander
	var ship_pos := game.get_ship().global_transform.origin
	var at_lander := pos.distance_to(ship_pos) < 9.0
	var rate := -O2_DRAIN + (O2_REFILL if at_lander else 0.0)
	_o2 = clampf(_o2 + rate * delta, -1.0, 100.0)
	var o01 := clampf(_o2 / 100.0, 0.0, 1.0)
	set_meter("o2", "OXYGEN", o01, Color(1.0, 0.3, 0.2).lerp(Color(0.4, 0.9, 1.0), o01),
		"%d%%%s" % [int(maxf(_o2, 0.0)), "  (refilling at lander)" if at_lander else ""])
	set_meter("tasks", "OBJECTIVES", float(int(_flag_planted) + _regolith + int(_earth_seen)) / 5.0,
		Color(1.0, 0.85, 0.3), "%d/5" % (int(_flag_planted) + _regolith + int(_earth_seen)))

	# Earth observation: look toward Earth while it is above the horizon
	var earth := _earth_dir_and_elevation()
	var earth_up : bool = earth[1] > 4.0
	var look_text := ""
	if not _earth_seen:
		if not earth_up:
			look_text = "Earth is below the horizon - keep working, it will rise as the Moon turns."
		else:
			var head := character.get_node_or_null("Head") as Node3D
			var looking := false
			if head != null:
				looking = (-head.global_transform.basis.z).dot(earth[0]) > LOOK_DOT
			if looking:
				_earth_progress = minf(_earth_progress + delta, EARTH_LOOK_TIME)
			else:
				_earth_progress = maxf(_earth_progress - delta, 0.0)
			look_text = "Earth is up (%d° above the horizon): look right at it and hold still." % int(earth[1])
			set_meter("earth", "OBSERVING EARTH", _earth_progress / EARTH_LOOK_TIME, Color(0.4, 0.7, 1.0))
			if _earth_progress >= EARTH_LOOK_TIME:
				_earth_seen = true
				remove_meter("earth")
				toast("🌍 Earth: 3.7 times wider than the Moon looks from Earth, fixed in a black sky. The Moon always shows Earth the same face (tidal locking).", 8.0)
				_check_win()
	else:
		remove_meter("earth")

	var lit := is_sunlit(pos)
	var surface := "+120 °C in sunlight" if lit else "−170 °C in shade"
	set_objective("Gravity 0.17 g  |  air: none  |  surface here: %s\n[%s] Plant flag   [%d/3] Regolith   [%s] Observe Earth\n%s" % [
		surface, "✔" if _flag_planted else " ", _regolith, "✔" if _earth_seen else " ", look_text])

	var scan := scan_progress_now()
	if scan >= 0.0 and not _flag_planted:
		set_meter("flag", "PLANTING FLAG", scan, Color(1.0, 0.85, 0.3))
	else:
		remove_meter("flag")

	if _o2 <= 0.0:
		lose("You ran out of oxygen. With no atmosphere, the suit's tank is all the air you have - return to the lander to refill.")


func _on_scan_done(site: Dictionary) -> void:
	if site == _flag_scan:
		_flag_planted = true
		_plant_flag()
		toast("🚩 Flag planted at the crater rim. No wind: it stays exactly as you left it - footprints last millions of years.", 6.0)
		_check_win()


func _plant_flag() -> void:
	var root := Node3D.new()
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.05
	pm.bottom_radius = 0.05
	pm.height = 4.0
	pole.mesh = pm
	pole.position = Vector3(0, 2.0, 0)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.95)
	pole.material_override = white
	root.add_child(pole)
	var cloth := MeshInstance3D.new()
	var qm := BoxMesh.new()
	qm.size = Vector3(1.8, 1.1, 0.05)
	cloth.mesh = qm
	cloth.position = Vector3(1.0, 3.3, 0)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.15, 0.15)
	cloth.material_override = red
	root.add_child(cloth)
	add_world_node(root, _rim_pos, up_at(_rim_pos))
	_flag_node = root


func _on_dig_done(site: Dictionary) -> void:
	_regolith += 1
	score += 1
	score_changed.emit(score)
	var pos : Vector3 = (site["node"] as Node3D).global_transform.origin
	toast("⛏ Regolith sample %d/3: crushed rock and glass dust - sharp and clingy, made by billions of years of meteorite impacts." % _regolith, 6.0)
	# A real sample container pops out of the hole
	spawn_pickup("canister", pos, Color(0.85, 0.85, 0.9), "Regolith sample %d" % _regolith)
	_check_win()


func _check_win() -> void:
	if _flag_planted and _regolith >= 3 and _earth_seen:
		win("Expedition complete with %d%% oxygen left." % int(_o2))


func objective_position() -> Vector3:
	if _o2 < 30.0:
		return game.get_ship().global_transform.origin
	if not _flag_planted:
		return _rim_pos
	for site in _regolith_sites:
		if not site["done"]:
			return (site["node"] as Node3D).global_transform.origin
	var p := nearest_pickup_position()
	if p != Vector3.INF:
		return p
	return Vector3.INF


func objective_action() -> String:
	if _o2 < 30.0:
		return "refill O₂"
	if not _flag_planted:
		return "plant flag"
	for site in _regolith_sites:
		if not site["done"]:
			return "dig"
	return "look at Earth" if not _earth_seen else "walk"


func _debrief_facts() -> PackedStringArray:
	return PackedStringArray([
		"Gravity on the Moon is only 1/6 of Earth's (0.17 g): you jump about six times higher and every hop lasts longer - you felt the low gravity in every step.",
		"There is no atmosphere: no wind, no weather, no sound, and a black sky even in daylight. That is also why your flag and footprints will last millions of years.",
		"Surface temperature swings from about +120 °C in sunlight to −170 °C in shade or at night, because with no air nothing spreads or holds the heat.",
		"Regolith is a layer of crushed rock and glass made by billions of years of meteorite impacts; craters stay sharp because nothing erodes them.",
		"The Moon is tidally locked: it always shows Earth the same face, so from the near side Earth hangs nearly fixed in the sky - and during a lunar eclipse Earth passes between the Sun and the Moon.",
	])


func _fail_facts() -> PackedStringArray:
	return PackedStringArray([
		"On the Moon there is no air, so your oxygen tank is finite (about 4 minutes here). Return to the lander to refill it.",
		"Use the low gravity: long hops cover ground quickly and cost no extra oxygen.",
	])
