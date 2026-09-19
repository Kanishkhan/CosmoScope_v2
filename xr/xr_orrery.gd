# The AR tabletop Solar System ("orrery").
#
# The real Solar System is far too big to put on a table (and OpenXR clamps XROrigin3D.world_scale
# to 1000, so it cannot simply be shrunk), so in AR the rig shows a small, live model of it:
# every planet uses the SAME procedural body/ring meshes and materials as the real one, spins
# with the real spin, sits on the real side of its orbit and moves with the real orbit progress.
# Distances and sizes are compressed so all eight planets are visible and pointable at once.
# A marker shows where your ship is. Everything is drawn on its own visual layer, and the AR
# camera only renders that layer, so the real-size world does not get in the way of passthrough.
#
# Real bodies keep running underneath (physics, ship, fast travel are untouched).
extends Node3D

const StellarBody = preload("../solar_system/stellar_body.gd")
const SolarSystemSetup = preload("../solar_system/solar_system_setup.gd")

## Visual layer used by the orrery and the rig's own visuals (bit 20 of 20)
const LAYER := 1 << 19

const SUN_DISPLAY_RADIUS := 0.075 # metres, before user scale
const FIRST_ORBIT := 0.34
const ORBIT_STEP := 0.15
const MOON_ORBIT := 0.1
const MIN_PICK_RADIUS := 0.035 # metres, before user scale

var _game : SolarSystem
var _entries : Array[Dictionary] = []
var _planet_orbit_radius := {} # StellarBody -> display orbit radius
var _real_distances := PackedFloat32Array()
var _display_distances := PackedFloat32Array()
var _ship_marker : MeshInstance3D
var _built := false
var _sun_entry := {}


func setup(game: SolarSystem) -> void:
	_game = game


func is_built() -> bool:
	return _built


func get_user_scale() -> float:
	return scale.x


func set_user_scale(s: float) -> void:
	scale = Vector3.ONE * s


## Builds the model once every real body exists. Safe to call every frame until it returns true.
func try_build() -> bool:
	if _built:
		return true
	var count := _game.get_stellar_body_count()
	if count == 0:
		return false
	for i in count:
		var b : StellarBody = _game.get_stellar_body(i)
		if b.node == null:
			return false
		if b.type != StellarBody.TYPE_SUN and b.node.get_node_or_null("PlanetBody") == null:
			return false

	# Planets ordered by real distance to the Sun get evenly spaced display orbits
	var planets : Array[StellarBody] = []
	for i in count:
		var b : StellarBody = _game.get_stellar_body(i)
		if b.type != StellarBody.TYPE_SUN and b.parent_id == 0:
			planets.append(b)
	planets.sort_custom(func(a, b): return a.distance_to_parent < b.distance_to_parent)
	_real_distances.append(0.0)
	_display_distances.append(SUN_DISPLAY_RADIUS)
	for rank in planets.size():
		var r := FIRST_ORBIT + ORBIT_STEP * rank
		_planet_orbit_radius[planets[rank]] = r
		_real_distances.append(planets[rank].distance_to_parent)
		_display_distances.append(r)
		_add_orbit_line(r)
	# Beyond the last planet: keep going in a straight line so far away ships still map somewhere
	_real_distances.append(planets[planets.size() - 1].distance_to_parent * 2.0)
	_display_distances.append(FIRST_ORBIT + ORBIT_STEP * (planets.size() + 1))

	for i in count:
		_entries.append(_build_entry(_game.get_stellar_body(i)))
	for e in _entries:
		if e["body"].type == StellarBody.TYPE_SUN:
			_sun_entry = e

	_ship_marker = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.008
	sphere.height = 0.016
	_ship_marker.mesh = sphere
	_ship_marker.material_override = _unshaded(Color(1.0, 0.5, 0.1), false)
	_ship_marker.name = "ShipMarker"
	add_child(_ship_marker)
	_set_layers(_ship_marker)

	_built = true
	update_layout()
	return true


static func _display_radius(body: StellarBody) -> float:
	if body.type == StellarBody.TYPE_SUN:
		return SUN_DISPLAY_RADIUS
	# Sizes are compressed: still clearly ordered (Jupiter > Earth > Mercury) but all visible
	return 0.019 * pow(body.radius / 900.0, 0.85)


