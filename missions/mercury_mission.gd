extends "res://missions/mission_base.gd"
# ☿ MERCURY - "Extreme World"
#
# The science you experience: with (almost) no atmosphere, Mercury's temperature depends only on
# whether the Sun is shining on you. Your suit temperature moves toward the environment's: about
# +430 C in full sunlight, about -170 C in shadow. You must hop between sun and shade to survive
# while you recover four instruments scattered over the cratered ground.
#
# Shade comes from shelters with a sun parasol that tracks the Sun (the Sun moves across the sky
# as the planet turns). Shade is tested with real rays
# to the Sun: your own shadows on the ground are the real ones.

const T_START := 20.0
const T_HOT := 110.0
const T_COLD := -70.0
const K_HEAT := 0.014 # 1/s, how fast the suit follows the environment
const SHADE_TEMP := -170.0
const SUN_TEMP := 430.0
const PARASOL_SIZE := Vector3(15.0, 15.0, 0.5)
const PARASOL_HEIGHT := 4.5

var _temp := T_START
var _max_temp := T_START
var _min_temp := T_START
var _lit := true
var _shields : Array[Dictionary] = []
var _readings := 0
var _warned := 0.0


func _mission_title() -> String:
	return "☿ MERCURY - EXTREME WORLD"


func _mission_intro() -> String:
	return "No air: only shade protects you. Recover 4 instruments - and keep your suit between %d °C and +%d °C." % [int(T_COLD), int(T_HOT)]


func _on_start() -> void:
	var origin := player_pos()
	var base := _rng.randf() * TAU
	var defs : Array[Dictionary] = [
		{"name": "Surface thermometer", "kind": "probe", "color": Color(1.0, 0.55, 0.2), "shade": false},
		{"name": "Exosphere sniffer", "kind": "canister", "color": Color(0.7, 0.9, 1.0), "shade": false},
		{"name": "Crater seismometer", "kind": "case", "color": Color(0.95, 0.85, 0.4), "shade": false},
		{"name": "Cold-trap ice probe", "kind": "flask", "color": Color(0.5, 0.85, 1.0), "shade": true},
	]
	for i in defs.size():
		var angle := base + TAU * float(i) / float(defs.size())
		var pos := point_around(origin, angle, 55.0 + 9.0 * i)
		# A shade shelter 11 m from each instrument
		var shelter := _make_shelter(point_around(pos, angle + PI, 11.0))
		_shields.append(shelter)
		var def := defs[i]
		if def["shade"]:
			# The ice probe sits inside the shelter's permanent shade
			spawn_pickup(def["kind"], point_around(shelter["pos"], 0.7, 2.6), def["color"], def["name"], def)
		else:
			spawn_pickup(def["kind"], pos, def["color"], def["name"], def)
	_update_shields()


# A shade shelter: a marked pad on the ground and a big sun parasol floating on the line between the
# pad and the Sun. The parasol tracks the Sun as the planet turns, so the pad stays in real shade at
# any sun elevation (shade is tested with a real ray to the Sun, and the parasol casts a real shadow).
func _make_shelter(pos: Vector3) -> Dictionary:
	var up := up_at(pos)
	var root := Node3D.new()
	root.name = "ShadeShelter"
	var pad := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 5.0
	disc.bottom_radius = 5.0
	disc.height = 0.1
	pad.mesh = disc
	pad.material_override = _material(Color(0.35, 0.6, 1.0), 0.35)
	pad.position = Vector3(0, 0.12, 0)
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pad)
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.1
	bm.bottom_radius = 0.5
	bm.height = 40.0
	beam.mesh = bm
	beam.position = Vector3(0, 20.0, 0)
	beam.material_override = _material(Color(0.35, 0.6, 1.0), 0.22)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)
	var tag := _label3d("SHADE SHELTER", 44)
	tag.position = Vector3(0, 3.0, 0)
	root.add_child(tag)
	add_world_node(root, pos, up)

	# The parasol (solid: it blocks the ray to the Sun and casts the shadow)
	var plate := StaticBody3D.new()
	plate.name = "SunParasol"
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = PARASOL_SIZE
	shape.shape = box_shape
	plate.add_child(shape)
	var mesh_i := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = PARASOL_SIZE
	mesh_i.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.77, 0.84)
	mat.metallic = 0.6
	mat.roughness = 0.35
	mesh_i.material_override = mat
	plate.add_child(mesh_i)
	game.add_child(plate)
	_spawned.append(plate)
	return {"root": root, "plate": plate, "pos": pos}


func _sun_dir_flat(from: Vector3) -> Vector3:
	var up := up_at(from)
	var d := (sun_position() - from).normalized()
	d = d - up * d.dot(up)
	if d.length() < 0.001:
		return Vector3.FORWARD
	return d.normalized()


func _update_shields() -> void:
	for s in _shields:
		var pos : Vector3 = s["pos"]
		var up := up_at(pos)
		var to_sun := (sun_position() - pos).normalized()
		# Keep the parasol at least ~4 m above the ground, on the ray to the Sun
		var elev_sin := maxf(to_sun.dot(up), 0.22)
		var center := pos + up * 1.0 + to_sun * (PARASOL_HEIGHT / elev_sin)
		var ref := up if absf(to_sun.dot(up)) < 0.98 else Vector3.RIGHT
		var plate : Node3D = s["plate"]
		plate.global_transform = Transform3D(Basis.looking_at(-to_sun, ref).orthonormalized(), center)


