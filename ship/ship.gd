extends RigidBody3D
class_name Ship

const StellarBody = preload("../solar_system/stellar_body.gd")
const Util = preload("../util/util.gd")
const SolarSystemSetup = preload("../solar_system/solar_system_setup.gd")
const Settings = preload("res://settings.gd")
const ShipController = preload("./ship_controller.gd")
const ShipAudio = preload("./ship_audio.gd")
const JetVFX = preload("./jet_vfx.gd")
const ReferenceChangeInfo = preload("res://solar_system/reference_change_info.gd")

const STATE_LANDED = 0
const STATE_FLYING = 1

@export var linear_acceleration := 10.0
@export var angular_acceleration := 1000.0
@export var speed_cap_on_planet := 40.0
@export var speed_cap_in_space := 400.0

@onready var _visual_root : Node3D = $Visual/VisualRoot
@onready var _controller : ShipController = $Controller
# Nodes that should be enabled only when landed
@onready var _landed_nodes : Array[Node] = [
	# TODO Godot4 now imports some nodes with unpredictable names if they collide instead of
	# incrementing.
	# The model has Interior and Interior-colonly but then the second was supposed to be named
	# Interior2, now instead it is some random name with an @ which means it may not be relied on...
	#$Visual/VisualRoot/ship/Interior2,
	$Visual/VisualRoot/ship/HatchDown/KinematicBody,
	$CommandPanel
]
var _landed_node_parents : Array[Node] = []
@onready var _flight_collision_shapes : Array[CollisionShape3D] = [
	$FlightCollisionShape,
	#$FlightCollisionShape2,
	#$FlightCollisionShape3
]
@onready var _animation_player : AnimationPlayer = $AnimationPlayer
@onready var _main_jets : Array[JetVFX] = [
	$Visual/VisualRoot/JetVFXMainLeft,
	$Visual/VisualRoot/JetVFXMainRight,
]
@onready var _left_roll_jets : Array[JetVFX] = [
	$Visual/VisualRoot/JetVFXLeftWing1,
	$Visual/VisualRoot/JetVFXLeftWing2
]
@onready var _right_roll_jets : Array[JetVFX] = [
	$Visual/VisualRoot/JetVFXRightWing1,
	$Visual/VisualRoot/JetVFXRightWing2
]
@onready var _audio : ShipAudio = $ShipAudio

var _move_cmd := Vector3()
var _turn_cmd := Vector3()
var _superspeed_cmd := false
var _exit_ship_cmd := false
var _state := STATE_FLYING
var _planet_damping_amount := 0.0 # TODO Doesnt need to be a member var
var _ref_change_info : ReferenceChangeInfo
var _was_superspeed := false
var _last_contacts_count := 0
var _clear_vel := false  # set by clear_velocity_next_frame(); zeroed in _integrate_forces

var _speed_cap_in_space_superspeed_multiplier := 25.0
var _linear_acceleration_superspeed_multiplier := 30.0


func _ready():
	# Workaround because these node names can easily be unreliable due to import issues
	var visual_model_root := _visual_root.get_node("ship")
	for i in visual_model_root.get_child_count():
		var node := visual_model_root.get_child(i)
		if node is StaticBody3D:
			_landed_nodes.append(node)

	for n in _landed_nodes:
		_landed_node_parents.append(n.get_parent())
	
	_setup_flashlight()
	_visual_root.global_transform = global_transform
	enable_controller()
	
	get_solar_system().reference_body_changed.connect(_on_solar_system_reference_body_changed)


func apply_game_settings(s: Settings):
	if s.world_scale_x10:
		speed_cap_in_space *= SolarSystemSetup.LARGE_SCALE
		speed_cap_on_planet *= 0.25 * SolarSystemSetup.LARGE_SCALE
		_speed_cap_in_space_superspeed_multiplier *= SolarSystemSetup.LARGE_SCALE
		_linear_acceleration_superspeed_multiplier *= SolarSystemSetup.LARGE_SCALE


func enable_controller():
	_controller.set_enabled(true)
	for n in _landed_nodes:
		n.get_parent().remove_child(n)
	for cs in _flight_collision_shapes:
		cs.disabled = false
	freeze = false
	_close_hatch()
	_state = STATE_FLYING
	_audio.play_enabled()


func disable_controller():
	_controller.set_enabled(false)
	for i in len(_landed_nodes):
		_landed_node_parents[i].add_child(_landed_nodes[i])
	for cs in _flight_collision_shapes:
		cs.disabled = true
	freeze = true
	_open_hatch()
	_state = STATE_LANDED
	_audio.play_disabled()


func _notification(what: int):
	if what == NOTIFICATION_PREDELETE:
		if _state != STATE_LANDED:
			for n in _landed_nodes:
				n.free()


func _open_hatch():
	_animation_player.play("hatch_open")


func _close_hatch():
	_animation_player.play_backwards("hatch_open")


