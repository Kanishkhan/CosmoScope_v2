extends Node
class_name SolarSystem

const StellarBody = preload("./stellar_body.gd")
const SolarSystemSetup = preload("./solar_system_setup.gd")
const Settings = preload("res://settings.gd")
const MouseCapture = preload("res://gui/mouse_capture.gd")
const HUD = preload("res://gui/hud.gd")
const PauseMenu = preload("res://gui/pause_menu/pause_menu.gd")
const LensFlare = preload("res://addons/SIsilicon.vfx.lens flare/lens-flare.gd")
const SS_Camera = preload("res://camera/camera.gd")
const ReferenceChangeInfo = preload("./reference_change_info.gd")
const LoadingProgress = preload("./loading_progress.gd")
const FastTravelUI = preload("res://gui/fast_travel_ui.gd")

const CameraScene = preload("../camera/camera.tscn")
const ShipScene = preload("../ship/ship.tscn")
const FastTravelUIScene = preload("res://gui/fast_travel_ui.tscn")
const PlanetInteractionDialogScene = preload("res://gui/planet_interaction_dialog.tscn")
const MissionManagerScene = preload("res://missions/mission_manager.tscn")

const BODY_REFERENCE_ENTRY_RADIUS_FACTOR = 3.5
const BODY_REFERENCE_EXIT_RADIUS_FACTOR = 6.0 # Generous hysteresis to prevent flickering
const BODY_REFERENCE_COOLDOWN_FRAMES = 60 # 1 second cooldown between referential switches


signal reference_body_changed(info)
signal loading_progressed(info)
signal exit_to_menu_requested
signal player_spawned


@onready var _environment : Environment = $WorldEnvironment.environment
@onready var _spawn_point : Node3D = $SpawnPoint
@onready var _mouse_capture : MouseCapture = $MouseCapture
@onready var _hud : HUD = $HUD
@onready var _pause_menu : PauseMenu = $PauseMenu
@onready var _lens_flare : LensFlare = $LensFlare

var _ship : Ship = null
var _game_camera : SS_Camera = null

var _bodies : Array[StellarBody] = []
var _reference_body_id := 0
var _directional_light : DirectionalLight3D
var _physics_count := 0
var _physics_count_on_last_reference_change := 0
# This is a placeholder instance to allow testing the game without going from the usual main scene.
# It will be overriden in the normal flow.
var _settings := Settings.new()
var _settings_ui : Control
var _last_clouds_quality := -1

# Fast travel state
var _fast_travel_ui : Control = null
var _is_warping := false

# Planet interaction dialog
var _planet_dialog : Control = null
var _dialog_shown_for : String = ""
const DIALOG_SHOW_DISTANCE_FACTOR = 8.0  # x planet radius
const DIALOG_HIDE_DISTANCE_FACTOR = 10.0
const ORBITAL_LOD_SWITCH_NEAR = 2.8 # x radius: below this the voxel terrain replaces the orbital body
const ORBITAL_LOD_SWITCH_FAR = 3.0
# Bodies with surface exploration (walking, digging, missions). Everything else is flight only.
const WALKABLE_BODY_NAMES := ["Mercury", "Venus", "Earth", "Mars", "Moon"]

# Mission manager
var _mission_manager : Node = null

# Warp movement state — driven by _physics_process for frame-accurate delta
var _warp_active        := false
var _warp_elapsed       := 0.0
const WARP_DURATION     := 5.0   # seconds — cinematic hyperspeed travel
var _warp_start_pos     := Vector3.ZERO
var _warp_arrival_pos   := Vector3.ZERO
var _warp_to_planet     := Vector3.ZERO  # normalised travel direction (world space)
var _warp_target_body   : StellarBody = null
var _warp_target_id     := -1


