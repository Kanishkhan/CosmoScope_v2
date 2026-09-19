extends "res://missions/mission_base.gd"
# 🌍 EARTH - "Planet of Life"
#
# The science you experience: Earth is the only planet where you can simply breathe and walk
# around - so this mission has no suit meters, no heat, no pressure. Instead you run a field survey
# of the three spheres of life: BIOSPHERE (plants), HYDROSPHERE (water) and ATMOSPHERE (air).
# Samples are picked up in three different zones, but you can only carry 3 at a time, so you shuttle
# them back to the field lab. Each sphere the lab completes unlocks a real explanation - and
# completing the hydrosphere sets the water cycle in motion above the lab (evaporation, cloud, rain).

const CAPACITY := 3
const TIME_LIMIT := 420.0
const LAB_RADIUS := 6.5

var _lab_pos := Vector3.ZERO
var _lab_node : Node3D
var _deposited := {"crystal": 0, "flask": 0, "canister": 0}
var _cloud : MeshInstance3D
var _rain : Array[MeshInstance3D] = []
var _cycle_t := -1.0
var _full_toast := 0.0


func _mission_title() -> String:
	return "🌍 EARTH - PLANET OF LIFE"


func _mission_intro() -> String:
	return "No suit needed here - that's the point. Survey Earth's biosphere, hydrosphere and atmosphere: collect 6 samples (carry max 3) and deliver them to the field lab."


func _on_start() -> void:
	var origin := player_pos()
	var base := _rng.randf() * TAU
	_lab_pos = point_around(origin, base + 0.3, 11.0)
	_make_lab()

	var zones := [
		{"name": "MEADOW - vegetation", "angle": base + 1.4, "dist": 55.0, "kind": "crystal",
			"color": Color(0.4, 1.0, 0.4), "label": "Seed pod"},
		{"name": "COASTAL BASIN - water", "angle": base + 3.5, "dist": 62.0, "kind": "flask",
			"color": Color(0.35, 0.65, 1.0), "label": "Water sample"},
		{"name": "HIGH RIDGE - air", "angle": base + 5.3, "dist": 74.0, "kind": "canister",
			"color": Color(0.85, 0.95, 1.0), "label": "Air sample"},
	]
	for z in zones:
		var center := point_around(origin, z["angle"], z["dist"])
		# A sign for the zone so you feel the different environments
		var sign_root := Node3D.new()
		var tag := _label3d(z["name"], 56)
		tag.position = Vector3(0, 9.0, 0)
		sign_root.add_child(tag)
		add_world_node(sign_root, center, up_at(center))
		for i in 2:
			var p := point_around(center, TAU * float(i) / 2.0 + 0.6, 5.0)
			spawn_pickup(z["kind"], p, z["color"], z["label"])


func _make_lab() -> void:
	var root := Node3D.new()
	root.name = "FieldLab"
	var base_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.0
	cyl.bottom_radius = 3.2
	cyl.height = 0.8
	base_mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.84, 0.9)
	mat.metallic = 0.4
	base_mesh.material_override = mat
	base_mesh.position = Vector3(0, 0.4, 0)
	root.add_child(base_mesh)
	var cabin := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(3.6, 2.6, 3.0)
	cabin.mesh = bx
	cabin.material_override = mat
	cabin.position = Vector3(0, 2.1, 0)
	root.add_child(cabin)
	var dish := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.1
	sph.height = 1.1
	dish.mesh = sph
	dish.material_override = mat
	dish.position = Vector3(0, 4.0, 0)
	root.add_child(dish)
	var pad := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = LAB_RADIUS
	disc.bottom_radius = LAB_RADIUS
	disc.height = 0.1
	pad.mesh = disc
	pad.material_override = _material(Color(0.4, 1.0, 0.55), 0.3)
	pad.position = Vector3(0, 0.1, 0)
	root.add_child(pad)
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.1
	bm.bottom_radius = 0.6
	bm.height = 45.0
	beam.mesh = bm
	beam.position = Vector3(0, 22.5, 0)
	beam.material_override = _material(Color(0.4, 1.0, 0.55), 0.25)
	root.add_child(beam)
	var tag := _label3d("FIELD LAB - deliver samples", 48)
	tag.position = Vector3(0, 7.0, 0)
	root.add_child(tag)
	add_world_node(root, _lab_pos, up_at(_lab_pos))
	_lab_node = root


func _can_pickup(_pickup: Dictionary) -> bool:
	if carried_count() < CAPACITY:
		return true
	_full_toast -= get_physics_process_delta_time()
	if _full_toast <= 0.0:
		toast("🎒 You can only carry %d samples - deliver them to the lab first." % CAPACITY, 3.0)
		_full_toast = 3.0
	return false


func _on_tick(delta: float) -> void:
	var pos := player_pos()

	# Deliver everything you carry when you reach the lab
	if carried_count() > 0 and pos.distance_to(_lab_pos) <= LAB_RADIUS:
		_deliver()

	_animate_water_cycle(delta)

	var left := TIME_LIMIT - _elapsed
	set_meter("time", "FIELD TIME", left / TIME_LIMIT, Color(0.5, 0.8, 1.0), "%d s" % int(maxf(left, 0.0)))
	set_meter("bio", "🌱 BIOSPHERE", float(_deposited["crystal"]) / 2.0, Color(0.4, 1.0, 0.4), "%d/2" % _deposited["crystal"])
	set_meter("hydro", "💧 HYDROSPHERE", float(_deposited["flask"]) / 2.0, Color(0.35, 0.65, 1.0), "%d/2" % _deposited["flask"])
	set_meter("atmo", "☁ ATMOSPHERE", float(_deposited["canister"]) / 2.0, Color(0.85, 0.95, 1.0), "%d/2" % _deposited["canister"])
	set_objective("Air: 21%% O₂ / 78%% N₂  |  1.0 bar  |  15 °C  -  breathable, no suit needed\nCarrying %d/%d.  %s" % [
		carried_count(), CAPACITY,
		"→ Deliver to the field lab." if carried_count() >= CAPACITY or remaining_pickups().is_empty()
		else "→ Collect samples from the three zones."])

	if left <= 0.0:
		lose("Time ran out before the survey was complete.")


