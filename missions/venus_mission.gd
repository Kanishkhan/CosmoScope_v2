extends "res://missions/mission_base.gd"
# ♀ VENUS - "Into the Inferno"
#
# The science you experience: crushing pressure (92 bar) and 465 °C under a dense CO2 sky mean
# your suit integrity is constantly draining; the only relief is cooling relays. The air is a thick
# orange haze (fog) laced with drifting sulfuric-acid clouds, and the ground is volcanic: vents
# erupt on a cycle - you can see them glow and rumble before they blow.
#
# Three geological tasks, each different in kind:
#   1. SCAN a fresh volcanic vent (stand at its rim for a few seconds - but not while it erupts!)
#   2. DIG a basalt core out of a 'pancake dome' and pick it up
#   3. CARRY a seismometer from the relay to a distant site and deploy it (hold still to set it up)

const DRAIN := 0.95 # % per second: heat + pressure
const RELAY_HEAL := 11.0 # % per second inside a relay
const ACID_DAMAGE := 5.5 # % per second inside an acid cloud
const ERUPTION_DAMAGE := 32.0 # % per hit
const VENT_PERIOD := 9.0
const VENT_WARN_START := 5.0
const VENT_ERUPT_START := 7.2
const VENT_ERUPT_END := 8.5
const VENT_HIT_RADIUS := 6.5

var _integrity := 100.0
var _relays : Array[Dictionary] = []
var _vents : Array[Dictionary] = []
var _clouds : Array[Dictionary] = []
var _origin := Vector3.ZERO
var _tasks := {"vent": false, "core": false, "seismo": false}
var _vent_scan : Dictionary
var _core_dig : Dictionary
var _seismo_pickup : Dictionary
var _seismo_site : Dictionary
var _hit_cooldown := 0.0
var _acid_toast := 0.0
var _fog_saved := {}


func _mission_title() -> String:
	return "♀ VENUS - INTO THE INFERNO"


func _mission_intro() -> String:
	return "92 bar and 465 °C: your suit is failing. Scan the vent, dig a basalt core, deploy the seismometer - and use the cooling relays to survive."


func _on_start() -> void:
	_origin = player_pos()
	var base := _rng.randf() * TAU
	_enable_haze()

	# Cooling relays: one at the landing point, one out in the field
	_relays.append(_make_relay(point_around(_origin, base + 0.6, 16.0)))
	_relays.append(_make_relay(point_around(_origin, base + 3.4, 95.0)))

	# Volcanic vents; the first one is the scan target
	var vent_defs := [[base, 45.0], [base + 2.1, 62.0], [base + 4.2, 40.0]]
	for i in vent_defs.size():
		_vents.append(_make_vent(point_around(_origin, vent_defs[i][0], vent_defs[i][1]), float(i) * 3.0))
	_vent_scan = add_scan_site(_vents[0]["pos"] + up_at(_vents[0]["pos"]) * 0.1, 9.0, 4.0,
		Color(1.0, 0.5, 0.15), "SCAN VENT RIM")

	# Basalt core: dig at the pancake dome
	_core_dig = add_dig_site(point_around(_origin, base + 1.0, 75.0), 6.5, Color(0.95, 0.7, 0.3),
		"PANCAKE DOME - basalt core")

	# Seismometer: pick it up near the first relay, deploy it far away
	_seismo_pickup = spawn_pickup("case", point_around(_relays[0]["pos"], base + 1.0, 6.0),
		Color(0.4, 1.0, 0.9), "Seismometer")
	_seismo_site = add_scan_site(point_around(_origin, base + 3.0, 58.0), 4.5, 3.0,
		Color(0.4, 1.0, 0.9), "DEPLOY SEISMOMETER")
	_seismo_site["active"] = false
	(_seismo_site["node"] as Node3D).visible = false

	# Acid clouds wander around the area
	for i in 2:
		_clouds.append(_make_cloud(base + i * PI, 36.0 + 24.0 * i, 3.2 - i * 0.9))


func _on_cleanup() -> void:
	var env := game.get_environment() if game != null else null
	if env != null and not _fog_saved.is_empty():
		env.fog_enabled = _fog_saved["enabled"]
		env.fog_density = _fog_saved["density"]
		env.fog_light_color = _fog_saved["color"]
		_fog_saved.clear()


