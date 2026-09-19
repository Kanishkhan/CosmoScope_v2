extends SceneTree

func _init():
	print("--- TESTING SHADERS ---")
	var shaders = [
		"res://addons/zylann.atmosphere/shaders/planet_atmosphere_no_clouds.gdshader",
		"res://addons/zylann.atmosphere/shaders/planet_atmosphere_clouds.gdshader",
		"res://addons/zylann.atmosphere/shaders/planet_atmosphere_clouds_high.gdshader",
		"res://addons/zylann.atmosphere/shaders/planet_atmosphere_v1_no_clouds.gdshader",
		"res://addons/zylann.atmosphere/shaders/planet_atmosphere_v1_clouds.gdshader",
		"res://solar_system/materials/planet_ground.gdshader"
	]
	for s_path in shaders:
		var s = load(s_path)
		if s == null:
			print("FAILED TO LOAD: ", s_path)
		else:
			print("Loaded: ", s_path, " RID: ", s.get_rid())
			var sm = ShaderMaterial.new()
			sm.shader = s
			var ulist = RenderingServer.get_shader_parameter_list(s.get_rid())
			print("  Uniform count: ", ulist.size())
	quit()