func _on_solar_system_reference_body_changed(info: ReferenceChangeInfo):
	# We'll do that in `_integrate_forces`,
	# because Godot can't be bothered to do such override for us.
	# The camera following the ship will also needs to account for that delay...
	_ref_change_info = info
	#transform = info.inverse_transform * transform
	#_linear_velocity = info.inverse_transform.basis * _linear_velocity


func get_solar_system() -> SolarSystem:
	return get_parent()


func set_move_cmd(vec: Vector3):
	_move_cmd = vec


func set_turn_cmd(vec: Vector3):
	_turn_cmd = vec


func set_superspeed_cmd(cmd: bool):
	_superspeed_cmd = cmd


func _integrate_forces(state: PhysicsDirectBodyState3D):
	# Fast-travel warp: zero velocity the first frame after unfreeze
	if _clear_vel:
		_clear_vel = false
		state.linear_velocity  = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		return

	if _ref_change_info != null:
		# Teleport
		state.transform = _ref_change_info.inverse_transform * state.transform
		state.linear_velocity = _ref_change_info.inverse_transform.basis * state.linear_velocity
		_ref_change_info = null
	
	var gtrans := state.transform
	var forward := -gtrans.basis.z
	var right := gtrans.basis.x
	var up := gtrans.basis.y

	var stellar_body : StellarBody = get_solar_system().get_reference_stellar_body()
	var linear_acceleration_mod := linear_acceleration
	var speed_cap_in_space_mod := speed_cap_in_space

	const BRAKE_START_DIST := 500.0   # metres above surface — superspeed cuts here
	const BRAKE_STOP_DIST  := 30.0    # metres above surface — from here down it is a slow touchdown

	# Proximity check to all planets for auto-braking
	var ss := get_solar_system()
	var near_planet := false
	var near_planet_surface_dist := 999999.0
	var planet_approach_dir := Vector3.ZERO
	var nearest_radius := 1000.0
	if ss != null:
		for i in ss.get_stellar_body_count():
			var b : StellarBody = ss.get_stellar_body(i)
			if b.type == StellarBody.TYPE_SUN:
				continue
			var b_pos := b.node.global_transform.origin
			var dist_to_center := b_pos.distance_to(gtrans.origin)
			var dist_to_surf := dist_to_center - b.radius
			# Fixed detection range: 1000 m above surface
			if dist_to_surf < BRAKE_START_DIST:
				if not near_planet or dist_to_surf < near_planet_surface_dist:
					near_planet = true
					near_planet_surface_dist = dist_to_surf
					planet_approach_dir = (b_pos - gtrans.origin).normalized()
					nearest_radius = b.radius

	# Hard safety: never let the ship get inside any body (fast ships can tunnel through terrain
	# that has not finished streaming). Push it back out and cancel the inward velocity.
	if ss != null:
		for i in ss.get_stellar_body_count():
			var cb : StellarBody = ss.get_stellar_body(i)
			var core_r := cb.radius if cb.type == StellarBody.TYPE_SUN \
				else SolarSystemSetup.get_solid_core_radius(cb)
			var to_ship := gtrans.origin - cb.node.global_transform.origin
			var d := to_ship.length()
			if d < core_r + 5.0:
				var out_dir := to_ship / d if d > 0.001 else Vector3.UP
				state.transform.origin = cb.node.global_transform.origin + out_dir * (core_r + 5.0)
				var inward := -state.linear_velocity.dot(out_dir)
				if inward > 0.0:
					state.linear_velocity += out_dir * inward
				gtrans = state.transform

	var superspeed := false
	# Disengage superspeed at 1000 m from surface
	if _superspeed_cmd:
		speed_cap_in_space_mod *= _speed_cap_in_space_superspeed_multiplier
		linear_acceleration_mod *= _linear_acceleration_superspeed_multiplier
		superspeed = true
	
	if superspeed != _was_superspeed:
		if superspeed:
			_audio.play_start_superspeed()
		else:
			_audio.play_stop_superspeed()
		_was_superspeed = superspeed

	var speed_cap := speed_cap_in_space_mod
	
	var motor := _move_cmd.z * forward * linear_acceleration_mod
	state.apply_central_force(motor)

	_turn_cmd.x = clampf(_turn_cmd.x, -1.0, 1.0)
	_turn_cmd.y = clampf(_turn_cmd.y, -1.0, 1.0)
	_turn_cmd.z = clampf(_turn_cmd.z, -1.0, 1.0)
	
	state.apply_torque_impulse(up * _turn_cmd.x * angular_acceleration)
	state.apply_torque_impulse(right * _turn_cmd.y * angular_acceleration)
	state.apply_torque_impulse(forward * _turn_cmd.z * angular_acceleration)

	# Planet influence
	if stellar_body.type != StellarBody.TYPE_SUN:
		var pull_center := stellar_body.node.global_transform.origin
		var distance_to_core := pull_center.distance_to(gtrans.origin)

		var gd : float = absf(distance_to_core - stellar_body.radius) + stellar_body.radius
		var gravity_dir := (pull_center - gtrans.origin).normalized()
		var stellar_mass := Util.get_sphere_volume(stellar_body.radius)
		var f := 0.005 * stellar_mass / (gd * gd)
		f = minf(f, 25.0)
		state.apply_central_force(gravity_dir * f)
		
		# Near-planet damping
		var distance_to_surface := distance_to_core - stellar_body.radius
		_planet_damping_amount = \
			1.0 - clampf((distance_to_surface - 50.0) / stellar_body.radius, 0.0, 1.0)
		DDD.set_text("Atmosphere damping amount", _planet_damping_amount)
		speed_cap = minf(speed_cap_in_space_mod, maxf(speed_cap_on_planet, distance_to_surface * 3.0))

	# Proximity Auto-Brake: smooth ramp from 500 m down to a slow touchdown speed (no invisible wall:
	# the ship must be able to land on walkable bodies)
	if near_planet:
		# brake_t: 0.0 at 1000 m, 1.0 at 500 m
		var brake_t := clampf(
			1.0 - (near_planet_surface_dist - BRAKE_STOP_DIST) / (BRAKE_START_DIST - BRAKE_STOP_DIST),
			0.0, 1.0)
		# Speed cap drops from normal planet speed to ~10% as you close in
		speed_cap = minf(speed_cap, maxf(speed_cap_on_planet * 0.1, (near_planet_surface_dist - BRAKE_STOP_DIST) * 3.0))
		# Cancel inward velocity aggressively
		var inward_speed := state.linear_velocity.dot(planet_approach_dir)
		if inward_speed > 0.0:
			var brake_rate := brake_t * brake_t * 4.0 * state.step
			state.linear_velocity -= planet_approach_dir * inward_speed * clampf(brake_rate, 0.0, 1.0)
	
	var speed := state.linear_velocity.length()
	if speed > speed_cap:
		state.linear_velocity = state.linear_velocity.normalized() * speed_cap
	
	# Jets
	var main_jet_power := _move_cmd.z
	for jet in _main_jets:
		jet.set_power(main_jet_power)
	var left_roll_jet_power := maxf(_turn_cmd.z, 0.0)
	var right_roll_jet_power := maxf(-_turn_cmd.z, 0.0)
	for jet in _left_roll_jets:
		jet.set_power(left_roll_jet_power)
	for jet in _right_roll_jets:
		jet.set_power(right_roll_jet_power)
	_audio.set_main_jet_power(absf(_move_cmd.z))
	_audio.set_secondary_jet_power(clampf(left_roll_jet_power + right_roll_jet_power, 0.0, 1.0))

	DDD.set_text("Speed", state.linear_velocity.length())
	DDD.set_text("X", gtrans.origin.x)
	DDD.set_text("Y", gtrans.origin.y)
	DDD.set_text("Z", gtrans.origin.z)
	
	_visual_root.global_transform = gtrans
	
	_last_contacts_count = state.get_contact_count()


