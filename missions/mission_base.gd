extends Node
# Shared framework for the five on-foot science missions (Mercury, Venus, Earth, Mars, Moon).
#
# Each mission is its own script with its own mechanics; this base only provides what they all
# need: the HUD (objective, meters, toasts, carried items, guidance arrow), real pickups that fly
# to the player, "hold to scan" and "dig to sample" sites, terrain placement helpers, the science
# debrief panel and clean-up. A mission only ever reads the character's position and the game
# state, so it works the same with keyboard/mouse, gamepad and XR.

signal mission_won
signal mission_lost
signal score_changed(score: int)

const StellarBody = preload("../solar_system/stellar_body.gd")
const PickupSound = preload("res://sounds/place_waypoint.wav")

const PICKUP_RADIUS := 2.6
const SCAN_DECAY := 1.5

var planet_name := ""
## Text for HUDs that are not the 2D screen (the XR wrist display reads this)
var hud_text := ""
var score := 0

var game : SolarSystem
var character : Node3D
var character_controller : Node
var body : StellarBody

var _finished := false
var _debrief_open := false
var _elapsed := 0.0
var _rng := RandomNumberGenerator.new()
var _spawned : Array[Node] = []
var _pickups : Array[Dictionary] = []
var _scans : Array[Dictionary] = []
var _digs : Array[Dictionary] = []
var _inventory := {}
var _saved_gravity := 1.0

var _layer : CanvasLayer
var _objective_label : Label
var _guide_label : Label
var _toast_label : Label
var _inventory_label : Label
var _meter_box : VBoxContainer
var _meters := {}
var _toast_time := 0.0
var _debrief_panel : Control
var _debrief_button : Button
var _audio : AudioStreamPlayer
var _objective_text := ""


func _init(p_planet_name: String = "") -> void:
	planet_name = p_planet_name


# ─── To override ─────────────────────────────────────────────────────────────

func _mission_title() -> String:
	return planet_name


func _mission_intro() -> String:
	return ""


func _debrief_facts() -> PackedStringArray:
	return PackedStringArray()


## Called once, when the character and the terrain around it exist
func _on_start() -> void:
	pass


## Called every physics frame while the mission runs
func _on_tick(_delta: float) -> void:
	pass


## Where the player should go / dig / scan next (for the guidance arrow), or Vector3.INF
func objective_position() -> Vector3:
	return Vector3.INF


## One word for what to do there: "walk", "dig", "scan", "deposit", "shade", "sun", "look"
func objective_action() -> String:
	return "walk"


func _on_cleanup() -> void:
	pass


# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	game = get_parent().get_parent() as SolarSystem if get_parent() != null else null
	if game == null:
		queue_free()
		return
	character = game.get_character()
	body = game.get_body_under_player()
	if character == null or body == null:
		queue_free()
		return
	character_controller = character.get_node_or_null("Controller")
	_rng.seed = planet_name.hash()
	_saved_gravity = float(character.get("gravity_scale")) if "gravity_scale" in character else 1.0
	_audio = AudioStreamPlayer.new()
	_audio.stream = PickupSound
	add_child(_audio)
	game.reference_body_changed.connect(_on_reference_body_changed)
	if character_controller != null and character_controller.has_signal("dug"):
		character_controller.dug.connect(_on_player_dug)
	_build_hud()
	_on_start()
	toast(_mission_intro(), 7.0)
	_update_hud()


func _exit_tree() -> void:
	_cleanup()


func _cleanup() -> void:
	if character != null and is_instance_valid(character) and "gravity_scale" in character:
		character.set("gravity_scale", _saved_gravity)
	_on_cleanup()
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
		_layer = null


func _on_reference_body_changed(info) -> void:
	# The world was re-centered: keep everything where it was on the ground
	for n in _spawned:
		if is_instance_valid(n) and n is Node3D:
			n.global_transform = info.inverse_transform * n.global_transform


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _debrief_open:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
			confirm_debrief()
			get_viewport().set_input_as_handled()
	elif event.keycode == KEY_BACKSPACE and not _finished:
		_abort("Mission abandoned")


