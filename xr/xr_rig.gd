# The XR player rig (XROrigin3D + XRCamera3D + two XRController3D), built in code and added to the
# game world by XRManager. It does not replace the existing camera/ship/character: the original
# chase camera keeps running (it handles collisions and reference-body switches) and this rig
# follows it. The rig only *drives* the existing ship/character through their public commands.
#
# VR: the origin follows the chase camera (flight) or the character's feet (on foot).
#     Flight: left stick = thrust/roll, right stick = yaw/pitch, right grip = superspeed,
#             left grip = ship flashlight,
#             A = leave ship, hold right trigger on a planet = fast travel.
#     Walk:   left stick = move, right stick forward = teleport arc (release to teleport),
#             right stick sideways = snap turn, right trigger = dig, left trigger = build,
#             A = jump, B = return to ship, left grip = flashlight, right grip = waypoint,
#             left stick click = toggle smooth movement.
#     PLAY MISSION panel (walkable bodies only): point the right laser at the button and pull
#             the trigger; or left X = PLAY MISSION, left menu button = dismiss panel.
# AR: a live tabletop model of the Solar System (xr_orrery.gd) is anchored in the room and the
#     passthrough shows the real world around it (OpenXR world_scale is capped at 1000, so the real
#     Solar System cannot simply be shrunk). Aim at a surface and pull the trigger to place it;
#     right stick = rotate / scale while placing (or holding left grip); trigger-tap a planet to
#     select it, hold it to fast travel the ship there; touch the table + left grip while
#     placing sets the table height; left X = place again; right stick click = reset yaw/scale.
#     The ship is still flown with the sticks; an orange marker shows where it is in the model.
# Both: left Y = toggle VR <-> AR, left X (VR, no panel open) = recenter.
extends XROrigin3D

const XRMode = preload("./xr_mode.gd")
const StellarBody = preload("../solar_system/stellar_body.gd")
const XROrrery = preload("./xr_orrery.gd")

const DEADZONE := 0.15
const SNAP_TURN_DEGREES := 30.0
const FLIGHT_TURN_GAIN := 0.35
const TELEPORT_STEPS := 40
const HOLD_TO_WARP_TIME := 1.2
const FOCUS_TAP_TIME := 0.5
const TRIGGER_THRESHOLD := 0.6

const ORRERY_SCALE_MIN := 0.3
const ORRERY_SCALE_MAX := 4.0
const AR_PLACE_DISTANCE := 1.2

# Laser-clickable PLAY MISSION panel (metres, in the panel's own space)
const PANEL_SIZE := Vector2(0.32, 0.17)
const PANEL_BUTTON_SIZE := Vector2(0.14, 0.06)
const PANEL_MISSION_CENTER := Vector2(0.0, -0.04)