func _deliver() -> void:
	var names := {"crystal": "Seed pods", "flask": "Water samples", "canister": "Air samples"}
	for kind in ["crystal", "flask", "canister"]:
		var n := carried(kind)
		if n <= 0:
			continue
		var before := int(_deposited[kind])
		_deposited[kind] = mini(before + n, 2)
		if before < 2 and int(_deposited[kind]) >= 2:
			_sphere_complete(kind)
		else:
			toast("🔬 %s delivered (%d/2)" % [names[kind], _deposited[kind]], 3.0)
	clear_inventory()
	score = int(_deposited["crystal"]) + int(_deposited["flask"]) + int(_deposited["canister"])
	score_changed.emit(score)
	if score >= 6:
		win("Habitability index: 100%. Life, liquid water and a protective atmosphere - all three present.")


func _sphere_complete(kind: String) -> void:
	match kind:
		"crystal":
			toast("🌱 BIOSPHERE complete - plants turn sunlight, CO₂ and water into sugar and oxygen (photosynthesis). That is why our air is 21% oxygen.", 8.0)
		"flask":
			toast("💧 HYDROSPHERE complete - 71% of Earth is ocean. Watch the water cycle start: evaporation, cloud, rain.", 8.0)
			_start_water_cycle()
		"canister":
			toast("☁ ATMOSPHERE complete - 78% nitrogen, 21% oxygen. The ozone layer blocks UV and the greenhouse effect keeps the average at 15 °C.", 8.0)


func _start_water_cycle() -> void:
	_cycle_t = 0.0
	_cloud = MeshInstance3D.new()
	_cloud.name = "WaterCycleCloud"
	var sphere := SphereMesh.new()
	sphere.radius = 9.0
	sphere.height = 10.0
	_cloud.mesh = sphere
	_cloud.material_override = _material(Color(0.95, 0.97, 1.0), 0.55, false)
	_cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_world_node(_cloud, _lab_pos + up_at(_lab_pos) * 32.0, up_at(_lab_pos))
	_cloud.scale = Vector3.ONE * 0.05
	for i in 18:
		var drop := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.05
		cm.height = 1.4
		drop.mesh = cm
		drop.material_override = _material(Color(0.5, 0.75, 1.0), 0.7, false)
		drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drop.visible = false
		add_world_node(drop, _lab_pos, up_at(_lab_pos))
		_rain.append(drop)


func _animate_water_cycle(delta: float) -> void:
	if _cycle_t < 0.0 or _cloud == null or not is_instance_valid(_cloud):
		return
	_cycle_t += delta
	# 0-6 s: the cloud condenses; afterwards it rains around the lab, continuously
	_cloud.scale = Vector3.ONE * clampf(_cycle_t / 6.0, 0.05, 1.0)
	if _cycle_t > 6.0:
		var up := up_at(_lab_pos)
		var axes := tangent_axes(up)
		for i in _rain.size():
			var drop := _rain[i]
			drop.visible = true
			var a := float(i) / float(_rain.size()) * TAU
			var r := 2.0 + 7.0 * fmod(float(i) * 0.37, 1.0)
			var fall := fmod(_cycle_t * 14.0 + float(i) * 5.3, 32.0)
			drop.global_position = _lab_pos + (axes[0] * cos(a) + axes[1] * sin(a)) * r + up * (32.0 - fall)


func objective_position() -> Vector3:
	if carried_count() >= CAPACITY or (carried_count() > 0 and remaining_pickups().is_empty()):
		return _lab_pos
	var p := nearest_pickup_position()
	if p != Vector3.INF:
		return p
	return _lab_pos


func objective_action() -> String:
	if carried_count() >= CAPACITY or (carried_count() > 0 and remaining_pickups().is_empty()):
		return "deposit"
	return "walk"


func _debrief_facts() -> PackedStringArray:
	return PackedStringArray([
		"Liquid water: Earth sits in the 'habitable zone' where temperature and pressure let oceans stay liquid - they cover 71% of the surface and drive the water cycle you just watched.",
		"Atmosphere: 78% nitrogen and 21% oxygen let you breathe with no suit. The oxygen exists because photosynthesis by plants and algae has been producing it for billions of years.",
		"Protection: the ozone layer blocks harmful UV, the magnetic field deflects the solar wind, and the greenhouse effect keeps the average temperature near 15 °C instead of −18 °C.",
		"Biodiversity: millions of species from deep-sea vents to mountain ridges - life exists in every environment you sampled, and it shapes the air and the soil.",
		"Compare: Mercury has no air, Venus is too hot, Mars too cold and thin, the Moon airless - Earth is the only place where all the ingredients for life come together.",
	])


func _fail_facts() -> PackedStringArray:
	return PackedStringArray([
		"A field survey needs all three spheres: living things, liquid water and air.",
		"You can carry only %d samples at a time - plan trips between the zones and the lab." % CAPACITY,
	])