func _input(event: InputEvent) -> void:
	if _debrief_open and event is InputEventJoypadButton and event.pressed \
	and event.button_index == JOY_BUTTON_A:
		confirm_debrief()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _finished:
		return
	if character == null or not is_instance_valid(character):
		_abort("You returned to the ship")
		return
	_elapsed += delta
	_animate_pickups(delta)
	_update_scans(delta)
	_on_tick(delta)
	_update_toast(delta)
	_update_hud()


# ─── Player / terrain helpers ────────────────────────────────────────────────

func player_pos() -> Vector3:
	return character.global_transform.origin


func planet_center() -> Vector3:
	return body.node.global_transform.origin


func up_at(pos: Vector3) -> Vector3:
	return (pos - planet_center()).normalized()


## Two unit vectors spanning the ground plane at `up`
func tangent_axes(up: Vector3) -> Array:
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var t1 := ref.cross(up).normalized()
	var t2 := up.cross(t1).normalized()
	return [t1, t2]


## Point on the real terrain closest (along "up") to `guess`
func ground_point(guess: Vector3) -> Vector3:
	var up := up_at(guess)
	var space := character.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(guess + up * 120.0, guess - up * 250.0)
	query.exclude = [character.get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		return hit.position
	# Terrain collision not streamed in yet: stay at the player's own altitude
	return planet_center() + up * (player_pos() - planet_center()).length()


## Ground point `dist` metres from `origin` in direction `angle` (radians) along the ground
func point_around(origin: Vector3, angle: float, dist: float) -> Vector3:
	var axes := tangent_axes(up_at(origin))
	var dir : Vector3 = (axes[0] * cos(angle) + axes[1] * sin(angle)).normalized()
	return ground_point(origin + dir * dist)


func basis_up(up: Vector3) -> Basis:
	var axes := tangent_axes(up)
	var right : Vector3 = axes[0]
	return Basis(right, up, right.cross(up)).orthonormalized()


func add_world_node(n: Node3D, pos: Vector3, up: Vector3) -> void:
	game.add_child(n)
	n.global_transform = Transform3D(basis_up(up), pos)
	_spawned.append(n)


func sun_position() -> Vector3:
	return game.get_stellar_body(0).node.global_transform.origin


## True if the sun shines on `pos` (not night, not shadowed by terrain or anything solid nearby)
func is_sunlit(pos: Vector3) -> bool:
	var up := up_at(pos)
	var to_sun := (sun_position() - pos).normalized()
	if up.dot(to_sun) < 0.02:
		return false
	var space := character.get_world_3d().direct_space_state
	var from := pos + up * 1.2
	var query := PhysicsRayQueryParameters3D.create(from, from + to_sun * 80.0)
	query.exclude = [character.get_rid()]
	return space.intersect_ray(query).is_empty()


func sun_elevation_deg(pos: Vector3) -> float:
	var up := up_at(pos)
	return rad_to_deg(asin(clampf(up.dot((sun_position() - pos).normalized()), -1.0, 1.0)))


func _material(color: Color, alpha := 1.0, emissive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emissive:
		m.emission_enabled = true
		m.emission = color
	return m


func _label3d(text: String, size := 64) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.02
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.shaded = false
	l.outline_size = 10
	return l


# ─── Pickups ─────────────────────────────────────────────────────────────────

## Creates a real, visible item lying on the ground. Walk into it to pick it up: it flies to the
## suit, the inventory shows it and `_on_pickup(kind, data)` runs.
## kind: "crystal", "canister", "case", "flask", "core", "probe"
func spawn_pickup(kind: String, pos: Vector3, color: Color, label: String, data := {}) -> Dictionary:
	var up := up_at(pos)
	var root := Node3D.new()
	root.name = "Pickup_" + kind
	var item := Node3D.new()
	item.name = "Item"
	item.position = up * 0.0
	root.add_child(item)

	var mat := _material(color)
	match kind:
		"crystal":
			var m := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = 0.55
			s.height = 1.5
			s.radial_segments = 6
			s.rings = 3
			m.mesh = s
			m.material_override = mat
			item.add_child(m)
		"canister", "flask":
			var body_mesh := MeshInstance3D.new()
			if kind == "canister":
				var c := CylinderMesh.new()
				c.top_radius = 0.32
				c.bottom_radius = 0.32
				c.height = 1.1
				body_mesh.mesh = c
			else:
				var s2 := SphereMesh.new()
				s2.radius = 0.5
				s2.height = 1.0
				body_mesh.mesh = s2
			body_mesh.material_override = mat
			item.add_child(body_mesh)
			var cap := MeshInstance3D.new()
			var cc := CylinderMesh.new()
			cc.top_radius = 0.16
			cc.bottom_radius = 0.2
			cc.height = 0.5
			cap.mesh = cc
			cap.position = Vector3(0, 0.75, 0)
			cap.material_override = _material(Color(0.9, 0.9, 0.95), 1.0, false)
			item.add_child(cap)
		"case", "probe", "core":
			var b := MeshInstance3D.new()
			var bx := BoxMesh.new()
			bx.size = Vector3(0.9, 0.6, 0.6) if kind != "core" else Vector3(0.5, 0.9, 0.5)
			b.mesh = bx
			b.material_override = mat
			item.add_child(b)
			var band := MeshInstance3D.new()
			var bb := BoxMesh.new()
			bb.size = Vector3(0.95, 0.12, 0.65) if kind != "core" else Vector3(0.55, 0.12, 0.55)
			band.mesh = bb
			band.position = Vector3(0, 0.15, 0)
			band.material_override = _material(Color(1, 1, 1), 1.0, false)
			item.add_child(band)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.0
	light.omni_range = 9.0
	light.shadow_enabled = false
	item.add_child(light)

	# A faint beam so it can be seen from far away
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.08
	bm.bottom_radius = 0.5
	bm.height = 40.0
	beam.mesh = bm
	beam.position = Vector3(0, 20.0, 0)
	beam.material_override = _material(color, 0.28)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)

	var tag := _label3d(label, 40)
	tag.position = Vector3(0, 3.2, 0)
	root.add_child(tag)

	add_world_node(root, pos, up)
	var entry := {"kind": kind, "node": root, "item": item, "label": label, "data": data,
		"collected": false, "fly": 0.0, "phase": _rng.randf() * TAU, "color": color, "base_y": 1.3}
	_pickups.append(entry)
	return entry


func _animate_pickups(delta: float) -> void:
	var pos := player_pos()
	for p in _pickups:
		if p["collected"]:
			continue
		var item : Node3D = p["item"]
		p["phase"] += delta * 2.2
		item.position = Vector3(0, float(p["base_y"]) + sin(p["phase"]) * 0.25, 0)
		item.rotate_y(delta * 1.5)
		if not is_instance_valid(p["node"]) or not (p["node"] as Node3D).visible:
			continue
		if (p["node"] as Node3D).global_transform.origin.distance_to(pos) <= PICKUP_RADIUS \
		and _can_pickup(p):
			_collect(p)
	# Collected items fly into the suit, then vanish
	for p in _pickups:
		if p["collected"] and float(p["fly"]) < 1.0 and is_instance_valid(p["node"]):
			p["fly"] = minf(float(p["fly"]) + delta / 0.4, 1.0)
			var node : Node3D = p["node"]
			var start : Vector3 = p["fly_from"]
			var target := player_pos() + up_at(player_pos()) * 1.2
			node.global_position = start.lerp(target, ease(float(p["fly"]), 0.4))
			node.scale = Vector3.ONE * (1.0 - float(p["fly"]) * 0.8)
			if float(p["fly"]) >= 1.0:
				node.queue_free()


func _can_pickup(_pickup: Dictionary) -> bool:
	return true


func _collect(p: Dictionary) -> void:
	p["collected"] = true
	p["fly"] = 0.0
	p["fly_from"] = (p["node"] as Node3D).global_transform.origin + up_at(player_pos()) * 1.3
	_audio.play()
	_inventory[p["kind"]] = int(_inventory.get(p["kind"], 0)) + 1
	_on_pickup(p)


func _on_pickup(_pickup: Dictionary) -> void:
	pass


func remaining_pickups(kind := "") -> Array[Dictionary]:
	var out : Array[Dictionary] = []
	for p in _pickups:
		if not p["collected"] and (kind == "" or p["kind"] == kind):
			out.append(p)
	return out


func carried_count() -> int:
	var n := 0
	for k in _inventory:
		n += int(_inventory[k])
	return n


func carried(kind: String) -> int:
	return int(_inventory.get(kind, 0))


func clear_inventory() -> void:
	_inventory.clear()


func nearest_pickup_position(kind := "") -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for p in remaining_pickups(kind):
		var pos := (p["node"] as Node3D).global_transform.origin
		var d := pos.distance_to(player_pos())
		if d < best_d:
			best_d = d
			best = pos
	return best


# ─── Scan sites (stand inside and hold still for a while) ────────────────────

func add_scan_site(pos: Vector3, radius: float, seconds: float, color: Color, label: String,
		data := {}) -> Dictionary:
	var up := up_at(pos)
	var root := Node3D.new()
	root.name = "ScanSite"
	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.12
	ring.mesh = disc
	ring.position = Vector3(0, 0.1, 0)
	ring.material_override = _material(color, 0.28)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var fill := MeshInstance3D.new()
	var fd := CylinderMesh.new()
	fd.top_radius = radius
	fd.bottom_radius = radius
	fd.height = 0.16
	fill.mesh = fd
	fill.position = Vector3(0, 0.14, 0)
	fill.material_override = _material(color, 0.55)
	fill.scale = Vector3(0.01, 1.0, 0.01)
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fill)
	var pillar := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.1
	pm.bottom_radius = 0.4
	pm.height = 35.0
	pillar.mesh = pm
	pillar.position = Vector3(0, 17.5, 0)
	pillar.material_override = _material(color, 0.22)
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pillar)
	var tag := _label3d(label, 40)
	tag.position = Vector3(0, 3.5, 0)
	root.add_child(tag)
	add_world_node(root, pos, up)
	var site := {"pos": pos, "node": root, "fill": fill, "radius": radius, "seconds": seconds,
		"progress": 0.0, "done": false, "data": data, "label": label, "active": true}
	_scans.append(site)
	return site


