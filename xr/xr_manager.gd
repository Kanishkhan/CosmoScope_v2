# Owns the XR interface (OpenXR) and the current mode: Desktop, VR or AR.
#
# Desktop is always available and is the default when no headset/runtime is found, so the game
# behaves exactly as before. When OpenXR initializes, the game starts in VR (or in AR with the
# `--ar` command line flag; `--desktop` forces the flat mode). F9 cycles the available modes, and
# the left "Y" controller button toggles VR <-> AR.
#
# AR = the same game rendered over the real world through the headset's passthrough (OpenXR
# alpha-blend/additive environment blend mode or the runtime passthrough), with the Solar System
# scaled down and anchored in the room (see xr_rig.gd).
extends Node

const XRMode = preload("./xr_mode.gd")
const XRRig = preload("./xr_rig.gd")

signal mode_changed(mode)

var mode := XRMode.DESKTOP

var _interface : XRInterface
var _game : SolarSystem
var _rig : XRRig
var _env_backup := {}


func setup() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "--desktop" in args:
		return

	_interface = XRServer.find_interface("OpenXR")
	if _interface == null:
		return
	if not _interface.is_initialized():
		if not _interface.initialize():
			print("XR: OpenXR could not be initialized, staying in desktop mode")
			_interface = null
			return

	print("XR: OpenXR initialized")
	get_viewport().use_xr = true
	# The headset paces frames, the desktop mirror must not
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var wanted := XRMode.VR
	if "--ar" in args and supports_ar():
		wanted = XRMode.AR
	set_mode(wanted)


func is_xr_active() -> bool:
	return mode != XRMode.DESKTOP


func has_xr_interface() -> bool:
	return _interface != null


## True when the runtime can show the real world behind the rendering (passthrough / blend modes).
func supports_ar() -> bool:
	if _interface == null:
		return false
	if _interface.has_method("get_supported_environment_blend_modes"):
		var modes : Array = _interface.call("get_supported_environment_blend_modes")
		for m in modes:
			if m != XRInterface.XR_ENV_BLEND_MODE_OPAQUE:
				return true
	if _interface.has_method("is_passthrough_supported") \
	and _interface.call("is_passthrough_supported"):
		return true
	return false


func set_mode(new_mode: int) -> bool:
	if new_mode != XRMode.DESKTOP and _interface == null:
		return false
	if new_mode == XRMode.AR and not supports_ar():
		push_warning("XR: AR (passthrough) is not supported by this device/runtime")
		if _rig != null:
			_rig.show_hint("AR/passthrough not supported by this device", 4.0)
		return false

	mode = new_mode
	_apply_display_mode()
	_apply_environment()
	if _rig != null:
		_rig.set_mode(mode)
	print("XR: mode is now ", XRMode.get_mode_name(mode))
	mode_changed.emit(mode)
	return true


func cycle_mode() -> void:
	# Desktop -> VR -> AR -> Desktop (skipping what is not available)
	var order := [XRMode.DESKTOP, XRMode.VR, XRMode.AR]
	var i := order.find(mode)
	for step in range(1, order.size() + 1):
		var candidate : int = order[(i + step) % order.size()]
		if set_mode(candidate):
			return


func toggle_vr_ar() -> void:
	if mode == XRMode.VR:
		set_mode(XRMode.AR)
	else:
		set_mode(XRMode.VR)


func bind_game(game: SolarSystem) -> void:
	_game = game
	_env_backup.clear()
	if _interface == null:
		return
	_rig = XRRig.new()
	_rig.name = "XRRig"
	_rig.setup(self, game)
	game.add_child(_rig)
	_apply_environment()
	_rig.set_mode(mode)


func unbind_game() -> void:
	_game = null
	_rig = null
	_env_backup.clear()


func _apply_display_mode() -> void:
	var vp := get_viewport()
	vp.use_xr = mode != XRMode.DESKTOP
	if _interface == null:
		return

	var ar := mode == XRMode.AR
	vp.transparent_bg = ar

	if ar:
		var modes : Array = []
		if _interface.has_method("get_supported_environment_blend_modes"):
			modes = _interface.call("get_supported_environment_blend_modes")
		if XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in modes:
			_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		elif XRInterface.XR_ENV_BLEND_MODE_ADDITIVE in modes:
			_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ADDITIVE
		if _interface.has_method("start_passthrough"):
			_interface.call("start_passthrough")
	else:
		if _interface.has_method("stop_passthrough"):
			_interface.call("stop_passthrough")
		_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE


# In AR the sky/space background must be transparent so the real world shows through.
func _apply_environment() -> void:
	if _game == null:
		return
	var env : Environment = _game.get_environment()
	if env == null:
		return
	if _env_backup.is_empty():
		_env_backup = {
			"background_mode": env.background_mode,
			"background_color": env.background_color,
			"ambient_light_source": env.ambient_light_source,
		}
	if mode == XRMode.AR:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0, 0, 0, 0)
		# Keep the planets lit as before: ambient light still comes from the (hidden) space sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	else:
		env.background_mode = _env_backup["background_mode"]
		env.background_color = _env_backup["background_color"]
		env.ambient_light_source = _env_backup["ambient_light_source"]


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		if _interface != null:
			cycle_mode()