func _ready():
	set_physics_process(false)
	_hud.hide()
	
	_bodies = SolarSystemSetup.create_solar_system_data(_settings)
	
	var progress_info := LoadingProgress.new()
	
	for i in len(_bodies):
		var body : StellarBody = _bodies[i]
		progress_info.message = "Setting up {0}...".format([body.name])
		progress_info.progress = float(i) / float(len(_bodies))
		loading_progressed.emit(progress_info)
		await get_tree().process_frame

		var sun_light := SolarSystemSetup.setup_stellar_body(body, self, _settings)
		if sun_light != null:
			_directional_light = sun_light

	# Wait for initial GPU shader compilation.
	var initial_gpu_tasks : int = get_gpu_tasks_count()
	if initial_gpu_tasks > 0:
		var gpu_tasks      := initial_gpu_tasks
		var max_gpu_tasks  := initial_gpu_tasks
		var start_ms       := Time.get_ticks_msec()
		const TIMEOUT_MS   := 15_000  # 15 seconds max wait for initial shaders

		while gpu_tasks > 0:
			var elapsed_ms := Time.get_ticks_msec() - start_ms
			if elapsed_ms >= TIMEOUT_MS:
				break
			# Keep denominator growing so progress never goes negative
			if gpu_tasks > max_gpu_tasks:
				max_gpu_tasks = gpu_tasks
			var done        := max_gpu_tasks - gpu_tasks
			var elapsed_s   := int(elapsed_ms / 1000.0)
			progress_info.message = \
				"Compiling shaders — %d remaining (%ds)" % [gpu_tasks, elapsed_s]
			progress_info.progress = float(done) / float(max_gpu_tasks)
			loading_progressed.emit(progress_info)
			await get_tree().process_frame
			gpu_tasks = get_gpu_tasks_count()

	# Spawn player
	_mouse_capture.capture()
	# Camera must process before the ship so we have to spawn it before...
	var camera : SS_Camera = CameraScene.instantiate()
	camera.auto_find_camera_anchor = true
	camera.far = maxf(camera.far, 300000.0)  # outer planets are up to ~140000 from the sun
	if _settings.world_scale_x10:
		camera.far *= SolarSystemSetup.LARGE_SCALE
	add_child(camera)
	_ship = ShipScene.instantiate()
	_ship.global_transform = _spawn_point.global_transform
	_ship.apply_game_settings(_settings)
	add_child(_ship)
	camera.set_target(_ship)
	_game_camera = camera
	_hud.show()
	player_spawned.emit()

	# Spawn fast travel UI (null-guarded: a bad tscn will disable fast travel
	# rather than crashing the whole game)
	var ft_instance = FastTravelUIScene.instantiate()
	if ft_instance != null:
		_fast_travel_ui = ft_instance
		add_child(_fast_travel_ui)
		_fast_travel_ui.travel_confirmed.connect(_on_fast_travel_confirmed)
		_fast_travel_ui.travel_cancelled.connect(_on_fast_travel_cancelled)
	else:
		push_error("FastTravelUI failed to instantiate — fast travel disabled.")

	# Spawn planet interaction dialog
	var dialog_instance = PlanetInteractionDialogScene.instantiate()
	if dialog_instance != null:
		_planet_dialog = dialog_instance
		add_child(_planet_dialog)
		_planet_dialog.mission_pressed.connect(_on_planet_mission)
		_planet_dialog.dismissed.connect(_on_planet_dialog_dismissed)
	else:
		push_error("PlanetInteractionDialog failed to instantiate.")

	# Spawn mission manager
	var mm_instance = MissionManagerScene.instantiate()
	if mm_instance != null:
		_mission_manager = mm_instance
		add_child(_mission_manager)
		_mission_manager.mission_started.connect(func(n): print("Mission started: ", n))
		_mission_manager.mission_ended.connect(func(n, w): print("Mission ended: ", n, " won: ", w))
	else:
		push_error("MissionManager failed to instantiate.")

	set_physics_process(true)

	progress_info.finished = true
	loading_progressed.emit(progress_info)
	
	_last_clouds_quality = _settings.clouds_quality



static func get_gpu_tasks_count() -> int:
	var stats := VoxelEngine.get_stats()
	var task_counts : Dictionary = stats["tasks"]
	# Older versions don't have this entry
	return task_counts.get("gpu", 0)


func set_settings(s: Settings):
	_settings = s


func set_settings_ui(ui: Control):
	_settings_ui = ui


func _unhandled_input(event: InputEvent):
	if event is InputEventKey:
		if event.pressed and not event.is_echo():
			if event.keycode == KEY_ESCAPE:
				if _settings_ui.visible:
					_settings_ui.hide()
				elif _pause_menu.visible:
					_pause_menu.hide()
					_mouse_capture.capture()
				else:
					_pause_menu.show()


