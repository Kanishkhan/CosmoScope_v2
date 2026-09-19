extends Control
# PlanetInteractionDialog
# Shown when the player approaches a planet.
# Offers two choices: EXPLORE (land) or PLAY MISSION.

signal explore_pressed(body_name: String)
signal mission_pressed(body_name: String)
signal dismissed

# ── Mission descriptions per planet ──────────────────────────────────────────
const MISSION_DESCRIPTIONS := {
	"Mercury": "Extreme World - survive +430 °C sun and -170 °C shade while recovering 4 instruments.",
	"Venus":   "Into the Inferno - 92 bar, 465 °C: scan a vent, dig basalt, deploy a seismometer.",
	"Earth":   "Planet of Life - survey the biosphere, hydrosphere and atmosphere; watch the water cycle.",
	"Moon":    "Lunar Expedition - 1/6 g hops to the rim, regolith digging and Earth observation.",
	"Mars":    "Search for Life - detect and dig ancient-water evidence, survive dust storms.",
}

@onready var _title_label     : Label  = $Panel/Margin/VBox/HeaderRow/TitleLabel
@onready var _status_badge    : Label  = $Panel/Margin/VBox/HeaderRow/StatusBadge
@onready var _mouse_btn       : Button = $Panel/Margin/VBox/HeaderRow/MouseToggleBtn
@onready var _desc_label      : Label  = $Panel/Margin/VBox/MissionDesc
@onready var _explore_btn     : Button = $Panel/Margin/VBox/ButtonRow/ExploreBtn
@onready var _mission_btn     : Button = $Panel/Margin/VBox/ButtonRow/MissionBtn
@onready var _panel           : PanelContainer = $Panel

var _current_body_name := ""
var _is_exploring := false


func _ready() -> void:
	hide()
	_explore_btn.pressed.connect(_on_explore)
	_mission_btn.pressed.connect(_on_mission)
	_mouse_btn.pressed.connect(_on_toggle_mouse)
	set_process_unhandled_key_input(true)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_TAB:
				_on_toggle_mouse()
				get_viewport().set_input_as_handled()
			KEY_E:
				_on_explore()
				get_viewport().set_input_as_handled()
			KEY_M, KEY_P:
				_on_mission()
				get_viewport().set_input_as_handled()


func _on_toggle_mouse() -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_explore_btn.grab_focus()
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func show_for_planet(body_name: String) -> void:
	_current_body_name = body_name
	_is_exploring = false
	_title_label.text = "🪐 " + body_name.to_upper()
	_status_badge.text = "● IN VICINITY"
	_status_badge.add_theme_color_override("font_color", Color(0.4, 0.95, 0.55, 1.0))
	var desc : String = String(MISSION_DESCRIPTIONS.get(body_name,
		"Explore %s or launch planetary mission." % body_name))
	_desc_label.text = desc
	show()

	# Animate in gently at the top-right
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.3)


func set_exploring_mode() -> void:
	_is_exploring = true
	_status_badge.text = "🚀 EXPLORING"
	_status_badge.add_theme_color_override("font_color", Color(0.2, 0.8, 1.0, 1.0))


func dismiss() -> void:
	_dismiss_animated()


func _on_explore() -> void:
	set_exploring_mode()
	# Ensure mouse is captured so character/ship controls immediately work
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	explore_pressed.emit(_current_body_name)


func _on_mission() -> void:
	mission_pressed.emit(_current_body_name)


func _on_dismiss() -> void:
	dismissed.emit()
	_dismiss_animated()


func _dismiss_animated() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(hide)



# ─── Input: gamepad + programmatic (XR) activation ───────────────────────────
# Mouse: the buttons are normal Buttons (Tab frees the mouse while playing).
# Keyboard: E = explore, M/P = mission (see _unhandled_key_input).
# Gamepad: A = explore, B = mission (no need to free the mouse).
# XR: laser/trigger presses call activate_explore()/activate_mission().

func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventJoypadButton) or not event.pressed:
		return
	match event.button_index:
		JOY_BUTTON_A:
			activate_explore()
			get_viewport().set_input_as_handled()
		JOY_BUTTON_B:
			activate_mission()
			get_viewport().set_input_as_handled()


func activate_explore() -> void:
	if visible:
		_on_explore()


func activate_mission() -> void:
	if visible:
		_on_mission()


## Screen-space rectangles of the two buttons (used by XR to build a matching laser panel).
func get_current_body_name() -> String:
	return _current_body_name
