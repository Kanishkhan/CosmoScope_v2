extends Node
# MissionManager
# Runs the on-foot science missions. Only the five walkable bodies have one - Mercury, Venus, Earth,
# Mars and the Moon - and each has its own script with its own mechanics (see mission_base.gd).
# The gas/ice giants (Jupiter, Saturn, Uranus, Neptune) are flight-only and have no mission.

signal mission_started(planet_name: String)
signal mission_ended(planet_name: String, won: bool)
signal score_changed(score: int)

const SURFACE_MISSION_SCRIPTS := {
	"Mercury": preload("./mercury_mission.gd"),
	"Venus": preload("./venus_mission.gd"),
	"Earth": preload("./earth_mission.gd"),
	"Mars": preload("./mars_mission.gd"),
	"Moon": preload("./moon_mission.gd"),
}

var _current_mission : Node = null
var _current_planet := ""


func has_mission(planet_name: String) -> bool:
	return SURFACE_MISSION_SCRIPTS.has(planet_name)


func start_mission(planet_name: String) -> void:
	if _current_mission != null:
		return # one at a time; finish or abort (Backspace) the running one first
	if not has_mission(planet_name):
		push_warning("%s has no walking mission (flight-only body)." % planet_name)
		return
	var game := get_parent() as SolarSystem
	if game == null or game.get_character() == null:
		push_warning("Missions on %s must be started on foot." % planet_name)
		return
	_current_planet = planet_name
	_current_mission = SURFACE_MISSION_SCRIPTS[planet_name].new(planet_name)
	_current_mission.mission_won.connect(_on_mission_won)
	_current_mission.mission_lost.connect(_on_mission_lost)
	_current_mission.score_changed.connect(func(s): score_changed.emit(s))
	add_child(_current_mission)
	mission_started.emit(planet_name)


func is_mission_active() -> bool:
	return _current_mission != null and is_instance_valid(_current_mission)


## Text of the running mission for HUDs that are not the 2D screen (XR wrist display)
func get_hud_text() -> String:
	if is_mission_active() and "hud_text" in _current_mission:
		return _current_mission.hud_text
	return ""


func is_debrief_open() -> bool:
	return is_mission_active() and _current_mission.has_method("is_debrief_open") \
		and _current_mission.is_debrief_open()


## Closes the science debrief (used by XR, which cannot click the 2D panel)
func confirm_debrief() -> void:
	if is_debrief_open():
		_current_mission.confirm_debrief()


func _on_mission_won() -> void:
	_finish(true)


func _on_mission_lost() -> void:
	_finish(false)


func _finish(won: bool) -> void:
	# The mission frees itself after its debrief
	_current_mission = null
	mission_ended.emit(_current_planet, won)
	_current_planet = ""