func pad_position(shield: Dictionary) -> Vector3:
	return shield["pos"]


func _nearest_pad() -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for s in _shields:
		var p := pad_position(s)
		var d := p.distance_to(player_pos())
		if d < best_d:
			best_d = d
			best = p
	return best


func _on_tick(delta: float) -> void:
	_update_shields()
	var pos := player_pos()
	var up := up_at(pos)
	_lit = is_sunlit(pos)
	var to_sun := (sun_position() - pos).normalized()
	var target := SHADE_TEMP
	if _lit:
		target = SHADE_TEMP + (SUN_TEMP - SHADE_TEMP) * sqrt(clampf(up.dot(to_sun), 0.0, 1.0))
	_temp += K_HEAT * (target - _temp) * delta
	_max_temp = maxf(_max_temp, _temp)
	_min_temp = minf(_min_temp, _temp)

	var t01 := inverse_lerp(T_COLD, T_HOT, _temp)
	var color := Color(0.3, 0.6, 1.0).lerp(Color(0.3, 1.0, 0.4), clampf(t01 * 2.0, 0.0, 1.0)) \
		if t01 < 0.5 else Color(0.3, 1.0, 0.4).lerp(Color(1.0, 0.25, 0.15), clampf((t01 - 0.5) * 2.0, 0.0, 1.0))
	set_meter("temp", "SUIT TEMP", t01, color, "%d °C  (%s)" % [int(_temp), "SUNLIT" if _lit else "SHADE"])
	set_meter("readings", "INSTRUMENTS", float(_readings) / 4.0, Color(1.0, 0.85, 0.3), "%d/4" % _readings)
	set_objective("Recover the 4 instruments.  Sun elevation %d°  |  Air pressure ≈ 0  |  Solar day = 176 Earth days\n%s" % [
		int(sun_elevation_deg(pos)), _advice()])

	_warned -= delta
	if _warned <= 0.0:
		if _temp > T_HOT - 25.0 and _lit:
			toast("⚠ OVERHEATING - get into a shade shelter!", 2.5)
			_warned = 3.0
		elif _temp < T_COLD + 25.0 and not _lit:
			toast("⚠ FREEZING - step back into the sunlight!", 2.5)
			_warned = 3.0

	if _temp >= T_HOT:
		lose("Your suit overheated at %d °C. With no atmosphere, direct sunlight heats you fast: you have to keep hopping back into shade." % int(_temp))
	elif _temp <= T_COLD:
		lose("Your suit froze at %d °C. In shade there is no air to keep you warm: you have to return to the sunlight." % int(_temp))


func _advice() -> String:
	if _temp > 70.0 and _lit:
		return "→ Cool down: walk onto a blue shade-shelter pad."
	if _temp < -35.0 and not _lit:
		return "→ Warm up: step out into the sunlight."
	return "→ Collect the next instrument (watch your temperature)."


func objective_position() -> Vector3:
	if _temp > 70.0 and _lit:
		return _nearest_pad()
	if _temp < -35.0 and not _lit:
		return player_pos() + _sun_dir_flat(player_pos()) * 12.0
	return nearest_pickup_position()


func objective_action() -> String:
	if _temp > 70.0 and _lit:
		return "shade"
	if _temp < -35.0 and not _lit:
		return "sun"
	return "walk"


func _on_pickup(p: Dictionary) -> void:
	_readings += 1
	score = _readings
	score_changed.emit(score)
	var label_name : String = p["label"]
	match label_name:
		"Surface thermometer":
			toast("📟 %s: %d °C in the sunlight here, %d °C in shade - a swing of about 600 °C." % [label_name, int(SUN_TEMP), int(SHADE_TEMP)], 6.0)
		"Exosphere sniffer":
			toast("📟 %s: air pressure ~1 trillionth of Earth's. It's a vacuum - nothing carries heat or sound." % label_name, 6.0)
		"Crater seismometer":
			toast("📟 %s: this ground is scarred by impacts. With no air, meteoroids arrive at full speed and nothing erodes the craters." % label_name, 6.0)
		"Cold-trap ice probe":
			toast("📟 %s: water ice survives in permanent shadow, even on the planet nearest the Sun!" % label_name, 6.0)
	if _readings >= 4:
		win("All instruments recovered. Suit temperature ranged from %d °C to %d °C." % [int(_min_temp), int(_max_temp)])


func _debrief_facts() -> PackedStringArray:
	return PackedStringArray([
		"Mercury swings from about +430 °C in sunlight to about −180 °C at night - the biggest range of any planet, because it has almost no atmosphere to hold or spread heat.",
		"You survived by shade alone: with a near-vacuum exosphere, only direct sunlight heats you, and shadow is instantly cold.",
		"A solar day on Mercury lasts about 176 Earth days: it turns 3 times for every 2 orbits (a 3:2 resonance) and circles the Sun in just 88 days.",
		"Its surface is saturated with impact craters, like the Moon's, because there is no air to burn up meteoroids and almost no erosion.",
		"Although it is the planet closest to the Sun (58 million km), permanently shadowed polar craters hold water ice.",
	])


func _fail_facts() -> PackedStringArray:
	return PackedStringArray([
		"Mercury's temperature depends only on sunlight: +430 °C in the Sun, −170 °C in shadow.",
		"Keep your suit between %d °C and +%d °C by alternating between sunlight and the blue shade-shelter pads." % [int(T_COLD), int(T_HOT)],
	])