const VIGNETTE_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	ALBEDO = vec3(0.0);
	ALPHA = smoothstep(0.25, 0.75, length(p)) * strength;
}
"""

var _mode := XRMode.DESKTOP
var _manager : Node
var _game : SolarSystem

var _camera : XRCamera3D
var _left : XRController3D
var _right : XRController3D
var _head_visuals : Node3D
var _left_visuals : Node3D
var _right_visuals : Node3D
var _laser_pivot : Node3D
var _laser_material : StandardMaterial3D
var _hud_label : Label3D
var _msg_label : Label3D
var _target_label : Label3D
var _vignette : MeshInstance3D
var _vignette_material : ShaderMaterial
var _arc_mesh : ImmediateMesh
var _arc_instance : MeshInstance3D
var _arc_material : StandardMaterial3D
var _reticle : MeshInstance3D
var _orrery : XROrrery

# PLAY MISSION panel
var _panel : Node3D
var _panel_title : Label3D
var _panel_mission_mat : StandardMaterial3D
var _panel_hover := 0 # 0 none, 2 mission

var _spawned := false
var _hint_time := 0.0
var _loading_text := ""
var _hud_timer := 0.0
var _prev_buttons := {}

# Following (VR)
var _prev_target := Transform3D()
var _cur_target := Transform3D()
var _have_samples := false
var _reset_ticks := 0
var _last_state := -1
var _walk_yaw := 0.0
var _smooth_locomotion := true
var _snap_latch := false
var _prev_origin_basis := Basis()
var _vignette_strength := 0.0

# Teleport (VR on foot)
var _aiming_teleport := false
var _teleport_valid := false
var _teleport_target := Vector3()

# Pointing
var _pointed : StellarBody = null
var _hold_body : StellarBody = null
var _hold_time := 0.0
var _warp_latch := false

# AR
var _ar_scale := 1.0 # user scale of the tabletop model
var _ar_yaw := 0.0
var _ar_surface_y := 0.0
var _ar_anchor_real := Vector3(0, 0, -AR_PLACE_DISTANCE) # tracking-space metres
var _ar_placing := true
var _ar_needs_init := true
var _ar_selected : StellarBody = null # last planet tapped in the model


func setup(manager: Node, game: SolarSystem) -> void:
	_manager = manager
	_game = game


func _ready() -> void:
	# Sample the chase camera after it has moved this physics tick
	process_physics_priority = 10

	_camera = XRCamera3D.new()
	_camera.name = "XRCamera"
	add_child(_camera)

	_left = _make_controller(&"left_hand", &"default")
	_right = _make_controller(&"right_hand", &"aim")
	_build_visuals()
	_build_panel()

	_orrery = XROrrery.new()
	_orrery.name = "Orrery"
	_orrery.setup(_game)
	_orrery.visible = false
	add_child(_orrery)
	# The rig's own visuals must also be drawn by the AR camera (which only renders one layer)
	_add_layer_recursive(self)

	_game.loading_progressed.connect(_on_loading_progressed)
	_game.player_spawned.connect(_on_player_spawned)
	_game.reference_body_changed.connect(_on_reference_body_changed)

	# Until the player exists, sit where the ship will spawn
	global_transform = _game.get_spawn_transform()
	_spawned = _game.get_game_camera() != null
	_cur_target = global_transform
	_prev_target = global_transform


func set_mode(mode: int) -> void:
	_mode = mode
	var xr := mode != XRMode.DESKTOP
	visible = xr
	set_process(xr)
	set_physics_process(xr)

	if xr:
		_camera.make_current()
	else:
		_release_game_controls()
		var game_camera := _game.get_game_camera()
		if game_camera != null:
			game_camera.make_current()

	# AR: only the tabletop model (and the rig's own visuals) are rendered, so the real-size
	# Solar System does not cover the passthrough image
	var ar := mode == XRMode.AR
	_camera.cull_mask = XROrrery.LAYER if ar else 0xFFFFF
	_orrery.visible = ar
	_reticle.visible = ar and _ar_placing
	_target_label.visible = false
	if ar:
		_ar_needs_init = true
		_ar_placing = true
		show_hint("AR: aim at a surface and pull the trigger to place the Solar System.\n"
			+ "Right stick: rotate / scale. Touch the table + left grip: set table height.", 8.0)
	_have_samples = false
	_reset_ticks = 3
	_update_camera_clip()


func show_hint(text: String, seconds: float) -> void:
	if _msg_label == null:
		return
	_msg_label.text = text
	_msg_label.visible = true
	_hint_time = seconds


# ── Construction ─────────────────────────────────────────────────────────────

func _make_controller(tracker: StringName, pose: StringName) -> XRController3D:
	var c := XRController3D.new()
	c.name = String(tracker)
	c.tracker = tracker
	c.pose = pose
	add_child(c)
	return c


func _flat_material(color: Color, no_depth := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.no_depth_test = no_depth
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _make_label(font_size: int) -> Label3D:
	var l := Label3D.new()
	l.font_size = font_size
	l.pixel_size = 0.0007
	l.no_depth_test = true
	l.shaded = false
	l.double_sided = true
	l.outline_size = 8
	l.render_priority = 100
	l.outline_render_priority = 99
	return l


# Everything attached to the rig is authored in real-world metres.
func _build_visuals() -> void:
	# Controllers
	_left_visuals = Node3D.new()
	_left.add_child(_left_visuals)
	_right_visuals = Node3D.new()
	_right.add_child(_right_visuals)
	for v in [_left_visuals, _right_visuals]:
		var body := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.04, 0.04, 0.12)
		body.mesh = box
		body.material_override = _flat_material(Color(0.25, 0.27, 0.32))
		v.add_child(body)

	# Laser pointer on the right hand (unit length along -Z, stretched by scale.z)
	_laser_pivot = Node3D.new()
	_right_visuals.add_child(_laser_pivot)
	var laser := MeshInstance3D.new()
	var laser_mesh := BoxMesh.new()
	laser_mesh.size = Vector3(0.004, 0.004, 1.0)
	laser.mesh = laser_mesh
	laser.position = Vector3(0, 0, -0.5)
	_laser_material = _flat_material(Color(1, 1, 1, 0.8), true)
	laser.material_override = _laser_material
	_laser_pivot.add_child(laser)
	_laser_pivot.scale = Vector3(1, 1, 3.0)

	# Wrist HUD on the left hand
	_hud_label = _make_label(40)
	_hud_label.position = Vector3(0, 0.08, 0.02)
	_hud_label.rotation_degrees = Vector3(-60, 0, 0)
	_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hud_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_left_visuals.add_child(_hud_label)

	# Head-locked message (loading progress and hints) and comfort vignette
	_head_visuals = Node3D.new()
	_camera.add_child(_head_visuals)
	_msg_label = _make_label(48)
	_msg_label.position = Vector3(0, -0.12, -1.2)
	_msg_label.text = "Loading..."
	_head_visuals.add_child(_msg_label)

	_vignette = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	_vignette.mesh = quad
	_vignette.position = Vector3(0, 0, -0.3)
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER_CODE
	_vignette_material = ShaderMaterial.new()
	_vignette_material.shader = shader
	_vignette_material.render_priority = 127
	_vignette.material_override = _vignette_material
	_vignette.visible = false
	_vignette.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_head_visuals.add_child(_vignette)

	# Teleport arc (world space)
	_arc_mesh = ImmediateMesh.new()
	_arc_material = _flat_material(Color(0.4, 1.0, 0.6), true)
	_arc_instance = MeshInstance3D.new()
	_arc_instance.mesh = _arc_mesh
	_arc_instance.material_override = _arc_material
	_arc_instance.top_level = true
	_arc_instance.visible = false
	add_child(_arc_instance)

	# AR placement reticle (in rig space, moved to the anchor point)
	_reticle = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.15
	disc.bottom_radius = 0.15
	disc.height = 0.004
	_reticle.mesh = disc
	_reticle.material_override = _flat_material(Color(0.4, 0.8, 1.0, 0.6), true)
	_reticle.visible = false
	add_child(_reticle)


	# Floating label above a pointed planet in AR (world space)
	_target_label = _make_label(48)
	_target_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_target_label.top_level = true
	_target_label.visible = false
	add_child(_target_label)


# The PLAY MISSION panel: a small plate floating at the lower right of the view with a single
# button the right laser can point at. It mirrors the 2D dialog in planet_interaction_dialog.gd
# (which a headset cannot show) and calls the same activate_mission().
func _build_panel() -> void:
	_panel = Node3D.new()
	_panel.name = "InteractionPanel"
	_panel.position = Vector3(0.24, -0.16, -0.65)
	_panel.rotation_degrees = Vector3(0, -14, 0)
	_panel.visible = false
	_head_visuals.add_child(_panel)

	var bg := MeshInstance3D.new()
	var bg_mesh := QuadMesh.new()
	bg_mesh.size = PANEL_SIZE
	bg.mesh = bg_mesh
	bg.material_override = _flat_material(Color(0.04, 0.07, 0.16, 0.9), true)
	_panel.add_child(bg)

	_panel_title = _make_label(40)
	_panel_title.position = Vector3(0, 0.05, 0.003)
	_panel.add_child(_panel_title)

	_panel_mission_mat = _flat_material(Color(0.92, 0.62, 0.14, 0.95), true)
	_make_panel_button(PANEL_MISSION_CENTER, _panel_mission_mat, "▶  BEGIN MISSION")


func _make_panel_button(center: Vector2, mat: StandardMaterial3D, text: String) -> void:
	var b := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = PANEL_BUTTON_SIZE
	b.mesh = q
	b.material_override = mat
	b.position = Vector3(center.x, center.y, 0.002)
	_panel.add_child(b)
	var l := _make_label(34)
	l.text = text
	l.position = Vector3(center.x, center.y, 0.004)
	_panel.add_child(l)


# ── Game callbacks ───────────────────────────────────────────────────────────

func _on_loading_progressed(info) -> void:
	if info.finished:
		_loading_text = ""
		if _hint_time <= 0.0:
			_msg_label.visible = false
		return
	_loading_text = "%s  (%d%%)" % [info.message, int(info.progress * 100.0)]
	if _hint_time <= 0.0:
		_msg_label.text = _loading_text
		_msg_label.visible = true


func _on_player_spawned() -> void:
	_spawned = true
	_have_samples = false
	_reset_ticks = 3


func _on_reference_body_changed(_info) -> void:
	# The world is teleported: don't interpolate across the jump
	_reset_ticks = 3


func _release_game_controls() -> void:
	var ship : Ship = _game.get_ship()
	if ship != null:
		ship.get_controller().xr_override = false
		ship.set_move_cmd(Vector3())
		ship.set_turn_cmd(Vector3())
		ship.set_superspeed_cmd(false)
	var ch := _game.get_character()
	if ch != null:
		var cc = ch.get_node_or_null("Controller")
		if cc != null:
			cc.xr_motor = Vector3()
			cc.xr_aim = null


# ── Input helpers ────────────────────────────────────────────────────────────

func _stick(c: XRController3D) -> Vector2:
	var v := c.get_vector2(&"primary")
	if v.length() < DEADZONE:
		return Vector2.ZERO
	return v


func _trigger(c: XRController3D) -> bool:
	return c.get_float(&"trigger") > TRIGGER_THRESHOLD or c.is_button_pressed(&"trigger_click")


func _grip(c: XRController3D) -> bool:
	return c.get_float(&"grip") > TRIGGER_THRESHOLD or c.is_button_pressed(&"grip_click")


# Edge detection. Call at most once per key per frame.
func _edge(key: String, now: bool) -> bool:
	var was : bool = _prev_buttons.get(key, false)
	_prev_buttons[key] = now
	return now and not was


# ── Per-frame ────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _mode == XRMode.DESKTOP:
		return

	if _hint_time > 0.0:
		_hint_time -= delta
		if _hint_time <= 0.0:
			_msg_label.visible = _loading_text != ""
			_msg_label.text = _loading_text

	var a_pressed := _edge("right_a", _right.is_button_pressed(&"ax_button"))
	var b_pressed := _edge("right_b", _right.is_button_pressed(&"by_button"))
	var x_pressed := _edge("left_x", _left.is_button_pressed(&"ax_button"))
	var y_pressed := _edge("left_y", _left.is_button_pressed(&"by_button"))
	var menu_pressed := _edge("left_menu", _left.is_button_pressed(&"menu_button"))
	var trig_now := _trigger(_right)
	var trig_pressed := _edge("right_trigger", trig_now)
	var ltrig_pressed := _edge("left_trigger", _trigger(_left))
	var lgrip_now := _grip(_left)
	var lgrip_pressed := _edge("left_grip", lgrip_now)
	var rgrip_pressed := _edge("right_grip", _grip(_right))
	var lclick_pressed := _edge("left_click", _left.is_button_pressed(&"primary_click"))
	var rclick_pressed := _edge("right_click", _right.is_button_pressed(&"primary_click"))

	if y_pressed and _manager != null:
		_manager.toggle_vr_ar()
		return
	# Mission science debrief: A or the trigger continues (the 2D panel cannot be clicked in a headset)
	var missions := _game.get_mission_manager()
	if missions != null and missions.is_debrief_open():
		if a_pressed or trig_pressed:
			missions.confirm_debrief()
		a_pressed = false
		trig_pressed = false
		trig_now = false


	# PLAY MISSION panel: laser button press or controller shortcuts. A trigger press
	# that hit a panel button must not also dig / warp / place, so it is consumed here.
	# Left X starts the mission; left menu button dismisses the panel.
	var panel_open := _update_panel()
	if panel_open:
		if trig_pressed and _panel_hover != 0:
			_activate_panel_button(_panel_hover)
			trig_pressed = false
			trig_now = false
		if x_pressed:
			_activate_panel_button(2)
			x_pressed = false
		if menu_pressed:
			var dialog := _game.get_planet_dialog()
			if dialog != null:
				dialog.activate_close()
	if _panel_hover != 0:
		# Pointing at the panel: the trigger is for the panel only
		trig_now = false
		trig_pressed = false
		ltrig_pressed = false

	var ship : Ship = _game.get_ship()
	var flying := ship != null and ship.is_flying()
	var character := _game.get_character()
	var walking := not flying and character != null

	var state := 0 if flying else (1 if walking else 2)
	if state != _last_state:
		_last_state = state
		_reset_ticks = 3
		_have_samples = false
		if not walking:
			_walk_yaw = 0.0

	if _mode == XRMode.AR:
		_process_ar_input(delta, trig_pressed, lgrip_now, lgrip_pressed, x_pressed, rclick_pressed)
	elif x_pressed:
		XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)

	var adjusting_ar := _mode == XRMode.AR and (_ar_placing or lgrip_now)

	if flying:
		_drive_ship(ship, a_pressed, adjusting_ar)
		if lgrip_pressed and _mode == XRMode.VR:
			ship.toggle_flashlight()
	elif walking:
		_drive_character(character, a_pressed, b_pressed, trig_pressed, ltrig_pressed,
			rgrip_pressed, lgrip_pressed, lclick_pressed, adjusting_ar)

	if not walking:
		_aiming_teleport = false
		_arc_instance.visible = false

	_update_follow()
	_update_camera_clip()
	_update_pointer(delta, trig_now, flying)
	_update_hud(delta, flying)
	_update_vignette(delta, walking)



func _physics_process(_delta: float) -> void:
	# Samples for smooth (interpolated) following at the headset's refresh rate
	if _mode != XRMode.VR or not _spawned:
		return
	var ch := _game.get_character()
	var ship : Ship = _game.get_ship()
	var target : Transform3D
	if ship != null and not ship.is_flying() and ch != null:
		target = _walk_transform(ch)
	else:
		var cam := _game.get_game_camera()
		if cam == null:
			return
		target = cam.global_transform
	if _reset_ticks > 0 or not _have_samples:
		_reset_ticks = maxi(_reset_ticks - 1, 0)
		_prev_target = target
		_cur_target = target
		_have_samples = true
	else:
		_prev_target = _cur_target
		_cur_target = target


func _walk_transform(ch: Node3D) -> Transform3D:
	var t := ch.global_transform
	t.basis = (t.basis * Basis(Vector3.UP, _walk_yaw)).orthonormalized()
	return t


# ── PLAY MISSION panel ───────────────────────────────────────────────────────

# Shows the panel while the 2D dialog is open and updates which button the right laser is on.
# Returns whether the panel is open.
func _update_panel() -> bool:
	var dialog := _game.get_planet_dialog()
	var open : bool = dialog != null and dialog.visible
	_panel.visible = open
	_panel_hover = 0
	if not open:
		return false
	_panel_title.text = "%s" % dialog.get_current_body_name().to_upper()

	var aim := _right.global_transform
	_panel_hover = _panel_button_under_ray(aim.origin, -aim.basis.z)
	_panel_mission_mat.albedo_color = Color(1.0, 0.75, 0.25, 1.0) if _panel_hover == 2 \
		else Color(0.92, 0.62, 0.14, 0.95)
	return true


# 0 = none, 2 = PLAY MISSION (kept as 2 so existing button-code paths still map cleanly)
func _panel_button_under_ray(origin: Vector3, dir: Vector3) -> int:
	var inv := _panel.global_transform.affine_inverse()
	var lo := inv * origin
	var ld := inv.basis * dir
	if absf(ld.z) < 0.0001:
		return 0
	var t := -lo.z / ld.z
	if t < 0.0:
		return 0
	var p := lo + ld * t
	var v := Vector2(p.x, p.y)
	if _in_rect(v, PANEL_MISSION_CENTER, PANEL_BUTTON_SIZE):
		return 2
	return 0


static func _in_rect(p: Vector2, center: Vector2, size: Vector2) -> bool:
	return absf(p.x - center.x) <= size.x * 0.5 and absf(p.y - center.y) <= size.y * 0.5


func _activate_panel_button(button: int) -> void:
	var dialog := _game.get_planet_dialog()
	if dialog == null:
		return
	if button == 2:
		dialog.activate_mission()
	_right.trigger_haptic_pulse(&"haptic", 0.0, 0.5, 0.1, 0.0)


# ── Ship / character control ─────────────────────────────────────────────────

func _drive_ship(ship: Ship, exit_pressed: bool, adjusting_ar: bool) -> void:
	var sc := ship.get_controller()
	sc.xr_override = true
	var l := _stick(_left)
	var r := _stick(_right)
	if adjusting_ar:
		r = Vector2.ZERO
	ship.set_move_cmd(Vector3(0, 0, l.y))
	# Same conventions as the mouse/keyboard: x = yaw (stick right turns right),
	# y = pitch (stick up pitches up), z = roll (stick right rolls right)
	ship.set_turn_cmd(Vector3(-r.x, r.y, l.x) * FLIGHT_TURN_GAIN)
	ship.set_superspeed_cmd(_grip(_right) and not adjusting_ar)
	if exit_pressed:
		sc.request_exit_ship()


func _drive_character(ch: Node3D, jump: bool, return_to_ship: bool, dig: bool, build: bool,
		waypoint: bool, flashlight: bool, toggle_smooth: bool, adjusting_ar: bool) -> void:
	var cc = ch.get_node_or_null("Controller")
	if cc == null:
		return
	cc.xr_aim = _right
	if toggle_smooth:
		_smooth_locomotion = not _smooth_locomotion
		show_hint("Smooth movement " + ("on" if _smooth_locomotion else "off (teleport only)"), 2.0)

	var l := _stick(_left)
	cc.xr_motor = Vector3(l.x, 0.0, -l.y) if _smooth_locomotion else Vector3()

	# The character's movement is relative to its Head node, so align that with the gaze
	var head : Node3D = ch.get_node_or_null("Head")
	if head != null:
		head.global_transform.basis = _camera.global_transform.basis.orthonormalized()

	if adjusting_ar:
		return

	if jump:
		cc.xr_action(&"jump")
	if return_to_ship:
		cc.xr_action(&"return_ship")
	if dig:
		cc.xr_action(&"dig")
	if build:
		cc.xr_action(&"build")
	if waypoint:
		cc.xr_action(&"waypoint")
	if flashlight:
		cc.xr_action(&"flashlight")

	# Right stick: teleport (forward) and snap turn (sideways)
	var r := _right.get_vector2(&"primary")
	if r.y > 0.7 and absf(r.x) < 0.5:
		_aiming_teleport = true
		_update_teleport_arc(ch)
	elif _aiming_teleport:
		_aiming_teleport = false
		_arc_instance.visible = false
		if _teleport_valid:
			var t := ch.global_transform
			t.origin = _teleport_target
			ch.global_transform = t
			_reset_ticks = 3
			_have_samples = false

	if not _aiming_teleport:
		if absf(r.x) > 0.8 and not _snap_latch:
			_snap_latch = true
			_walk_yaw += deg_to_rad(-signf(r.x) * SNAP_TURN_DEGREES)
			_reset_ticks = 3
			_have_samples = false
		elif absf(r.x) < 0.4:
			_snap_latch = false


func _update_teleport_arc(ch: Node3D) -> void:
	var up := ch.global_transform.basis.y
	var aim := _right.global_transform
	var p := aim.origin
	var v := -aim.basis.z * 8.0
	var g := -up * 9.8
	var dt := 0.05
	var space := _right.get_world_3d().direct_space_state
	var points := PackedVector3Array([p])
	_teleport_valid = false
	for i in TELEPORT_STEPS:
		var np := p + v * dt + 0.5 * g * dt * dt
		v += g * dt
		var query := PhysicsRayQueryParameters3D.create(p, np)
		query.exclude = [ch.get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			points.append(hit.position)
			if hit.normal.dot(up) > 0.6:
				_teleport_valid = true
				_teleport_target = hit.position + up * 0.05
			break
		p = np
		points.append(p)

	_arc_instance.visible = true
	_arc_instance.global_transform = Transform3D()
	_arc_material.albedo_color = \
		Color(0.4, 1.0, 0.6) if _teleport_valid else Color(1.0, 0.35, 0.3)
	_arc_mesh.clear_surfaces()
	_arc_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for pt in points:
		_arc_mesh.surface_add_vertex(pt)
	_arc_mesh.surface_end()


# ── Following ────────────────────────────────────────────────────────────────

func _update_follow() -> void:
	# Both VR and AR follow the chase camera / character (AR only for audio and to keep the real
	# world simulation and the rig in the same place; the tabletop model is fixed to the room)
	if not _spawned or not _have_samples:
		return
	var t := Engine.get_physics_interpolation_fraction()
	global_transform = _prev_target.interpolate_with(_cur_target, clampf(t, 0.0, 1.0))


func _update_camera_clip() -> void:
	if _mode == XRMode.AR:
		# Only the tabletop model is rendered: a tight range gives good depth precision
		_camera.near = 0.03
		_camera.far = 50.0
		return
	var far_clip := 300000.0
	var game_camera := _game.get_game_camera()
	if game_camera != null:
		far_clip = maxf(far_clip, game_camera.far)
	_camera.near = 0.1
	_camera.far = far_clip


# ── AR ───────────────────────────────────────────────────────────────────────

func _process_ar_input(delta: float, trig_pressed: bool, lgrip_now: bool, lgrip_pressed: bool,
		replace_pressed: bool, reset_pressed: bool) -> void:
	if _ar_needs_init and _camera.position != Vector3.ZERO:
		_ar_needs_init = false
		var fwd := -_camera.transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
		_ar_anchor_real = _camera.position + fwd * AR_PLACE_DISTANCE
		_ar_anchor_real.y = _ar_surface_y

	if replace_pressed:
		_ar_placing = true
		_ar_needs_init = true
	if reset_pressed:
		_ar_yaw = 0.0
		_ar_scale = 1.0

	if _ar_placing or lgrip_now:
		var r := _stick(_right)
		_ar_yaw -= r.x * delta * 1.5
		_ar_scale = clampf(_ar_scale * exp(r.y * delta * 1.2), ORRERY_SCALE_MIN, ORRERY_SCALE_MAX)

	if _ar_placing:
		var p := _right.position
		var d := -_right.transform.basis.z
		if lgrip_pressed:
			# Touch the table with the controller and squeeze the left grip
			_ar_surface_y = p.y
			show_hint("Table height set", 1.5)
		if d.y < -0.05:
			var t := (_ar_surface_y - p.y) / d.y
			if t > 0.05 and t < 8.0:
				_ar_anchor_real = p + d * t
		_ar_anchor_real.y = _ar_surface_y
		if trig_pressed:
			_ar_placing = false
			show_hint("Placed. Trigger-tap a planet to highlight it, hold to fast travel.", 4.0)

	_reticle.visible = _ar_placing
	_reticle.position = _ar_anchor_real

	# The model lives in the room (rig space), a little above the table
	if _orrery.try_build():
		_orrery.set_user_scale(_ar_scale)
		_orrery.position = _ar_anchor_real + Vector3(0, 0.1 * _ar_scale, 0)
		_orrery.rotation = Vector3(0, _ar_yaw, 0)
		_orrery.update_layout()


func _unhandled_input(event: InputEvent) -> void:
	# Touch fallback for handheld AR: tap = (re)place in front of the device, pinch = scale
	if _mode != XRMode.AR:
		return
	if event is InputEventScreenTouch and event.pressed:
		if _ar_placing:
			_ar_placing = false
		else:
			_ar_placing = true
			_ar_needs_init = true
	elif event is InputEventMagnifyGesture:
		_ar_scale = clampf(_ar_scale / maxf(event.factor, 0.01), ORRERY_SCALE_MIN, ORRERY_SCALE_MAX)


# ── Pointing / interaction ───────────────────────────────────────────────────

func _pick_body(origin: Vector3, dir: Vector3) -> StellarBody:
	if _mode == XRMode.AR:
		return _orrery.pick(origin, dir) if _orrery.is_built() else null
	var best : StellarBody = null
	var best_t := INF
	for i in _game.get_stellar_body_count():
		var b : StellarBody = _game.get_stellar_body(i)
		if b.node == null:
			continue
		var center := b.node.global_transform.origin
		var t := (center - origin).dot(dir)
		if t < 0.0:
			continue
		var miss := (center - (origin + dir * t)).length()
		var pick_radius := b.radius
		if miss <= pick_radius and t < best_t:
			best_t = t
			best = b
	return best


func _update_pointer(delta: float, trig_now: bool, flying: bool) -> void:
	var aim := _right.global_transform
	_pointed = _pick_body(aim.origin, -aim.basis.z)
	if _panel_hover != 0:
		_pointed = null
	_laser_material.albedo_color = Color(0.4, 1.0, 0.5, 0.9) if (_pointed != null or _panel_hover != 0) \
		else Color(1, 1, 1, 0.6)
	_laser_pivot.scale = Vector3(1, 1, 3.0 if _pointed == null else 6.0)

	# AR: an info label floating above the pointed (or last tapped) planet of the model
	var labelled := _pointed if _pointed != null else _ar_selected
	if _mode == XRMode.AR and labelled != null and _orrery.is_built():
		_target_label.visible = true
		_target_label.text = "%s\nDiameter %d m" % [labelled.name, int(labelled.radius * 2.0)]
		_target_label.global_position = _orrery.get_display_center(labelled) \
			+ Vector3.UP * (_orrery.get_display_radius(labelled) * 2.2 + 0.05)
	else:
		_target_label.visible = false

	# Trigger on a planet: tap = select (AR), hold = fast travel
	var pointer_owns_trigger := flying or _mode == XRMode.AR
	if not pointer_owns_trigger or (_mode == XRMode.AR and _ar_placing):
		_hold_body = null
		_hold_time = 0.0
		return

	if trig_now:
		if _pointed != null and _pointed == _hold_body:
			_hold_time += delta
		else:
			_hold_body = _pointed
			_hold_time = 0.0
		if _hold_body != null and _hold_time >= HOLD_TO_WARP_TIME and not _warp_latch \
		and _game.can_fast_travel() and _hold_body != _game.get_reference_stellar_body() \
		and _hold_body.type != StellarBody.TYPE_SUN:
			_warp_latch = true
			_game.fast_travel_now(_hold_body)
	else:
		if _mode == XRMode.AR and _hold_body != null and _hold_time < FOCUS_TAP_TIME \
		and not _warp_latch:
			_ar_selected = _hold_body
		_warp_latch = false
		_hold_body = null
		_hold_time = 0.0


func _update_hud(delta: float, flying: bool) -> void:
	_hud_timer -= delta
	if _hud_timer > 0.0:
		return
	_hud_timer = 0.25

	var lines := PackedStringArray()
	lines.append("%s mode" % XRMode.get_mode_name(_mode))
	var ship : Ship = _game.get_ship()
	if ship != null:
		var ref : StellarBody = _game.get_reference_stellar_body()
		lines.append("Reference: %s" % ref.name)
		lines.append("Speed: %d m/s" % int(ship.linear_velocity.length()))
		if ref.type != StellarBody.TYPE_SUN:
			var alt := ref.node.global_transform.origin.distance_to(ship.global_transform.origin) \
				- ref.radius
			lines.append("Altitude: %d m" % int(alt))
		if not flying:
			lines.append("On foot")
	if _mode == XRMode.AR:
		lines.append("Model scale x%.2f" % _ar_scale)
	if _pointed != null:
		lines.append("> %s  (diameter %d m)" % [_pointed.name, int(_pointed.radius * 2.0)])
		if _hold_body == _pointed and _hold_time > FOCUS_TAP_TIME and not _warp_latch:
			lines.append("Warping in %.1f s..." % maxf(HOLD_TO_WARP_TIME - _hold_time, 0.0))
	# The 2D mission HUD cannot be seen in a headset, so mirror it here
	var missions := _game.get_mission_manager()
	if missions != null and missions.is_mission_active():
		lines.append(missions.get_hud_text())
	_hud_label.text = "\n".join(lines)


func _update_vignette(delta: float, walking: bool) -> void:
	# Comfort: darken the periphery while the rig rotates (ship turning, snap turn) or moves
	var b := global_transform.basis.orthonormalized()
	var angle := Quaternion(_prev_origin_basis).angle_to(Quaternion(b))
	_prev_origin_basis = b
	var target := 0.0
	if _reset_ticks == 0 and delta > 0.0:
		target = clampf(angle / delta * 0.5, 0.0, 0.75)
	if walking and _smooth_locomotion:
		target = maxf(target, _stick(_left).length() * 0.3)
	_vignette_strength = lerpf(_vignette_strength, target, 1.0 - exp(-6.0 * delta))
	_vignette.visible = _vignette_strength > 0.01 and _mode != XRMode.AR
	_vignette_material.set_shader_parameter(&"strength", _vignette_strength)


func _add_layer_recursive(n: Node) -> void:
	if n is VisualInstance3D:
		n.layers |= XROrrery.LAYER
	for c in n.get_children():
		_add_layer_recursive(c)