func get_last_contacts_count() -> int:
	return _last_contacts_count



func is_flying() -> bool:
	return _state == STATE_FLYING


func get_controller() -> ShipController:
	return _controller


# ─── Flashlight ──────────────────────────────────────────────────────────────
# A spotlight on the nose of the ship (key F / gamepad X / XR left grip while flying). It lights
# dark sides of planets, shadowed craters and night landings.

var _flashlight : SpotLight3D
var _flashlight_audio : AudioStreamPlayer

const FlashOnSound = preload("res://sounds/flash_on.wav")
const FlashOffSound = preload("res://sounds/flash_off.wav")


func _setup_flashlight() -> void:
	_flashlight = SpotLight3D.new()
	_flashlight.name = "Flashlight"
	_flashlight.light_color = Color(1.0, 0.97, 0.88)
	_flashlight.light_energy = 14.0
	_flashlight.spot_range = 400.0
	_flashlight.spot_angle = 30.0
	_flashlight.spot_attenuation = 0.7
	_flashlight.shadow_enabled = false
	_flashlight.visible = false
	# The ship points along -Z: mount the light on the nose
	_flashlight.position = Vector3(0.0, 0.3, -3.5)
	_visual_root.add_child(_flashlight)
	_flashlight_audio = AudioStreamPlayer.new()
	add_child(_flashlight_audio)


func is_flashlight_on() -> bool:
	return _flashlight != null and _flashlight.visible


func set_flashlight(on: bool) -> void:
	if _flashlight == null or _flashlight.visible == on:
		return
	_flashlight.visible = on
	_flashlight_audio.stream = FlashOnSound if on else FlashOffSound
	_flashlight_audio.play()


func toggle_flashlight() -> void:
	set_flashlight(not is_flashlight_on())
