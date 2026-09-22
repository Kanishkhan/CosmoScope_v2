extends Control
# PlanetInteractionDialog
# Shown when the player approaches a walkable planet on foot.
#
# Two visual states:
#   • Full panel — offers "Begin Mission" and a small ✕ dismiss button
#   • Mini badge — a small "▶ <PLANET>  ·  Press M" pill in the corner, shown after the player
#     dismisses the full panel. Click it or press M to reopen the full panel.
#
# The whole thing auto-hides when the player leaves the planet's vicinity (driven by
# SolarSystem calling `dismiss()`).

signal mission_pressed(body_name: String)
signal dismissed

# ── Mission descriptions per planet (tagline - body) ──────────────────────────
const MISSION_DESCRIPTIONS := {
	"Mercury": "Extreme World - survive +430 °C sun and -170 °C shade while recovering 4 instruments.",
	"Venus":   "Into the Inferno - 92 bar, 465 °C: scan a vent, dig basalt, deploy a seismometer.",
	"Earth":   "Planet of Life - survey the biosphere, hydrosphere and atmosphere; watch the water cycle.",
	"Moon":    "Lunar Expedition - 1/6 g hops to the rim, regolith digging and Earth observation.",
	"Mars":    "Search for Life - detect and dig ancient-water evidence, survive dust storms.",
}

@onready var _panel           : Panel  = $Panel
@onready var _title_label     : Label  = $Panel/Margin/VBox/HeaderRow/TitleLabel
@onready var _status_badge    : Label  = $Panel/Margin/VBox/HeaderRow/StatusBadge
@onready var _close_btn       : Button = $Panel/Margin/VBox/HeaderRow/CloseBtn
@onready var _tagline_label   : Label  = $Panel/Margin/VBox/MissionTagline
@onready var _desc_label      : Label  = $Panel/Margin/VBox/MissionDesc
@onready var _mission_btn     : Button = $Panel/Margin/VBox/MissionBtn
@onready var _min_badge       : Button = $MinBadge

var _current_body_name := ""


func _ready() -> void:
	hide()
	_min_badge.visible = false
	_mission_btn.pressed.connect(_on_mission)
	_close_btn.pressed.connect(_on_close)
	_min_badge.pressed.connect(_on_reopen)
	set_process_unhandled_key_input(true)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# Full panel visible: normal controls
	if _panel.visible:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_P:
				_on_mission()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_on_close()
				get_viewport().set_input_as_handled()
			KEY_M:
				_on_mission()
				get_viewport().set_input_as_handled()
		return
	# Full panel dismissed, mini badge showing: M reopens
	if _min_badge.visible and event.keycode == KEY_M:
		_on_reopen()
		get_viewport().set_input_as_handled()


# ── Public API ───────────────────────────────────────────────────────────────

func show_for_planet(body_name: String) -> void:
	_current_body_name = body_name
	_title_label.text = body_name.to_upper()
	_status_badge.text = "IN RANGE"
	_status_badge.add_theme_color_override("font_color", Color(0.55, 1.0, 0.7, 1.0))

	var raw : String = String(MISSION_DESCRIPTIONS.get(body_name,
		"Planetary mission available on %s." % body_name))
	# Split "Tagline - body" so the tagline can be shown as a highlighted headline
	var split_idx := raw.find(" - ")
	if split_idx != -1:
		_tagline_label.text = raw.substr(0, split_idx).to_upper()
		_desc_label.text = raw.substr(split_idx + 3)
	else:
		_tagline_label.text = "MISSION AVAILABLE"
		_desc_label.text = raw

	_min_badge.text = "▶ %s  ·  Press M" % body_name.to_upper()

	_show_full_panel()


## Called by SolarSystem when the player leaves the planet's vicinity: hide everything.
func dismiss() -> void:
	if visible:
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.2)
		tw.tween_callback(_hide_all)
	else:
		_hide_all()


func get_current_body_name() -> String:
	return _current_body_name


# ── Input from gamepad / XR ──────────────────────────────────────────────────
# Gamepad: A / X = mission (or reopen if minimized), B = dismiss.
# XR: laser/trigger presses call activate_mission() / activate_close().

func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventJoypadButton) or not event.pressed:
		return
	match event.button_index:
		JOY_BUTTON_A, JOY_BUTTON_X:
			if _panel.visible:
				_on_mission()
			elif _min_badge.visible:
				_on_reopen()
			get_viewport().set_input_as_handled()
		JOY_BUTTON_B:
			if _panel.visible:
				_on_close()
				get_viewport().set_input_as_handled()


func activate_mission() -> void:
	if _panel.visible:
		_on_mission()


func activate_close() -> void:
	if _panel.visible:
		_on_close()


# ── Internal handlers ────────────────────────────────────────────────────────

func _on_mission() -> void:
	mission_pressed.emit(_current_body_name)


func _on_close() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	dismissed.emit()
	_hide_panel_show_badge()


func _on_reopen() -> void:
	_show_full_panel()


# ── Show / hide helpers ──────────────────────────────────────────────────────

func _show_full_panel() -> void:
	show()
	_panel.visible = true
	_panel.modulate.a = 0.0
	_min_badge.visible = false
	modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 1.0, 0.22)


func _hide_panel_show_badge() -> void:
	# Fade the panel out then show the mini badge in the same corner
	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 0.0, 0.18)
	tw.tween_callback(func():
		_panel.visible = false
		_panel.modulate.a = 1.0
		_min_badge.modulate.a = 0.0
		_min_badge.visible = true
		show()
		modulate.a = 1.0
		var tw2 := create_tween()
		tw2.tween_property(_min_badge, "modulate:a", 1.0, 0.2))


func _hide_all() -> void:
	_panel.visible = false
	_min_badge.visible = false
	hide()
	modulate.a = 1.0
	_panel.modulate.a = 1.0
	_min_badge.modulate.a = 1.0