func _physics_process(delta: float):
	# ── Warp movement (physics-driven, frame-accurate) ──────────────────────
	if _warp_active:
		_warp_elapsed += delta
		var t := clampf(_warp_elapsed / WARP_DURATION, 0.0, 1.0)
		# Power-curve: very fast in the middle, decelerates as it approaches
		# Use a custom ease: fast ramp then smooth brake
		var smooth_t: float
		if t < 0.7:
			# Accelerating phase: ease-in
			smooth_t = (t / 0.7) * (t / 0.7) * 0.7
		else:
			# Decelerating phase: ease-out
			var u := (t - 0.7) / 0.3
			smooth_t = 0.7 + u * (2.0 - u) * 0.3
		var new_pos := _warp_start_pos.lerp(_warp_arrival_pos, smooth_t)
		var new_trans := _ship.global_transform
		new_trans.origin = new_pos
		if _warp_to_planet.length_squared() > 0.001:
			# Always face toward the target planet's current world position
			var target_world_pos := _bodies[_warp_target_id].node.global_transform.origin
			var look_dir := (target_world_pos - new_pos)
			if look_dir.length_squared() > 0.01:
				new_trans = new_trans.looking_at(target_world_pos, Vector3.UP)
		_ship.global_transform = new_trans
		if t >= 1.0:
			_finish_warp()
		return  # Skip orbit simulation during warp

	# Check when to change referential.
	# Only do so after a few frames elapsed from the last change, because in Godot,
	# physics are deferred in shitty ways even if we presently are in _physics_process
	if not _warp_active and _physics_count > 0 and _physics_count - _physics_count_on_last_reference_change > BODY_REFERENCE_COOLDOWN_FRAMES:
		# Enter the reference frame of any body we get close to. This also works from inside another
		# body's frame (e.g. the Moon, which orbits Earth and would otherwise slide under our feet).
		var entered := false
		for i in len(_bodies):
			var body : StellarBody = _bodies[i]
			if body.type == StellarBody.TYPE_SUN or i == _reference_body_id:
				# Ignore sun, no point landing there
				continue
			var body_pos := body.node.global_transform.origin
			var d := body_pos.distance_to(_ship.global_transform.origin)
			if d < BODY_REFERENCE_ENTRY_RADIUS_FACTOR * body.radius:
				print("Close to ", body.name, " which is at ", body_pos)
				set_reference_body(i)
				entered = true
				break
		if not entered and _reference_body_id != 0:
			var ref_body := _bodies[_reference_body_id]
			var body_pos := ref_body.node.global_transform.origin
			var d := body_pos.distance_to(_ship.global_transform.origin)
			if d > BODY_REFERENCE_EXIT_RADIUS_FACTOR * ref_body.radius:
				set_reference_body(0)
	
	# Calculate current referential transform
	var ref_trans_inverse := Transform3D()
	if _reference_body_id != 0:
		var ref_body := _bodies[_reference_body_id]
		var ref_trans := _compute_absolute_body_transform(ref_body)
		ref_trans_inverse = ref_trans.affine_inverse()

	# Simulate orbits
	for i in len(_bodies):
		var body : StellarBody = _bodies[i]
		
		if body.self_revolution_time > 0:
			body.self_revolution_progress += delta / body.self_revolution_time
			if body.self_revolution_progress >= 1.0:
				body.self_revolution_progress -= 1.0
				body.day_count += 1
		
		if body.orbit_revolution_time > 0:
			body.orbit_revolution_progress += delta / body.orbit_revolution_time
			if body.orbit_revolution_progress >= 1.0:
				body.orbit_revolution_progress -= 1.0
				body.year_count += 1
		
		if _reference_body_id == i:
			# Don't touch the reference body
			continue
		
		var trans := _compute_absolute_body_transform(body)
		
		if _reference_body_id != 0:
			trans = ref_trans_inverse * trans
		
		body.node.transform = trans
	
	# Update directional light. Smoke and mirrors here:
	# We use a DirectionalLight because it has better quality than an OmniLight,
	# but that means planets are not accurately lit. This is not much of an issue though because
	# discrepancies will occur only when planets are very far away, or even behind the sun.
	# If we still want accurate lighting, we could maybe modify their shader far away to simulate
	# them being lit in a simplified manner?
	var camera : Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		var pos := camera.global_transform.origin
		pos.y = 0.0
		if pos != _directional_light.global_transform.origin:
			_directional_light.look_at(pos, Vector3(0, 1, 0))

	_process_directional_shadow_distance()
	
	# Update sky rotation.
	if _reference_body_id != 0:
		# When we are on a planet, the sky is no longer in world space,
		# so we must simulate its motion relative to us
		_environment.sky_rotation = ref_trans_inverse.basis.get_euler()
	else:
		_environment.sky_rotation = Vector3()
	
	_process_setting_changes()
	_update_planet_body_shaders()
	
	_physics_count += 1
	
	_process_debug()

	_process_atmosphere_large_distance_hack()


