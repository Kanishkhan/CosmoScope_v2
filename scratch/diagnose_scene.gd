extends SceneTree

func _init():
	var f = FileAccess.open("user://diag_out.txt", FileAccess.WRITE)
	if f:
		f.store_line("=== DIAGNOSTIC OUTPUT ===")
		f.store_line("Godot version: " + Engine.get_version_info()["string"])
		var SolarSystemSetup = load("res://solar_system/solar_system_setup.gd")
		var Settings = load("res://settings.gd")
		var settings = Settings.new()
		var bodies = SolarSystemSetup.create_solar_system_data(settings)
		f.store_line("Total bodies: " + str(bodies.size()))
		for b in bodies:
			f.store_line("Body: " + b.name + " type: " + str(b.type) + " radius: " + str(b.radius) + " dist: " + str(b.distance_to_parent))
		f.close()
	quit()