## Overridden by missions that make scanning conditional (e.g. only while not erupting)
func _scan_allowed(_site: Dictionary) -> bool:
	return true


func _update_scans(delta: float) -> void:
	var pos := player_pos()
	for s in _scans:
		if s["done"] or not s["active"]:
			continue
		var node : Node3D = s["node"]
		if not is_instance_valid(node):
			continue
		var inside := (node.global_transform.origin as Vector3).distance_to(pos) <= float(s["radius"]) \
			and _scan_allowed(s)
		if inside:
			s["progress"] = minf(float(s["progress"]) + delta, float(s["seconds"]))
		else:
			s["progress"] = maxf(float(s["progress"]) - delta * SCAN_DECAY, 0.0)
		var t := float(s["progress"]) / float(s["seconds"])
		(s["fill"] as Node3D).scale = Vector3(maxf(t, 0.01), 1.0, maxf(t, 0.01))
		if t >= 1.0:
			s["done"] = true
			_audio.play()
			_on_scan_done(s)
			if is_instance_valid(node):
				node.visible = false


func _on_scan_done(_site: Dictionary) -> void:
	pass


## Fraction (0..1) of the scan the player is currently making progress on, or -1
func scan_progress_now() -> float:
	var pos := player_pos()
	for s in _scans:
		if not s["done"] and s["active"] and is_instance_valid(s["node"]) \
		and (s["node"] as Node3D).global_transform.origin.distance_to(pos) <= float(s["radius"]):
			return float(s["progress"]) / float(s["seconds"])
	return -1.0