# Update sun_direction on all PlanetBody/Ring shaders so lighting tracks the sun,
# and fade out orbital LOD spheres when the camera is close enough for voxel terrain.
func _update_planet_body_shaders() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var cam_pos := camera.global_transform.origin

	# Sun is always bodies[0]; its world position gives us the light direction
	var sun_body := _bodies[0]
	var sun_pos := sun_body.node.global_transform.origin

	# ── PLAY MISSION prompt (top-right) ────────────────────────────────────
	# Only for bodies you can walk on (Mercury, Venus, Earth, Mars, Moon) and only while on foot.
	# Gas/ice giants stay flight-only experiences and never show it.
	if _planet_dialog != null:
		var walk_body_name := get_walkable_body_name_under_player()
		if walk_body_name != "" and not _warp_active:
			if _dialog_shown_for != walk_body_name:
				_dialog_shown_for = walk_body_name
				_planet_dialog.show_for_planet(walk_body_name)
		elif _dialog_shown_for != "":
			_dialog_shown_for = ""
			if _planet_dialog.visible:
				_planet_dialog.dismiss()

	for body in _bodies:
		if body.node == null:
			continue
		var body_pos := body.node.global_transform.origin
		var sun_dir_local := (sun_pos - body_pos).normalized()

		for child in body.node.get_children():
			if not child is MeshInstance3D:
				continue
			var mi := child as MeshInstance3D
			if mi.name == "PlanetBody" or mi.name == "Rings":
				var mat := mi.material_override
				if mat is ShaderMaterial:
					mat.set_shader_parameter(&"sun_direction", sun_dir_local)
				# Orbital LOD: from far away the procedural planet body is the ONLY thing drawn for a
				# rocky planet (the voxel terrain's coarsest LODs would otherwise z-fight with it and
				# make every rocky planet look like the same grey/brown ball). Up close it is the
				# voxel terrain that is drawn. Hysteresis avoids flicker at the switch distance.
				if mi.name == "PlanetBody" and mi.has_meta("lod_orbital"):
					var dist_to_cam := body_pos.distance_to(cam_pos)
					var show_orbital : bool = mi.visible
					if show_orbital and dist_to_cam < body.radius * ORBITAL_LOD_SWITCH_NEAR:
						show_orbital = false
					elif not show_orbital and dist_to_cam > body.radius * ORBITAL_LOD_SWITCH_FAR:
						show_orbital = true
					mi.visible = show_orbital
					if body.volume != null:
						body.volume.visible = not show_orbital


func _on_planet_mission(body_name: String) -> void:
	print("Starting mission for: ", body_name)
	if _mission_manager != null:
		_mission_manager.start_mission(body_name)
	else:
		push_warning("MissionManager not available.")


func _on_planet_dialog_dismissed() -> void:
	# Keep _dialog_shown_for set until the ship leaves the planet's vicinity
	pass


func _process_setting_changes():
	# Update graphics settings
	if _settings.shadows_enabled != _directional_light.shadow_enabled:
		_directional_light.shadow_enabled = _settings.shadows_enabled

	if _settings.glow_enabled != _environment.glow_enabled:
		_environment.glow_enabled = _settings.glow_enabled
	if _settings.lens_flares_enabled != _lens_flare.enabled:
		_lens_flare.enabled = _settings.lens_flares_enabled

	if _settings.clouds_quality != _last_clouds_quality:
		_last_clouds_quality = _settings.clouds_quality
		for body in _bodies:
			if body.atmosphere != null:
				SolarSystemSetup.update_atmosphere_settings(body, _settings)