static func _unshaded(color: Color, no_depth: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.no_depth_test = no_depth
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _set_layers(n: Node) -> void:
	if n is VisualInstance3D:
		n.layers = LAYER
	if n is GeometryInstance3D:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_set_layers(c)


func _build_entry(body: StellarBody) -> Dictionary:
	var root := Node3D.new()
	root.name = "Orrery_" + body.name
	add_child(root)
	var disp := _display_radius(body)
	var entry := {"body": body, "root": root, "radius": disp, "materials": []}

	if body.type == StellarBody.TYPE_SUN:
		var mi := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = disp
		mesh.height = disp * 2.0
		mi.mesh = mesh
		mi.material_override = SolarSystemSetup.SunMaterial
		root.add_child(mi)
	else:
		# Reuse the real planet body (same mesh + material, so the same colours/bands/clouds),
		# scaled down to its display size. The material is duplicated so the sun direction can be
		# set for the model independently of the real world.
		var real_body : MeshInstance3D = body.node.get_node("PlanetBody")
		var copy := real_body.duplicate() as MeshInstance3D
		copy.visible = true
		var scale_factor := disp / body.radius
		copy.scale = Vector3.ONE * scale_factor
		var mat := real_body.material_override.duplicate() as ShaderMaterial
		copy.material_override = mat
		entry["materials"].append(mat)
		root.add_child(copy)
		var real_rings := body.node.get_node_or_null("Rings") as MeshInstance3D
		if real_rings != null:
			var rings := real_rings.duplicate() as MeshInstance3D
			rings.scale = Vector3.ONE * scale_factor
			var rmat := real_rings.material_override.duplicate() as ShaderMaterial
			rings.material_override = rmat
			entry["materials"].append(rmat)
			root.add_child(rings)

	var label := Label3D.new()
	label.text = body.name
	label.font_size = 40
	label.pixel_size = 0.0005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.outline_size = 8
	label.position = Vector3(0, disp * 1.5 + 0.02, 0)
	root.add_child(label)

	_set_layers(root)
	return entry


func _add_orbit_line(radius: float) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 97:
		var a := float(i) / 96.0 * TAU
		im.surface_add_vertex(Vector3(cos(a) * radius, 0.0, sin(a) * radius))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = _unshaded(Color(0.55, 0.65, 0.85, 0.35), false)
	mi.name = "OrbitLine"
	add_child(mi)
	_set_layers(mi)


# Where the real body is, mapped to the model (in the orrery's own unscaled space)
func _display_position(body: StellarBody) -> Vector3:
	var sun_pos : Vector3 = _game.get_stellar_body(0).node.global_transform.origin
	if body.type == StellarBody.TYPE_SUN:
		return Vector3.ZERO
	var parent : StellarBody = _game.get_stellar_body(body.parent_id)
	if parent.type == StellarBody.TYPE_SUN:
		var v : Vector3 = body.node.global_transform.origin - sun_pos
		var flat := Vector2(v.x, v.z)
		if flat.length() < 0.001:
			flat = Vector2(1, 0)
		flat = flat.normalized() * float(_planet_orbit_radius.get(body, FIRST_ORBIT))
		return Vector3(flat.x, 0.0, flat.y)
	# A moon: a small circle around its planet
	var pv : Vector3 = body.node.global_transform.origin - parent.node.global_transform.origin
	var pflat := Vector2(pv.x, pv.z)
	if pflat.length() < 0.001:
		pflat = Vector2(1, 0)
	pflat = pflat.normalized() * MOON_ORBIT
	return _display_position(parent) + Vector3(pflat.x, 0.0, pflat.y)


func _map_distance(real: float) -> float:
	for i in range(1, _real_distances.size()):
		if real <= _real_distances[i]:
			var t := inverse_lerp(_real_distances[i - 1], _real_distances[i], real)
			return lerpf(_display_distances[i - 1], _display_distances[i], t)
	return _display_distances[_display_distances.size() - 1]


func _ship_display_position() -> Vector3:
	var ship : Ship = _game.get_ship()
	if ship == null:
		return Vector3.ZERO
	var ship_pos : Vector3 = ship.global_transform.origin
	# Close to a body: hover around it in the model
	var best : Dictionary = {}
	var best_ratio := INF
	for e in _entries:
		var b : StellarBody = e["body"]
		if b.type == StellarBody.TYPE_SUN:
			continue
		var d := ship_pos.distance_to(b.node.global_transform.origin)
		var ratio := d / b.radius
		if ratio < best_ratio:
			best_ratio = ratio
			best = e
	if best_ratio < 12.0:
		var b : StellarBody = best["body"]
		var off : Vector3 = (ship_pos - b.node.global_transform.origin) / (12.0 * b.radius)
		return _display_position(b) + off * (float(best["radius"]) * 5.0)
	var sun_pos : Vector3 = _game.get_stellar_body(0).node.global_transform.origin
	var v := ship_pos - sun_pos
	var d := v.length()
	var flat := Vector2(v.x, v.z)
	if flat.length() < 0.001:
		flat = Vector2(1, 0)
	var radius := _map_distance(d)
	flat = flat.normalized() * radius
	return Vector3(flat.x, clampf(v.y / maxf(d, 1.0), -1.0, 1.0) * 0.15, flat.y)


## Call every frame while shown.
func update_layout() -> void:
	if not _built:
		return
	var sun_global := global_transform * Vector3.ZERO
	for e in _entries:
		var b : StellarBody = e["body"]
		var root : Node3D = e["root"]
		root.position = _display_position(b)
		# Real spin (about the vertical axis) so the surface turns like the real planet
		root.basis = b.node.global_transform.basis.orthonormalized()
	_ship_marker.position = _ship_display_position()
	# Light every model planet from the model's Sun
	for e in _entries:
		if e["body"].type == StellarBody.TYPE_SUN:
			continue
		var root : Node3D = e["root"]
		var dir := (sun_global - root.global_transform.origin).normalized()
		for m in e["materials"]:
			m.set_shader_parameter(&"sun_direction", dir)


## The body whose model the ray (world space) hits, or null. Small planets get a forgiving radius.
func pick(origin: Vector3, dir: Vector3) -> StellarBody:
	var best : StellarBody = null
	var best_t := INF
	for e in _entries:
		var root : Node3D = e["root"]
		var center := root.global_transform.origin
		var t := (center - origin).dot(dir)
		if t < 0.0:
			continue
		var miss := (center - (origin + dir * t)).length()
		var r := maxf(float(e["radius"]), MIN_PICK_RADIUS) * scale.x * 1.3
		if miss <= r and t < best_t:
			best_t = t
			best = e["body"]
	return best


func get_display_center(body: StellarBody) -> Vector3:
	for e in _entries:
		if e["body"] == body:
			return (e["root"] as Node3D).global_transform.origin
	return global_transform.origin


func get_display_radius(body: StellarBody) -> float:
	for e in _entries:
		if e["body"] == body:
			return float(e["radius"]) * scale.x
	return 0.0