# ─── Dig sites (use the real digging tool on the marked spot) ────────────────

func add_dig_site(pos: Vector3, radius: float, color: Color, label: String, data := {}) -> Dictionary:
	var up := up_at(pos)
	var root := Node3D.new()
	root.name = "DigSite"
	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.1
	ring.mesh = disc
	ring.position = Vector3(0, 0.1, 0)
	ring.material_override = _material(color, 0.3)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	for i in 2:
		var bar := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(radius * 1.6, 0.14, 0.5)
		bar.mesh = bb
		bar.rotation.y = PI * 0.25 + PI * 0.5 * i
		bar.position = Vector3(0, 0.2, 0)
		bar.material_override = _material(color, 0.9)
		root.add_child(bar)
	var pillar := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.1
	pm.bottom_radius = 0.4
	pm.height = 35.0
	pillar.mesh = pm
	pillar.position = Vector3(0, 17.5, 0)
	pillar.material_override = _material(color, 0.22)
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pillar)
	var tag := _label3d(label + "\nDIG (mouse / trigger)", 36)
	tag.position = Vector3(0, 3.5, 0)
	root.add_child(tag)
	add_world_node(root, pos, up)
	var site := {"pos": pos, "node": root, "radius": radius, "done": false, "data": data,
		"label": label, "active": true, "color": color}
	_digs.append(site)
	return site