func _process_debug():
	for body in _bodies:
		var volume : VoxelLodTerrain = body.volume
		if body.volume == null:
			continue
		if _settings.show_octree_nodes \
		or _settings.show_mesh_updates \
		or _settings.show_edited_data_blocks:
			volume.debug_set_draw_enabled(true)
			volume.debug_set_draw_flag(VoxelLodTerrain.DEBUG_DRAW_EDITED_BLOCKS, 
				_settings.show_edited_data_blocks)
			volume.debug_set_draw_flag(VoxelLodTerrain.DEBUG_DRAW_MESH_UPDATES,
				_settings.show_mesh_updates)
			volume.debug_set_draw_flag(VoxelLodTerrain.DEBUG_DRAW_OCTREE_NODES,
				_settings.show_octree_nodes)
		else:
			volume.debug_set_draw_enabled(false)
	
	if len(_bodies) > 0:
		DDD.set_text("Reference body", _bodies[_reference_body_id].name)

	for i in len(_bodies):
		var body : StellarBody = _bodies[i]
		if body.volume == null:
			continue
		var s := str(
			"D: ", body.volume.debug_get_data_block_count(), ", ", 
			"M: ", body.volume.debug_get_mesh_block_count())
		if body.instancer != null:
			s += str("| I: ", body.instancer.debug_get_block_count())
		DDD.set_text(str("Blocks in ", body.name), s)
		#var stats = body.volume.get_statistics()
		#for k in stats:
		#	if k.begins_with("time_"):
		#		var t = stats[k]
		#		if t > 8000:
		#			DDD.set_text(str("!! ", body.name, " ", k), t)
		#if stats.blocked_lods > 0:
		#	DDD.set_text(str("!! blocked lods on ", body.name), stats.blocked_lods)


func _process_directional_shadow_distance():
	var camera : Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var light := _directional_light
	var ref_body := get_reference_stellar_body()
	var distance_to_core := \
		ref_body.node.global_transform.origin.distance_to(camera.global_transform.origin)
	var distance_to_surface := maxf(distance_to_core - ref_body.radius, 0.0)

	var scale := 1.0
	if _settings.world_scale_x10:
		scale = SolarSystemSetup.LARGE_SCALE

	var near_distance := 10.0 * scale
	# TODO Increase near shadow distance when flying ship?
	var near_shadow_distance := 500.0
	var far_distance := 1000.0 * scale
	var far_shadow_distance := 20000.0

	# Increase shadow distance when far from planets
	var t := clampf(
		(distance_to_surface - near_distance) / (far_distance - near_distance), 0.0, 1.0)
	var shadow_distance := lerpf(near_shadow_distance, far_shadow_distance, t)
	light.directional_shadow_max_distance = shadow_distance
	# if not Input.is_key_pressed(KEY_KP_0):
	# 	light.directional_shadow_max_distance = 500.0
	DDD.set_text("Shadow distance", shadow_distance)


# This helps with planet flickering in the distance.
# Unfortunately, it still flickers while on ground or really far away.
func _process_atmosphere_large_distance_hack():
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var cam_pos_world := camera.global_transform.origin

	for body in _bodies:
		if body.atmosphere != null and body.node != null:
			var planet_pos_world := body.node.global_transform.origin
			var distance := cam_pos_world.distance_to(planet_pos_world)
			var transition_distance_start := body.radius * 2.0
			var transition_length := body.radius * 1.5
			var sphere_factor := \
				clampf((distance - transition_distance_start) / transition_length, 0.0, 1.0)
			body.atmosphere.set_shader_parameter(&"u_sphere_depth_factor", sphere_factor)


func set_reference_body(ref_id: int):
	if _reference_body_id == ref_id:
		return
	
	var previous_body := _bodies[_reference_body_id]
	for sb in previous_body.static_bodies:
		sb.get_parent().remove_child(sb)
	previous_body.static_bodies_are_in_tree = false
	
	_reference_body_id = ref_id
	var body := _bodies[_reference_body_id]
	print("Setting reference to ", ref_id, " (", body.name, ")")
	var trans := body.node.transform
	body.node.transform = Transform3D()
	
	var info := ReferenceChangeInfo.new()
	# TODO Also have relative velocity of the body,
	# so the ship can integrate it so it looks seamless
	info.inverse_transform = trans.affine_inverse() * body.node.transform
	_physics_count_on_last_reference_change = _physics_count
	
	for sb in body.static_bodies:
		body.node.add_child(sb)
	body.static_bodies_are_in_tree = true

	# TODO Shadow opacity was removed in Godot 4, need it back because it's too dark now.
	# See https://github.com/godotengine/godot/pull/61893
	#_directional_light.shadow_color = body.atmosphere_color.darkened(0.8)
