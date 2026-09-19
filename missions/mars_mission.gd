extends "res://missions/mission_base.gd"
# ♂ MARS - "Search for Life"
#
# The science you experience: Mars is cold (about -63 °C on average) and its air is only ~0.6% of
# Earth's pressure, so your suit heater runs on a battery you must keep charged - solar cells only
# help in sunlight. Dust storms roll in (visibility drops, the detector is jammed, the heater works
# harder). The hunt is a real geology workflow:
#   - a ground-penetrating DETECTOR shows signal strength and a bearing to buried evidence
#   - you DIG the marked spots with the real digging tool to expose ancient-water evidence
#     (hematite from a dried river delta, clay minerals, polar-style ice, volcanic basalt)
#   - the four samples go to the lander for BIOSIGNATURE ANALYSIS - where a storm may hit mid-scan.

const DRAIN := 0.85 # % per second: keeping the suit warm at -63 °C
const STORM_DRAIN_FACTOR := 2.2
const SOLAR_CHARGE := 1.45 # % per second, only in sunlight and outside storms
const STORM_FIRST := 40.0
const STORM_PERIOD := 65.0
const STORM_LENGTH := 20.0
const DETECTOR_RANGE := 130.0
const REVEAL_RANGE := 32.0

const POI_DEFS := [
	{"name": "Ancient river delta", "kind": "case", "color": Color(0.9, 0.3, 0.2),
		"result": "Hematite 'blueberries' - iron oxide that forms in liquid water. This dry delta was once a lake bed."},
	{"name": "Clay mineral bed", "kind": "case", "color": Color(0.85, 0.6, 0.35),
		"result": "Clay minerals form in slow-moving, neutral water - the kind of water life could use."},
	{"name": "Polar-style ice deposit", "kind": "flask", "color": Color(0.5, 0.9, 1.0),
		"result": "Water ice under the dust - Mars still holds huge amounts of ice in its polar caps and underground."},
	{"name": "Volcanic basalt (Tharsis)", "kind": "core", "color": Color(0.7, 0.7, 0.75),
		"result": "Basalt from the Tharsis volcanoes - Olympus Mons is the tallest volcano known, about 22 km high."},
]

var _battery := 100.0
var _pois : Array[Dictionary] = []
var _samples := 0
var _storm_until := -1.0
var _next_storm := STORM_FIRST
var _storm_warned := false
var _fog_saved := {}
var _analysis : Dictionary
var _analysis_started := false


func _mission_title() -> String:
	return "♂ MARS - SEARCH FOR LIFE"


func _mission_intro() -> String:
	return "-63 °C and almost no air. Follow the detector, dig up 4 samples of ancient-water and volcanic evidence, then analyze them at the lander. Keep your battery alive."


func _on_start() -> void:
	var origin := player_pos()
	var base := _rng.randf() * TAU
	var dists := [55.0, 72.0, 62.0, 84.0]
	for i in POI_DEFS.size():
		var def : Dictionary = POI_DEFS[i]
		var pos := point_around(origin, base + TAU * float(i) / 4.0 + 0.4, dists[i])
		var site := add_dig_site(pos, 6.5, def["color"], def["name"], def)
		# Only revealed when you get close: you have to use the detector to find them
		(site["node"] as Node3D).visible = false
		_pois.append(site)
	_enable_dust(0.0006)


func _on_cleanup() -> void:
	var env := game.get_environment() if game != null else null
	if env != null and not _fog_saved.is_empty():
		env.fog_enabled = _fog_saved["enabled"]
		env.fog_density = _fog_saved["density"]
		env.fog_light_color = _fog_saved["color"]
		_fog_saved.clear()


func _enable_dust(density: float) -> void:
	var env := game.get_environment()
	if env == null:
		return
	if _fog_saved.is_empty():
		_fog_saved = {"enabled": env.fog_enabled, "density": env.fog_density, "color": env.fog_light_color}
	env.fog_enabled = true
	env.fog_light_color = Color(0.85, 0.5, 0.3)
	env.fog_density = density


func _in_storm() -> bool:
	return _elapsed < _storm_until