func _on_player_dug(hit_position: Vector3) -> void:
	if _finished:
		return
	for d in _digs:
		if d["done"] or not d["active"] or not is_instance_valid(d["node"]):
			continue
		var node : Node3D = d["node"]
		if node.global_transform.origin.distance_to(hit_position) <= float(d["radius"]):
			d["done"] = true
			node.visible = false
			_audio.play()
			_on_dig_done(d)
			return


func _on_dig_done(_site: Dictionary) -> void:
	pass


# ─── HUD ─────────────────────────────────────────────────────────────────────

func _build_hud() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 50
	add_child(_layer)

	_objective_label = Label.new()
	_objective_label.add_theme_font_size_override("font_size", 20)
	_objective_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	_objective_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_objective_label.add_theme_constant_override("shadow_offset_x", 2)
	_objective_label.add_theme_constant_override("shadow_offset_y", 2)
	_objective_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_objective_label.offset_left = -380.0
	_objective_label.offset_right = 380.0
	_objective_label.offset_top = -170.0
	_objective_label.offset_bottom = -30.0
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_objective_label)

	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", 22)
	_toast_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_toast_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_toast_label.add_theme_constant_override("outline_size", 6)
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_label.offset_left = -420.0
	_toast_label.offset_right = 420.0
	_toast_label.offset_top = 150.0
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_toast_label)

	_guide_label = Label.new()
	_guide_label.add_theme_font_size_override("font_size", 18)
	_guide_label.add_theme_color_override("font_color", Color(0.6, 0.95, 1.0))
	_guide_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_guide_label.add_theme_constant_override("outline_size", 5)
	_guide_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_guide_label.offset_left = -300.0
	_guide_label.offset_right = 300.0
	_guide_label.offset_top = 96.0
	_guide_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guide_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_guide_label)

	var side := VBoxContainer.new()
	side.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	side.offset_left = -290.0
	side.offset_right = -14.0
	side.offset_top = -40.0
	side.offset_bottom = 200.0
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(side)
	_meter_box = VBoxContainer.new()
	_meter_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(_meter_box)
	_inventory_label = Label.new()
	_inventory_label.add_theme_font_size_override("font_size", 16)
	_inventory_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	_inventory_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_inventory_label.add_theme_constant_override("outline_size", 4)
	_inventory_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(_inventory_label)


## Adds or updates a meter. `value` is 0..1. `text` is shown next to the name.
func set_meter(id: String, label: String, value: float, color: Color, text := "") -> void:
	if _meter_box == null:
		return
	var m : Dictionary = _meters.get(id, {})
	if m.is_empty():
		var row := VBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 4)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(250, 12)
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bar)
		_meter_box.add_child(row)
		m = {"row": row, "label": l, "bar": bar}
		_meters[id] = m
	(m["label"] as Label).text = label if text == "" else "%s   %s" % [label, text]
	(m["bar"] as ProgressBar).value = clampf(value, 0.0, 1.0)
	(m["bar"] as ProgressBar).modulate = color


func remove_meter(id: String) -> void:
	var m : Dictionary = _meters.get(id, {})
	if not m.is_empty():
		(m["row"] as Node).queue_free()
		_meters.erase(id)


func set_objective(text: String) -> void:
	_objective_text = text


func toast(text: String, seconds := 4.0) -> void:
	if _toast_label == null or text == "":
		return
	_toast_label.text = text
	_toast_time = seconds