#	var environment := get_viewport().world_3d.environment
#	environment.ambient_light_color = body.atmosphere_color
#	environment.ambient_light_energy = 20
	
	reference_body_changed.emit(info)


func _compute_absolute_body_transform(body: StellarBody) -> Transform3D:
	if body.parent_id == -1:
		# Sun
		return Transform3D()
	var parent_transform := Transform3D()
	if body.parent_id != -1:
		var parent_body := _bodies[body.parent_id]
		parent_transform = _compute_absolute_body_transform(parent_body)
	var orbit_angle := body.orbit_revolution_progress * TAU
	# TODO Elliptic orbits
	var pos := Vector3(cos(orbit_angle), 0, sin(orbit_angle)) * body.distance_to_parent
	pos = pos.rotated(Vector3(0, 0, 1), body.orbit_tilt)
	var self_angle := body.self_revolution_progress * TAU
	var basis := Basis.from_euler(Vector3(0, self_angle, body.self_tilt))
	var local_transform := Transform3D(basis, pos)
	return parent_transform * local_transform


func get_stellar_body_count() -> int:
	return len(_bodies)


func get_stellar_body(idx: int) -> StellarBody:
	return _bodies[idx]


func get_reference_stellar_body() -> StellarBody:
	return _bodies[_reference_body_id]


func get_ship() -> Ship:
	return _ship


func get_sun_position() -> Vector3:
	return _directional_light.global_transform.origin


# ─── Fast Travel ─────────────────────────────────────────────────────────────

## Called by HUD when player clicks a planet (in ship mode)
func request_fast_travel(body: StellarBody) -> void:
	if _is_warping:
		return
	if _fast_travel_ui == null:
		return
	# Only allow when the player is IN the ship (controller enabled)
	if not _ship._controller.is_processing():
		return
	_fast_travel_ui.show_for_body(body)


func _on_fast_travel_confirmed(body: StellarBody) -> void:
	_start_warp_to(body)


func _on_fast_travel_cancelled() -> void:
	pass  # Mouse mode restored by the UI itself


## Hyperspace warp: begins movement state; actual travel runs in _physics_process.
func _start_warp_to(target_body: StellarBody) -> void:
	if _is_warping:
		return
	_is_warping = true

	# Find the target body index
	var target_id := _bodies.find(target_body)
	_warp_target_id = target_id

	# Freeze ship physics and disable player controls during warp
	_ship._ref_change_info = null
	_ship.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_ship.freeze = true
	_ship._clear_vel = true
	_ship._controller.set_enabled(false)

	# Calculate approach in the CURRENT reference frame (world space or current planet frame).
	# The planet's current world-space position is its node's global_transform.origin.
	var ship_pos   := _ship.global_transform.origin
	var planet_pos := target_body.node.global_transform.origin

	# Arrival position: (radius + 600) meters above the planet surface, along the approach line
	var approach_dir := (planet_pos - ship_pos).normalized()
	var arrival_pos  := planet_pos - approach_dir * (target_body.radius + 600.0)

	# Initialise warp state for _physics_process
	_warp_start_pos   = ship_pos
	_warp_arrival_pos = arrival_pos
	_warp_to_planet   = approach_dir   # direction toward planet (world-space)
	_warp_elapsed     = 0.0
	_warp_active      = true

	# Keep reference-change cooldown so we don't accidentally flicker referentials during travel
	_physics_count_on_last_reference_change = _physics_count

	# Show warp VFX overlay
	_fast_travel_ui.begin_warp_vfx()