func _enable_haze() -> void:
	var env := game.get_environment()
	if env == null:
		return
	_fog_saved = {"enabled": env.fog_enabled, "density": env.fog_density, "color": env.fog_light_color}
	env.fog_enabled = true
	env.fog_light_color = Color(0.95, 0.6, 0.2)
	env.fog_density = 0.009


func _make_relay(pos: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.name = "CoolingRelay"
	var pad := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 5.0
	disc.bottom_radius = 5.0
	disc.height = 0.12
	pad.mesh = disc
	pad.material_override = _material(Color(0.3, 0.85, 1.0), 0.4)
	pad.position = Vector3(0, 0.1, 0)
	root.add_child(pad)
	var tower := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.9
	cyl.height = 4.0
	tower.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.85, 0.95)
	mat.metallic = 0.5
	tower.material_override = mat
	tower.position = Vector3(0, 2.0, 0)
	root.add_child(tower)
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.1
	bm.bottom_radius = 0.5
	bm.height = 40.0
	beam.mesh = bm
	beam.position = Vector3(0, 20.0, 0)
	beam.material_override = _material(Color(0.3, 0.85, 1.0), 0.25)
	root.add_child(beam)
	var tag := _label3d("COOLING RELAY", 44)
	tag.position = Vector3(0, 6.0, 0)
	root.add_child(tag)
	add_world_node(root, pos, up_at(pos))
	return {"pos": pos, "node": root}


func _make_vent(pos: Vector3, offset: float) -> Dictionary:
	var root := Node3D.new()
	root.name = "VolcanicVent"
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.2
	cm.bottom_radius = 4.0
	cm.height = 2.6
	cone.mesh = cm
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.16, 0.1, 0.09)
	rock.roughness = 1.0
	cone.material_override = rock
	cone.position = Vector3(0, 1.3, 0)
	root.add_child(cone)
	var glow := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 1.25
	gm.bottom_radius = 1.25
	gm.height = 0.1
	glow.mesh = gm
	var glow_mat := _material(Color(1.0, 0.45, 0.1), 0.9)
	glow.material_override = glow_mat
	glow.position = Vector3(0, 2.7, 0)
	root.add_child(glow)
	var column := MeshInstance3D.new()
	var col := CylinderMesh.new()
	col.top_radius = 2.4
	col.bottom_radius = 3.2
	col.height = 46.0
	column.mesh = col
	column.material_override = _material(Color(1.0, 0.5, 0.1), 0.65)
	column.position = Vector3(0, 23.0, 0)
	column.visible = false
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(column)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.15)
	light.omni_range = 26.0
	light.light_energy = 1.5
	light.position = Vector3(0, 4.0, 0)
	root.add_child(light)
	var tag := _label3d("VOLCANIC VENT", 40)
	tag.position = Vector3(0, 8.0, 0)
	root.add_child(tag)
	add_world_node(root, pos, up_at(pos))
	return {"pos": pos, "node": root, "glow": glow, "glow_mat": glow_mat, "column": column,
		"light": light, "offset": offset, "phase": "idle", "hit": false}


func _make_cloud(angle: float, radius: float, speed: float) -> Dictionary:
	var node := MeshInstance3D.new()
	node.name = "AcidCloud"
	var sphere := SphereMesh.new()
	sphere.radius = 12.0
	sphere.height = 24.0
	node.mesh = sphere
	node.material_override = _material(Color(0.75, 0.85, 0.2), 0.3)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tag := _label3d("ACID CLOUD", 44)
	tag.position = Vector3(0, 14.0, 0)
	node.add_child(tag)
	add_world_node(node, _origin, up_at(_origin))
	return {"node": node, "angle": angle, "radius": radius, "speed": speed}


func _vent_phase(vent: Dictionary) -> String:
	var t := fmod(_elapsed + float(vent["offset"]), VENT_PERIOD)
	if t >= VENT_ERUPT_START and t < VENT_ERUPT_END:
		return "erupt"
	if t >= VENT_WARN_START and t < VENT_ERUPT_START:
		return "warn"
	return "idle"