func _on_tick(delta: float) -> void:
	var pos := player_pos()

	# Dust storms come and go
	if not _in_storm() and not _storm_warned and _elapsed > _next_storm - 6.0:
		toast("🌪 A dust storm is coming in - your detector will jam and the heater will work harder!", 5.0)
		_storm_warned = true
	if not _in_storm() and _elapsed >= _next_storm:
		_storm_until = _elapsed + STORM_LENGTH
		_next_storm += STORM_PERIOD
		_storm_warned = false
		toast("🌪 DUST STORM - visibility is low. The thin air can't carry much force, but the dust chokes your solar cells.", 5.0)
	var target_density := 0.028 if _in_storm() else 0.0006
	var env := game.get_environment()
	if env != null:
		env.fog_density = lerpf(env.fog_density, target_density, clampf(delta * 1.2, 0.0, 1.0))

	# Battery: the heater drains it; solar cells recharge it in clear sunlight
	var rate := -DRAIN * (STORM_DRAIN_FACTOR if _in_storm() else 1.0)
	var sunlit := is_sunlit(pos)
	if sunlit and not _in_storm():
		rate += SOLAR_CHARGE
	_battery = clampf(_battery + rate * delta, -1.0, 100.0)
	var b01 := clampf(_battery / 100.0, 0.0, 1.0)
	set_meter("battery", "SUIT HEATER BATTERY", b01, Color(1.0, 0.3, 0.2).lerp(Color(0.4, 1.0, 0.5), b01),
		"%d%%  %s" % [int(maxf(_battery, 0.0)), "☀ charging" if (sunlit and not _in_storm()) else ("🌪 storm" if _in_storm() else "")])
	set_meter("samples", "SAMPLES", float(_samples) / 4.0, Color(1.0, 0.7, 0.3), "%d/4" % _samples)

	# Detector: distance to the nearest undug/unsampled spot
	var nearest := INF
	for site in _pois:
		if site["done"]:
			continue
		var p : Vector3 = (site["node"] as Node3D).global_transform.origin
		var d := p.distance_to(pos)
		nearest = minf(nearest, d)
		# Reveal the marker when close enough
		(site["node"] as Node3D).visible = d < REVEAL_RANGE
	if nearest < INF and _samples < 4 and not _analysis_started:
		var strength := 0.0 if _in_storm() else clampf(1.0 - nearest / DETECTOR_RANGE, 0.0, 1.0)
		set_meter("detector", "DETECTOR" + (" - JAMMED" if _in_storm() else ""), strength, Color(0.4, 0.9, 1.0),
			"%d m" % int(nearest) if not _in_storm() else "")
	else:
		remove_meter("detector")

	var analysis_progress := scan_progress_now() if _analysis_started else -1.0
	if analysis_progress >= 0.0:
		set_meter("analysis", "BIOSIGNATURE ANALYSIS", analysis_progress, Color(0.7, 1.0, 0.5))
	else:
		remove_meter("analysis")

	var step := "→ Follow the detector, then DIG the marked spot (mouse / trigger)."
	if _samples >= 4:
		step = "→ Return to the lander and hold still for the biosignature analysis."
	set_objective("Pressure 0.006 bar  |  -63 °C avg  |  CO₂ 95%%\n%s" % step)

	if _battery <= 0.0:
		lose("Your heater battery died in the Martian cold. At about -63 °C (and a near-vacuum), you can't survive without power.")


func _on_dig_done(site: Dictionary) -> void:
	var pos : Vector3 = (site["node"] as Node3D).global_transform.origin
	var def : Dictionary = site["data"]
	toast("⛏ Dust cleared - collect the sample.", 3.0)
	spawn_pickup(def["kind"], pos, def["color"], def["name"], def)


func _on_pickup(p: Dictionary) -> void:
	_samples += 1
	score = _samples
	score_changed.emit(score)
	var def : Dictionary = p["data"]
	toast("🔬 %s: %s" % [p["label"], def.get("result", "")], 8.0)
	if _samples >= 4:
		_begin_analysis()


func _begin_analysis() -> void:
	_analysis_started = true
	var ship := game.get_ship()
	var pos := ground_point(ship.global_transform.origin)
	_analysis = add_scan_site(pos, 9.0, 8.0, Color(0.6, 1.0, 0.45), "BIOSIGNATURE ANALYSIS")
	toast("All samples collected. Return to the lander - the on-board lab will run the biosignature analysis.", 6.0)


func _on_scan_done(site: Dictionary) -> void:
	if site == _analysis:
		win("Analysis: organic-carbon traces and cycling methane - tantalizing but not proof. Only samples returned to Earth can settle whether Mars ever had microbial life.")


func objective_position() -> Vector3:
	if _samples >= 4 and _analysis_started:
		return (_analysis["node"] as Node3D).global_transform.origin
	var pos := player_pos()
	var best := Vector3.INF
	var best_d := INF
	for site in _pois:
		if site["done"]:
			continue
		var p : Vector3 = (site["node"] as Node3D).global_transform.origin
		var d := p.distance_to(pos)
		if d < best_d:
			best_d = d
			best = p
	if best != Vector3.INF and not _in_storm():
		return best
	# Storm: the detector is jammed; still point to the nearest sample lying on the ground
	var pickup := nearest_pickup_position()
	if pickup != Vector3.INF:
		return pickup
	return best if best != Vector3.INF else Vector3.INF


func objective_action() -> String:
	if _samples >= 4:
		return "analyze"
	if nearest_pickup_position() != Vector3.INF:
		return "collect"
	return "dig"


func _debrief_facts() -> PackedStringArray:
	return PackedStringArray([
		"Mars's air is 95% carbon dioxide but only about 0.6% of Earth's pressure. Liquid water can't stay stable on the surface, and humans need a pressure suit.",
		"It is cold: about -63 °C on average, from -140 °C at the poles in winter to +20 °C on a summer day - which is why your heater battery was your lifeline.",
		"Hematite spheres, clay minerals and dry river deltas are strong evidence that liquid water flowed on ancient Mars, 3-4 billion years ago - a key ingredient for life.",
		"Water ice survives today in the polar caps and under the dust. Mars also has Olympus Mons, the tallest volcano in the Solar System (about 22 km high).",
		"Global dust storms can cover the whole planet for weeks. Whether microbes ever lived on Mars is still unknown - rovers like Perseverance are caching samples to return to Earth.",
	])


func _fail_facts() -> PackedStringArray:
	return PackedStringArray([
		"At about -63 °C your suit heater is essential; solar cells only charge it in clear sunlight - and dust storms cut that off and make the heater work harder.",
		"Plan the route: keep to sunlight between digs, and ride out storms near a sample rather than crossing open ground.",
	])