## Called from _physics_process when warp is complete.
func _finish_warp() -> void:
	_warp_active = false

	# NOW switch reference frame to the target planet — after physically arriving there
	if _warp_target_id != -1 and _reference_body_id != _warp_target_id:
		set_reference_body(_warp_target_id)
		# After set_reference_body, planet is at (0,0,0).
		# The ship's arrival position in new frame = -approach_dir * (radius + 600)
		var target_body := _bodies[_warp_target_id]
		var arrival_in_new_frame := -_warp_to_planet * (target_body.radius + 600.0)
		var final_trans := _ship.global_transform
		final_trans.origin = arrival_in_new_frame
		final_trans = final_trans.looking_at(Vector3.ZERO, Vector3.UP)
		_ship.global_transform = final_trans
	else:
		# Already in the right frame — just snap to arrival and face planet
		var final_trans := _ship.global_transform
		final_trans.origin = _warp_arrival_pos
		if _warp_to_planet.length_squared() > 0.001:
			var target_body := _bodies[_warp_target_id]
			final_trans = final_trans.looking_at(target_body.node.global_transform.origin, Vector3.UP)
		_ship.global_transform = final_trans

	# Unfreeze and restore normal physics; ship zeroes velocity inside _integrate_forces
	_ship._ref_change_info = null
	_ship.freeze = false
	_ship.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	_ship._clear_vel = true

	# Restore player controls
	_ship._controller.set_enabled(true)

	_is_warping = false

	# Cooldown to stay locked to the arrived planet
	_physics_count_on_last_reference_change = _physics_count

	# End VFX overlay (also restores mouse capture inside fast_travel_ui)
	_fast_travel_ui.end_warp_vfx()


func _notification(what: int):
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			# Save game when the user closes the window
			_save_world()


func _save_world():
	print("Saving world")
	for body in _bodies:
		if body.volume != null:
			body.volume.save_modified_blocks()


func _on_PauseMenu_exit_to_menu_requested():
	_save_world()
	exit_to_menu_requested.emit()


func _on_PauseMenu_exit_to_os_requested():
	_save_world()
	get_tree().quit()


func _on_PauseMenu_resume_requested():
	_pause_menu.hide()
	_mouse_capture.capture()


func _on_PauseMenu_settings_requested():
	_settings_ui.show()
	# The settings UI exists before the game is instanced so it might be behind.
	# This makes sure it shows in front.
	_settings_ui.move_to_front()


# ─── XR hooks (see res://xr) ─────────────────────────────────────────────────

## The chase camera that follows the ship/character. In XR the active camera is an XRCamera3D,
## so gameplay code must not assume `get_viewport().get_camera_3d()` is this one.
func get_game_camera() -> SS_Camera:
	return _game_camera


func get_environment() -> Environment:
	return _environment


func get_spawn_transform() -> Transform3D:
	return _spawn_point.global_transform


func can_fast_travel() -> bool:
	return not _is_warping and _ship != null and _ship._controller.is_processing()


## Fast travel without the 2D confirmation dialog (used by XR, where 2D UI is not visible).
func fast_travel_now(body: StellarBody) -> void:
	if not can_fast_travel() or _fast_travel_ui == null:
		return
	if body.type == StellarBody.TYPE_SUN or body == get_reference_stellar_body():
		return
	_start_warp_to(body)


# ─── Walkable bodies ─────────────────────────────────────────────────────────

func is_body_walkable(body: StellarBody) -> bool:
	return body != null and body.name in WALKABLE_BODY_NAMES


## The character on foot (null while flying the ship).
func get_character() -> Node3D:
	return get_tree().get_first_node_in_group(&"xr_character") as Node3D


## The body closest to the player's feet, whatever the current reference frame is.
func get_body_under_player() -> StellarBody:
	var character := get_character()
	if character == null:
		return null
	var pos := character.global_transform.origin
	var best : StellarBody = null
	var best_alt := INF
	for body in _bodies:
		if body.type == StellarBody.TYPE_SUN or body.node == null:
			continue
		var alt := body.node.global_transform.origin.distance_to(pos) - body.radius
		if alt < best_alt:
			best_alt = alt
			best = body
	# Must really be near the surface, not somewhere in space
	if best != null and best_alt > 1000.0:
		return null
	return best


## Name of the walkable body the player is on foot on, or "" (flying, or on a gas/ice giant).
func get_walkable_body_name_under_player() -> String:
	var body := get_body_under_player()
	if is_body_walkable(body):
		return body.name
	return ""


func get_planet_dialog() -> Control:
	return _planet_dialog


func get_mission_manager() -> Node:
	return _mission_manager