func _scan_allowed(site: Dictionary) -> bool:
	# The vent rim can only be scanned between eruptions
	if site == _vent_scan:
		return _vent_phase(_vents[0]) != "erupt"
	return true


func _on_tick(delta: float) -> void:
	var pos := player_pos()
	_hit_cooldown -= delta
	_acid_toast -= delta

	# Vents: warn (glow + rumble), then erupt with a damaging column
	for i in _vents.size():
		var v := _vents[i]
		var phase := _vent_phase(v)
		var column : Node3D = v["column"]
		column.visible = phase == "erupt"
		var mat : StandardMaterial3D = v["glow_mat"]
		if phase == "warn":
			var pulse := 0.5 + 0.5 * sin(_elapsed * 14.0)
			mat.albedo_color = Color(1.0, 0.25 + 0.4 * pulse, 0.1, 1.0)
			(v["light"] as OmniLight3D).light_energy = 3.0 + 4.0 * pulse
			if v["phase"] != "warn" and pos.distance_to(v["pos"]) < 40.0:
				toast("🌋 The vent is rumbling - get clear!", 2.0)
		elif phase == "erupt":
			(v["light"] as OmniLight3D).light_energy = 9.0
		else:
			mat.albedo_color = Color(1.0, 0.45, 0.1, 0.9)
			(v["light"] as OmniLight3D).light_energy = 1.5
		v["phase"] = phase
		if phase == "erupt":
			var flat := pos - (v["pos"] as Vector3)
			var up := up_at(v["pos"])
			flat -= up * flat.dot(up)
			if flat.length() < VENT_HIT_RADIUS and _hit_cooldown <= 0.0:
				_integrity -= ERUPTION_DAMAGE
				_hit_cooldown = 1.2
				toast("🌋 Caught in an eruption! Suit -%d%%" % int(ERUPTION_DAMAGE), 2.5)
				if v == _vents[0]:
					_vent_scan["progress"] = 0.0

	# Acid clouds drift in circles
	var in_acid := false
	for c in _clouds:
		c["angle"] += float(c["speed"]) * delta / float(c["radius"])
		var axes := tangent_axes(up_at(_origin))
		var p : Vector3 = _origin + (axes[0] * cos(c["angle"]) + axes[1] * sin(c["angle"])) * float(c["radius"]) + up_at(_origin) * 4.0
		(c["node"] as Node3D).global_position = p
		if pos.distance_to(p) < 12.0:
			in_acid = true

	# Suit integrity: constant drain, acid, and relays
	var rate := -DRAIN
	if in_acid:
		rate -= ACID_DAMAGE
		if _acid_toast <= 0.0:
			toast("☠ Sulfuric acid cloud - move out of it!", 2.0)
			_acid_toast = 3.0
	for r in _relays:
		if pos.distance_to(r["pos"]) < 5.0:
			rate += RELAY_HEAL
			if _integrity < 99.0 and _acid_toast <= 0.0:
				toast("❄ Cooling relay: suit restoring", 1.5)
				_acid_toast = 2.0
	_integrity = clampf(_integrity + rate * delta, -1.0, 100.0)

	var i01 := clampf(_integrity / 100.0, 0.0, 1.0)
	set_meter("integrity", "SUIT INTEGRITY", i01, Color(1.0, 0.25, 0.15).lerp(Color(0.3, 1.0, 0.4), i01),
		"%d%%" % int(maxf(_integrity, 0.0)))
	var scan := scan_progress_now()
	if scan >= 0.0:
		set_meter("scan", "SCANNING", scan, Color(1.0, 0.7, 0.2))
	else:
		remove_meter("scan")
	var advice := "→ Suit low! Reach a cooling relay." if _integrity < 40.0 \
		else "→ Follow the arrow; avoid vents and acid clouds."
	set_objective("Pressure 92 bar  |  465 °C  |  CO₂ 96%%\n%s  %s  %s\n%s" % [
		_mark(_tasks["vent"], "Scan vent rim"), _mark(_tasks["core"], "Dig basalt core"),
		_mark(_tasks["seismo"], "Deploy seismometer"), advice])
	if _integrity <= 0.0:
		lose("The heat and pressure finished your suit. Venus's surface is ~465 °C at 92 times Earth's pressure - even robot landers lasted only about two hours.")