func _update_toast(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast_label.text = ""


func _update_hud() -> void:
	if _objective_label == null or _finished:
		return
	var lines := PackedStringArray()
	lines.append(_mission_title())
	lines.append(_objective_text)
	lines.append("[Backspace] abort mission")
	_objective_label.text = "\n".join(lines)

	var carried_text := PackedStringArray()
	for k in _inventory:
		if int(_inventory[k]) > 0:
			carried_text.append("%s x%d" % [k, int(_inventory[k])])
	_inventory_label.text = "Carrying: " + ", ".join(carried_text) if not carried_text.is_empty() else ""

	# Guidance
	var target := objective_position()
	if target != Vector3.INF and character != null:
		var d := player_pos().distance_to(target)
		var arrow := _bearing_arrow(target)
		_guide_label.text = "%s  %s  %d m" % [arrow, objective_action().to_upper(), int(d)]
	else:
		_guide_label.text = ""

	var meter_text := PackedStringArray()
	for id in _meters:
		meter_text.append((_meters[id]["label"] as Label).text)
	hud_text = "%s\n%s\n%s\n%s" % [_mission_title(), _objective_text, "\n".join(meter_text), _guide_label.text]


# Arrow relative to where the player looks (head), like a compass
func _bearing_arrow(target: Vector3) -> String:
	var head := character.get_node_or_null("Head") as Node3D
	if head == null:
		return "•"
	var up := up_at(player_pos())
	var fwd := -head.global_transform.basis.z
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var to_t := target - player_pos()
	to_t = (to_t - up * to_t.dot(up))
	if to_t.length() < 0.5:
		return "◎"
	to_t = to_t.normalized()
	var angle := rad_to_deg(atan2(fwd.cross(to_t).dot(up), fwd.dot(to_t)))
	# angle > 0: target is to the left (right-handed, up axis)
	if absf(angle) < 25.0:
		return "▲"
	if absf(angle) > 155.0:
		return "▼"
	return "◀" if angle > 0.0 else "▶"


# ─── Ending: win / fail / abort ──────────────────────────────────────────────

func win(summary := "") -> void:
	_end(true, summary)


func lose(reason: String) -> void:
	_end(false, reason)


func _end(won: bool, text: String) -> void:
	if _finished:
		return
	_finished = true
	_show_debrief(won, text)


func _abort(reason: String) -> void:
	if _finished:
		return
	_finished = true
	toast(reason, 2.0)
	_close_and_emit(false)


func is_debrief_open() -> bool:
	return _debrief_open


func confirm_debrief() -> void:
	if _debrief_open:
		_close_and_emit(_won)


var _won := false


func _close_and_emit(won: bool) -> void:
	_debrief_open = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if _debrief_panel != null and is_instance_valid(_debrief_panel):
		_debrief_panel.queue_free()
	_cleanup()
	if won:
		mission_won.emit()
	else:
		mission_lost.emit()
	queue_free()


func _show_debrief(won: bool, text: String) -> void:
	_won = won
	_debrief_open = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_objective_label.text = ""
	_guide_label.text = ""

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.06, 0.14, 0.94)
	style.border_color = Color(0.3, 0.85, 0.5, 1.0) if won else Color(1.0, 0.4, 0.3, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 26.0
	style.content_margin_right = 26.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(660, 0)
	panel.offset_left = -330.0
	panel.offset_right = 330.0
	panel.offset_top = -210.0
	panel.offset_bottom = 210.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = ("MISSION COMPLETE" if won else "MISSION FAILED") + "  —  " + _mission_title()
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.5, 1.0, 0.65) if won else Color(1.0, 0.55, 0.45))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)

	if text != "":
		var summary := Label.new()
		summary.text = text
		summary.add_theme_font_size_override("font_size", 16)
		summary.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(summary)

	box.add_child(HSeparator.new())
	var head := Label.new()
	head.text = "WHAT YOU LEARNED" if won else "WHAT WENT WRONG"
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(0.45, 0.8, 1.0))
	box.add_child(head)

	var facts := _debrief_facts() if won else _fail_facts()
	for f in facts:
		var l := Label.new()
		l.text = "•  " + f
		l.add_theme_font_size_override("font_size", 16)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(600, 0)
		box.add_child(l)

	_debrief_button = Button.new()
	_debrief_button.text = "CONTINUE EXPLORING   [Enter / A]"
	_debrief_button.custom_minimum_size = Vector2(0, 44)
	_debrief_button.focus_mode = Control.FOCUS_ALL
	_debrief_button.pressed.connect(confirm_debrief)
	box.add_child(_debrief_button)

	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(panel)
	_debrief_panel = panel
	_debrief_button.grab_focus()

	hud_text = "%s\n%s\nPress A / trigger to continue" % [
		("MISSION COMPLETE" if won else "MISSION FAILED") + " - " + _mission_title(), text]


func _fail_facts() -> PackedStringArray:
	return PackedStringArray(["Try again from the mission panel - the environment is the challenge."])
