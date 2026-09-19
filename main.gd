extends Node

const Settings = preload("res://settings.gd")
const XRManager = preload("res://xr/xr_manager.gd")

@onready var _main_menu : Control = $MainMenu
@onready var _settings_ui : Control = $SettingsUI

var _settings := Settings.new()
var _game : SolarSystem
var _xr : XRManager


func _ready():
	_settings_ui.set_settings(_settings)

	# XR (VR/AR) is optional: without a headset/OpenXR runtime this stays in desktop mode
	_xr = XRManager.new()
	_xr.name = "XRManager"
	add_child(_xr)
	_xr.setup()
	if _xr.is_xr_active():
		# The 2D main menu is not visible in a headset: start the game directly
		_on_MainMenu_start_requested.call_deferred()


func _on_MainMenu_start_requested():
	assert(_game == null)
	_main_menu.hide()
	var game_scene : PackedScene = load("res://game.tscn")
	_game = game_scene.instantiate()
	_game.set_settings(_settings)
	_game.set_settings_ui(_settings_ui)
	_game.exit_to_menu_requested.connect(_on_game_exit_to_menu_requested)
	add_child(_game)
	_xr.bind_game(_game)


func _on_MainMenu_settings_requested():
	_settings_ui.show()


func _on_MainMenu_exit_requested():
	get_tree().quit()


func _on_game_exit_to_menu_requested():
	_xr.unbind_game()
	_game.queue_free()
	_game = null
	_main_menu.show()
	if _xr.is_xr_active():
		# No 2D menu in a headset
		get_tree().quit()


func _process(delta):
	AudioServer.set_bus_volume_db(0, linear_to_db(_settings.main_volume_linear))

	DDD.visible = _settings.debug_text

	var viewport := get_viewport()
	if _settings.wireframe != (viewport.debug_draw == Viewport.DEBUG_DRAW_WIREFRAME):
		if _settings.wireframe:
			viewport.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
		else:
			viewport.debug_draw = Viewport.DEBUG_DRAW_DISABLED
		print("Setting viewport draw mode to ", viewport.debug_draw)
	
	if _settings.antialias == Settings.ANTIALIAS_DISABLED:
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	elif _settings.antialias == Settings.ANTIALIAS_FXAA:
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA


func _unhandled_input(event: InputEvent):
	if _game != null:
		# Let the game handle it
		return
	if event is InputEventKey:
		if event.pressed and not event.is_echo():
			if event.keycode == KEY_ESCAPE:
				_settings_ui.hide()