func _on_dig_done(site: Dictionary) -> void:
	if site == _core_dig:
		toast("⛏ Basalt exposed! Pick up the core sample.", 4.0)
		var pos : Vector3 = (site["node"] as Node3D).global_transform.origin
		spawn_pickup("core", pos, Color(0.95, 0.7, 0.3), "Basalt core")


func _on_pickup(p: Dictionary) -> void:
	if p["label"] == "Basalt core":
		_tasks["core"] = true
		toast("🪨 Basalt core: fresh volcanic rock - Venus's surface is young lava plains.", 6.0)
	elif p["label"] == "Seismometer":
		_seismo_site["active"] = true
		(_seismo_site["node"] as Node3D).visible = true
		toast("📡 Seismometer collected - carry it to the marked site and hold still to deploy.", 5.0)
	_check_win()


func _on_scan_done(site: Dictionary) -> void:
	if site == _vent_scan:
		_tasks["vent"] = true
		toast("🌋 Vent scan complete: sulfur dioxide - active volcanism (Venus has 1,600+ major volcanoes).", 6.0)
	elif site == _seismo_site:
		_tasks["seismo"] = true
		toast("📡 Seismometer deployed: it will listen for 'Venusquakes' through the crust.", 6.0)
	_check_win()


func _check_win() -> void:
	score = int(_tasks["vent"]) + int(_tasks["core"]) + int(_tasks["seismo"])
	score_changed.emit(score)
	if _tasks["vent"] and _tasks["core"] and _tasks["seismo"]:
		win("All three geological objectives complete with %d%% suit integrity left." % int(_integrity))


func objective_position() -> Vector3:
	if _integrity < 40.0:
		var best := Vector3.INF
		var best_d := INF
		for r in _relays:
			var d : float = player_pos().distance_to(r["pos"])
			if d < best_d:
				best_d = d
				best = r["pos"]
		return best
	if not _tasks["vent"]:
		return _vents[0]["pos"]
	if not _tasks["core"]:
		if not _core_dig["done"]:
			return (_core_dig["node"] as Node3D).global_transform.origin
		return nearest_pickup_position()
	if not _tasks["seismo"]:
		if not _seismo_pickup["collected"]:
			return (_seismo_pickup["node"] as Node3D).global_transform.origin
		return (_seismo_site["node"] as Node3D).global_transform.origin
	return Vector3.INF


func objective_action() -> String:
	if _integrity < 40.0:
		return "cool down"
	if not _tasks["vent"]:
		return "scan"
	if not _tasks["core"] and not _core_dig["done"]:
		return "dig"
	if _tasks["core"] or _core_dig["done"]:
		if _tasks["seismo"] or _seismo_pickup["collected"]:
			return "deploy" if not _tasks["seismo"] else "walk"
	return "walk"


func _debrief_facts() -> PackedStringArray:
	return PackedStringArray([
		"Venus's atmosphere is 96% carbon dioxide: a runaway greenhouse effect makes the surface about 465 °C - hotter than Mercury, even though it is nearly twice as far from the Sun.",
		"Surface pressure is about 92 bar, like being 900 m under Earth's ocean. The Soviet Venera landers survived from 23 minutes to about two hours.",
		"Thick clouds of sulfuric acid droplets reflect most sunlight, so the surface is a dim orange twilight; the acid rain evaporates before it ever reaches the ground.",
		"Venus has more volcanoes than any other planet. Its surface is young basalt plains, lava channels and 'pancake dome' volcanoes you just sampled.",
		"It rotates backwards, very slowly: a Venus day (243 Earth days) is longer than its year (225 days).",
	])


func _fail_facts() -> PackedStringArray:
	return PackedStringArray([
		"Venus's surface is ~465 °C at ~92 bar, so your suit drains continuously - cooling relays are your lifeline.",
		"Watch the vents glow before they erupt, and stay out of the drifting acid clouds.",
	])


func _mark(done: bool, text: String) -> String:
	return ("[✔] " if done else "[  ] ") + text
