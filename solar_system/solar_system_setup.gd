# Scripts

const StellarBody = preload("./stellar_body.gd")
const Settings = preload("res://settings.gd")
const PlanetAtmosphere = preload("res://addons/zylann.atmosphere/planet_atmosphere.gd")

# Assets 

const VolumetricAtmosphereScene = preload("res://addons/zylann.atmosphere/planet_atmosphere.tscn")
const BigRock1Scene = preload("../props/big_rocks/big_rock1.tscn")
const Rock1Scene = preload("../props/rocks/rock1.tscn")
const GrassScene = preload("res://props/grass/grass.tscn")

const AtmosphereCloudsHighShader = preload(
	"res://addons/zylann.atmosphere/shaders/planet_atmosphere_v1_clouds_high.gdshader")
const AtmosphereCloudsShader = preload(
	"res://addons/zylann.atmosphere/shaders/planet_atmosphere_v1_clouds.gdshader")
const AtmosphereNoCloudsShader = preload(
	"res://addons/zylann.atmosphere/shaders/planet_atmosphere_v1_no_clouds.gdshader")
const AtmosphereScatteredCloudsHighShader = preload(
	"res://addons/zylann.atmosphere/shaders/planet_atmosphere_clouds_high.gdshader")
const AtmosphereScatteredCloudsShader = preload(
	"res://addons/zylann.atmosphere/shaders/planet_atmosphere_clouds.gdshader")
const AtmosphereScatteredNoCloudsShader = preload(
	"res://addons/zylann.atmosphere/shaders/planet_atmosphere_no_clouds.gdshader")

const CloudShapeTexture3D = preload("./atmosphere/noise_texture_3d.res")
const CloudCoverageTextureEarth = preload("./atmosphere/cloud_coverage_earth.tres")
const CloudCoverageTextureMars = preload("./atmosphere/cloud_coverage_mars.tres")
const CloudCoverageTextureGas = preload("./atmosphere/cloud_coverage_gas.tres")

const SunMaterial = preload("./materials/sun_yellow.tres")
const PlanetRockyMaterial = preload("./materials/planet_material_rocky.tres")
const PlanetGrassyMaterial = preload("./materials/planet_material_grassy.tres")
const WaterSeaMaterial = preload("./materials/water_sea_material.tres")
const RockMaterial = preload("res://props/rocks/rock_material.tres")

# Procedural planet body and ring shaders (no-placeholder visuals)
const PlanetSurfaceShader = preload("./materials/planet_surface.gdshader")
const SaturnRingsShader = preload("./materials/saturn_rings.gdshader")

const Pebble1Mesh = preload("res://props/pebbles/pebble1.obj")
const Rock1Mesh = preload("res://props/rocks/rock1.obj")
const BigRock1Mesh = preload("res://props/big_rocks/big_rock1.obj")

const BasePlanetVoxelGraph = preload("./voxel_graph_planet_v4.tres")

const EarthDaySound = preload("res://sounds/earth_surface_day.ogg")
const EarthNightSound = preload("res://sounds/earth_surface_night.ogg")
const WindSound = preload("res://sounds/wind.ogg")

const SAVE_FOLDER_PATH = "debug_data"

# Scale used when the large world setting is enabled
const LARGE_SCALE = 10.0

# Planet surface type constants (must match planet_surface.gdshader)
const SURFACE_ROCKY = 0
const SURFACE_EARTH = 1
const SURFACE_GAS_GIANT = 2
const SURFACE_ICE_GIANT = 3


static func create_solar_system_data(settings: Settings) -> Array[StellarBody]:
	var bodies: Array[StellarBody] = []
	
	var sun := StellarBody.new()
	sun.type = StellarBody.TYPE_SUN
	sun.radius = 1500.0
	sun.self_revolution_time = 60.0
	sun.orbit_revolution_time = 60.0
	sun.name = "Sun"
	bodies.append(sun)
	
	var planet := StellarBody.new()
	planet.name = "Mercury"
	planet.type = StellarBody.TYPE_ROCKY
	planet.radius = 900.0
	planet.parent_id = 0
	planet.distance_to_parent = 14400.0
	planet.self_revolution_time = 10.0 * 60.0
	planet.orbit_revolution_time = 50.0 * 60.0
	planet.atmosphere_mode = StellarBody.ATMOSPHERE_DISABLED
	planet.orbit_revolution_progress = -0.1
	planet.day_ambient_sound = WindSound
	bodies.append(planet)

	planet = StellarBody.new()
	planet.name = "Venus"
	planet.type = StellarBody.TYPE_ROCKY
	planet.radius = 1700.0
	planet.parent_id = 0
	planet.distance_to_parent = 19500.0
	planet.self_revolution_time = 20.0 * 60.0
	planet.orbit_revolution_time = 100.0 * 60.0
	planet.atmosphere_mode = StellarBody.ATMOSPHERE_MONOCHROME
	planet.atmosphere_color = Color(0.98, 0.90, 0.65)
	planet.orbit_revolution_progress = 0.35
	planet.day_ambient_sound = WindSound
	bodies.append(planet)

	planet = StellarBody.new()
	planet.name = "Earth"
	planet.type = StellarBody.TYPE_ROCKY
	planet.radius = 1800.0
	planet.parent_id = 0
	planet.distance_to_parent = 25600.0
	planet.self_revolution_time = 10.0 * 60.0
	planet.orbit_revolution_time = 150.0 * 60.0
	planet.atmosphere_mode = StellarBody.ATMOSPHERE_WITH_SCATTERING
#	planet.atmosphere_color = Color(0.3, 0.5, 1.0)
	planet.atmosphere_color = Color(0.75, 0.83, 1.0)
	planet.atmosphere_ambient_color = Color(0.02, 0.02, 0.1)
	planet.orbit_revolution_progress = 0.0
	planet.day_ambient_sound = EarthDaySound
	planet.night_ambient_sound = EarthNightSound
	planet.clouds_coverage_bias = 0.0
	planet.clouds_coverage_cubemap = CloudCoverageTextureEarth
	planet.sea = true
	var earth_id := bodies.size()
	bodies.append(planet)

	planet = StellarBody.new()
	planet.name = "Moon"
	planet.type = StellarBody.TYPE_ROCKY
	planet.radius = 600.0
	planet.parent_id = earth_id
	# The moon should not be too close, otherwise referential change
	# will overlap and physics will break. Every planet is a static body
	# and only the reference one is not moving, so it's a problem is the
	# moon is still moving while we reach it.
	planet.distance_to_parent = 7500.0
	planet.self_revolution_time = 10.0 * 60.0
	planet.orbit_revolution_time = 100.0 * 60.0
	planet.atmosphere_mode = StellarBody.ATMOSPHERE_DISABLED
#	planet.atmosphere_color = Color(0.2, 0.2, 0.2)
#	planet.atmosphere_color_for_scattering = Color(1.0, 1.0, 1.0)
	planet.orbit_revolution_progress = 0.25
	planet.day_ambient_sound = WindSound
	bodies.append(planet)

	planet = StellarBody.new()
	planet.name = "Mars"
	planet.type = StellarBody.TYPE_ROCKY
	planet.radius = 1280.0
	planet.parent_id = 0
	planet.distance_to_parent = 48000.0
	planet.self_revolution_time = 10.0 * 60.0
	planet.orbit_revolution_time = 100.0 * 60.0
	planet.atmosphere_mode = StellarBody.ATMOSPHERE_WITH_SCATTERING
#	planet.atmosphere_color = Color(1.2, 0.8, 0.5)
	planet.atmosphere_color = Color(1.0, 0.8, 0.5)
	planet.orbit_revolution_progress = 0.1
	planet.day_ambient_sound = WindSound
	planet.clouds_coverage_bias = -0.1
	planet.clouds_coverage_cubemap = CloudCoverageTextureMars
	bodies.append(planet)

	planet = StellarBody.new()
	planet.name = "Jupiter"
	planet.type = StellarBody.TYPE_GAS
	planet.radius = 3000.0
	planet.parent_id = 0
	planet.distance_to_parent = 70400.0
	planet.self_revolution_time = 8.0 * 60.0
	planet.orbit_revolution_time = 300.0 * 60.0
	planet.atmosphere_mode = StellarBody.ATMOSPHERE_WITH_SCATTERING
	planet.atmosphere_color = Color(0.95, 0.82, 0.65)
	planet.day_ambient_sound = WindSound
	planet.clouds_coverage_bias = 0.2
	planet.clouds_coverage_cubemap = CloudCoverageTextureGas
	bodies.append(planet)

	planet = StellarBody.new()
	planet.name = "Saturn"
	planet.type = StellarBody.TYPE_GAS
	planet.radius = 2700.0
	planet.parent_id = 0
	planet.distance_to_parent = 95000.0
	planet.self_revolution_time = 8.0 * 60.0
	planet.orbit_revolution_time = 400.0 * 60.0
	planet.atmosphere_mode = StellarBody.ATMOSPHERE_WITH_SCATTERING
	planet.atmosphere_color = Color(1.0, 0.9, 0.7)
	planet.orbit_revolution_progress = 0.6
	planet.day_ambient_sound = WindSound
	planet.clouds_coverage_bias = 0.2
	planet.clouds_coverage_cubemap = CloudCoverageTextureGas
	bodies.append(planet)

	planet = StellarBody.new()
	planet.name = "Uranus"
	planet.type = StellarBody.TYPE_GAS
	planet.radius = 2200.0
	planet.parent_id = 0
	planet.distance_to_parent = 118000.0
	planet.self_revolution_time = 9.0 * 60.0
	planet.orbit_revolution_time = 500.0 * 60.0
	planet.atmosphere_mode = StellarBody.ATMOSPHERE_WITH_SCATTERING
	planet.atmosphere_color = Color(0.6, 0.9, 1.0)
	planet.orbit_revolution_progress = 0.8
	planet.day_ambient_sound = WindSound
	planet.clouds_coverage_bias = 0.1
	planet.clouds_coverage_cubemap = CloudCoverageTextureGas
	bodies.append(planet)

	planet = StellarBody.new()
	planet.name = "Neptune"
	planet.type = StellarBody.TYPE_GAS
	planet.radius = 2100.0
	planet.parent_id = 0
	planet.distance_to_parent = 140000.0
	planet.self_revolution_time = 9.0 * 60.0
	planet.orbit_revolution_time = 600.0 * 60.0
	planet.atmosphere_mode = StellarBody.ATMOSPHERE_WITH_SCATTERING
	planet.atmosphere_color = Color(0.4, 0.55, 1.0)
	planet.orbit_revolution_progress = 0.95
	planet.day_ambient_sound = WindSound
	planet.clouds_coverage_bias = 0.1
	planet.clouds_coverage_cubemap = CloudCoverageTextureGas
	bodies.append(planet)
	
	var scale := 1.0
	if settings.world_scale_x10:
		scale = LARGE_SCALE

	for body in bodies:
		body.radius *= scale
		var speed := body.distance_to_parent * TAU / body.orbit_revolution_time
		body.distance_to_parent *= scale
		body.orbit_revolution_time = body.distance_to_parent * TAU / speed
	
	return bodies


# ─── Orbital LOD Planet Body ────────────────────────────────────────────────
# Creates a spherical visual body visible from space for any planet.
# For rocky planets this is supplementary to voxel terrain (fades on approach).
# For gas giants this IS the primary body.
static func _setup_planet_body(body: StellarBody, root: Node3D,
		surface_type: int, b_color: Color, s_color: Color, t_color: Color,
		ocean_color: Color = Color(0.1, 0.3, 0.7, 1.0),
		ocean_thresh: float = 0.0, night_intensity: float = 0.0,
		band_freq: float = 8.0, band_warp: float = 1.2,
		storm_x: float = 0.0, storm_y: float = 0.0, storm_r: float = 0.0,
		storm_color: Color = Color(0.85, 0.45, 0.3, 1.0)) -> MeshInstance3D:

	var mat := ShaderMaterial.new()
	mat.shader = PlanetSurfaceShader
	mat.set_shader_parameter(&"planet_type", surface_type)
	mat.set_shader_parameter(&"base_color", b_color)
	mat.set_shader_parameter(&"secondary_color", s_color)
	mat.set_shader_parameter(&"tertiary_color", t_color)
	mat.set_shader_parameter(&"ocean_color", ocean_color)
	mat.set_shader_parameter(&"ocean_threshold", ocean_thresh)
	mat.set_shader_parameter(&"night_light_intensity", night_intensity)
	mat.set_shader_parameter(&"band_frequency", band_freq)
	mat.set_shader_parameter(&"band_warp", band_warp)
	mat.set_shader_parameter(&"storm_x", storm_x)
	mat.set_shader_parameter(&"storm_y", storm_y)
	mat.set_shader_parameter(&"storm_radius", storm_r)
	mat.set_shader_parameter(&"storm_color", storm_color)
	# Sun direction updated at runtime by solar_system.gd
	mat.set_shader_parameter(&"sun_direction", Vector3(1, 0, 0))

	var sphere := SphereMesh.new()
	sphere.radius = body.radius
	sphere.height = body.radius * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24

	var mi := MeshInstance3D.new()
	mi.name = "PlanetBody"
	mi.mesh = sphere
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


# ─── Ring System ─────────────────────────────────────────────────────────────
static func _setup_rings(body: StellarBody, root: Node3D,
		inner_frac: float = 0.35, ring_color_inner: Color = Color(0.85, 0.78, 0.62, 0.85),
		ring_color_outer: Color = Color(0.6, 0.55, 0.45, 0.4),
		tilt_deg: float = 0.0) -> void:
	var ring_outer_radius := body.radius * 2.4

	var mat := ShaderMaterial.new()
	mat.shader = SaturnRingsShader
	mat.set_shader_parameter(&"ring_color_inner", ring_color_inner)
	mat.set_shader_parameter(&"ring_color_outer", ring_color_outer)
	mat.set_shader_parameter(&"inner_radius_frac", inner_frac)
	mat.set_shader_parameter(&"disc_half_size", ring_outer_radius)
	mat.set_shader_parameter(&"sun_direction", Vector3(1, 0, 0))

	# PlaneMesh creates a flat horizontal disc; subdivisions give the shader
	# smooth radial distance interpolation across the ring area
	var disc := PlaneMesh.new()
	disc.size = Vector2(ring_outer_radius * 2.0, ring_outer_radius * 2.0)
	disc.subdivide_width = 64
	disc.subdivide_depth = 64

	var mi := MeshInstance3D.new()
	mi.name = "Rings"
	mi.mesh = disc
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if tilt_deg != 0.0:
		mi.rotation_degrees.z = tilt_deg
	root.add_child(mi)


# ─── Gas Giant Setup ─────────────────────────────────────────────────────────
static func _setup_gas_giant(body: StellarBody, root: Node3D) -> void:
	match body.name:
		"Jupiter":
			_setup_planet_body(body, root, SURFACE_GAS_GIANT,
				Color(0.85, 0.58, 0.35),  # base: warm tan belts
				Color(0.42, 0.22, 0.12),  # secondary: dark brown-red belts
				Color(0.96, 0.90, 0.76),  # tertiary: cream zones
				Color(0.1, 0.3, 0.7, 1.0), 0.0, 0.0,
				12.0, 1.6,
				0.05, -0.22, 0.13,  # Great Red Spot position/size
				Color(0.92, 0.28, 0.15, 1.0))
		"Saturn":
			_setup_planet_body(body, root, SURFACE_GAS_GIANT,
				Color(0.94, 0.84, 0.60),  # pale butterscotch gold
				Color(0.72, 0.60, 0.40),  # golden brown bands
				Color(0.98, 0.95, 0.82),  # bright pale zones
				Color(0.1, 0.3, 0.7, 1.0), 0.0, 0.0,
				8.0, 0.9, 0.0, 0.0, 0.0)
			_setup_rings(body, root, 0.5,
				Color(0.95, 0.88, 0.70, 0.90),
				Color(0.65, 0.55, 0.42, 0.50),
				27.0)
		"Uranus":
			_setup_planet_body(body, root, SURFACE_ICE_GIANT,
				Color(0.35, 0.88, 0.92),  # distinctive cyan/aquamarine
				Color(0.20, 0.68, 0.78),
				Color(0.70, 0.95, 0.98),
				Color(0.1, 0.3, 0.7, 1.0), 0.0, 0.0,
				6.0, 0.5, 0.0, 0.0, 0.0)
			_setup_rings(body, root, 0.66,
				Color(0.65, 0.85, 0.95, 0.5),
				Color(0.40, 0.65, 0.75, 0.25),
				98.0)  # extreme axial tilt
		"Neptune":
			_setup_planet_body(body, root, SURFACE_ICE_GIANT,
				Color(0.08, 0.25, 0.95),  # vivid deep cobalt azure
				Color(0.04, 0.12, 0.60),  # deep ocean blue bands
				Color(0.70, 0.85, 1.0),   # bright white/cyan cirrus bands
				Color(0.1, 0.3, 0.7, 1.0), 0.0, 0.0,
				7.0, 0.7,
				-0.1, 0.1, 0.10,  # Great Dark Spot
				Color(0.02, 0.05, 0.30, 1.0))


# ─── Orbital Ring Lines ───────────────────────────────────────────────────────
# Draws a circular orbit path around the sun as a thin bright line mesh.
static func _setup_orbital_ring(distance: float, parent: Node3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.6, 0.75, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true

	var points := 256
	var arr := PackedVector3Array()
	arr.resize(points + 1)
	for i in range(points + 1):
		var angle := float(i) / float(points) * TAU
		arr[i] = Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in arr:
		im.surface_add_vertex(p)
	im.surface_end()

	var mi := MeshInstance3D.new()
	mi.name = "OrbitRing"
	mi.mesh = im
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _setup_sun(body: StellarBody, root: Node3D) -> DirectionalLight3D:

	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = body.radius
	mesh.height = 2.0 * mesh.radius
	mi.mesh = mesh
	mi.material_override = SunMaterial
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	
	var directional_light := DirectionalLight3D.new()
	directional_light.shadow_enabled = true
	# The environment in this game is a space background so it's very dark. Sky is actually a post
	# effect because you can fly out and it's a planet... And still you can also have shadows while
	# in your ship. We workaround this by making shadows not 100% opaque, and by adding a very
	# faint ambient light to the environment
	directional_light.shadow_opacity = 0.99
	directional_light.shadow_normal_bias = 0.2
	directional_light.directional_shadow_split_1 = 0.1
	directional_light.directional_shadow_split_2 = 0.2
	directional_light.directional_shadow_split_3 = 0.5
	directional_light.directional_shadow_blend_splits = true
	directional_light.directional_shadow_max_distance = 20000.0
	directional_light.name = "DirectionalLight"
	body.node.add_child(directional_light)
	
	return directional_light


static func update_atmosphere_settings(body: StellarBody, settings: Settings):
	var atmo: PlanetAtmosphere = body.atmosphere
	
	var has_clouds := (body.clouds_coverage_cubemap != null
		and settings.clouds_quality != Settings.CLOUDS_DISABLED)

	if has_clouds:
		if body.atmosphere_mode == StellarBody.ATMOSPHERE_WITH_SCATTERING:
			if settings.clouds_quality == Settings.CLOUDS_HIGH:
				atmo.custom_shader = AtmosphereScatteredCloudsHighShader
			else:
				atmo.custom_shader = AtmosphereScatteredCloudsShader
		else:
			if settings.clouds_quality == Settings.CLOUDS_HIGH:
				atmo.custom_shader = AtmosphereCloudsHighShader
			else:
				atmo.custom_shader = AtmosphereCloudsShader
	else:
		if body.atmosphere_mode == StellarBody.ATMOSPHERE_WITH_SCATTERING:
			atmo.custom_shader = AtmosphereScatteredNoCloudsShader
		else:
			atmo.custom_shader = AtmosphereNoCloudsShader
	
	#atmo.scale = Vector3(1, 1, 1) * (0.99 * body.radius)
	if settings.world_scale_x10:
		atmo.planet_radius = body.radius * 1.0
		atmo.atmosphere_height = 125.0 * LARGE_SCALE
	else:
		atmo.planet_radius = body.radius * 1.03
		atmo.atmosphere_height = 0.15 * body.radius

	var atmo_density := 0.001

	if body.atmosphere_mode == StellarBody.ATMOSPHERE_WITH_SCATTERING:
		# Scattered atmosphere settings
		atmo_density = 0.04 if settings.world_scale_x10 else 0.05
		atmo.set_shader_parameter(&"u_atmosphere_modulate", body.atmosphere_color)
		var sc_strength : float = 6.0
		if body.type == StellarBody.TYPE_GAS:
			sc_strength = 1.2
		elif settings.world_scale_x10:
			sc_strength = 1.0
		atmo.set_shader_parameter(&"u_scattering_strength", sc_strength)
		atmo.set_shader_parameter(&"u_atmosphere_ambient_color", body.atmosphere_ambient_color)
	else:
		if body.type == StellarBody.TYPE_GAS:
			if settings.world_scale_x10:
				# TODO Need to investigate this, atmosphere currently blows up HDR when large and dense
				atmo_density /= LARGE_SCALE
		# Settings for the fake color atmospheres
		atmo.set_shader_parameter(&"u_day_color0", body.atmosphere_color)
		atmo.set_shader_parameter(&"u_day_color1", body.atmosphere_color.lerp(Color(1, 1, 1), 0.5))
		atmo.set_shader_parameter(&"u_night_color0", body.atmosphere_color.darkened(0.8))
		atmo.set_shader_parameter(&"u_night_color1",
			body.atmosphere_color.darkened(0.8).lerp(Color(1, 1, 1), 0.0))

	atmo.set_shader_parameter(&"u_density", atmo_density)
#	atmo.set_shader_param("u_attenuation_distance", 50.0)

	if has_clouds:
		atmo.set_shader_parameter(&"u_cloud_density_scale",
			0.01 if settings.world_scale_x10 else 0.02)
		atmo.set_shader_parameter(&"u_cloud_shape_texture", CloudShapeTexture3D)
		atmo.set_shader_parameter(&"u_cloud_coverage_cubemap", body.clouds_coverage_cubemap)
		atmo.set_shader_parameter(&"u_cloud_shape_factor", 0.4)
		atmo.set_shader_parameter(&"u_cloud_shape_scale",
			0.001 if settings.world_scale_x10 else 0.005)
		atmo.set_shader_parameter(&"u_cloud_coverage_bias", body.clouds_coverage_bias)
		atmo.set_shader_parameter(&"u_cloud_shape_invert", 1.0)
		atmo.clouds_rotation_speed = 0.05 if settings.world_scale_x10 else 0.5


static func _setup_atmosphere(body: StellarBody, root: Node3D, settings: Settings):
	var atmo: PlanetAtmosphere = VolumetricAtmosphereScene.instantiate()
	body.atmosphere = atmo
	
	# TODO This is kinda bad to hardcode the path, need to find another robust way
	atmo.sun_path = "/root/Main/GameWorld/Sun/DirectionalLight"

	update_atmosphere_settings(body, settings)

	# This is clunky, can't save as .tres, FLAG_BUNDLE_RESOURCES doesn't save anything,
	# and Godot throws lots of errors when inspecting the resulting scene...	
#	var debug_packed_scene := PackedScene.new()
#	var pack_result := debug_packed_scene.pack(atmo)
#	print("Pack: ", pack_result)
#	var debug_packed_scene_fpath := str("debug_dump_atmosphere_", body.name, ".res")
#	var save_result := ResourceSaver.save(debug_packed_scene, 
#		debug_packed_scene_fpath)
#	print("Save ", debug_packed_scene_fpath, ": ", save_result)
	
	root.add_child(atmo)


static func _setup_sea(body: StellarBody, root: Node3D):
	var sea_mesh := SphereMesh.new()
	sea_mesh.radius = body.radius * 0.985
	sea_mesh.height = 2.0 * sea_mesh.radius
	var sea_mesh_instance := MeshInstance3D.new()
	sea_mesh_instance.mesh = sea_mesh
	sea_mesh_instance.material_override = WaterSeaMaterial
	root.add_child(sea_mesh_instance)


static func _setup_rocky_planet(body: StellarBody, root: Node3D, settings: Settings):
	var mat: ShaderMaterial
	# TODO Dont hardcode this
	if body.name == "Earth":
		mat = PlanetGrassyMaterial.duplicate()
	else:
		mat = PlanetRockyMaterial.duplicate()
	mat.set_shader_parameter(&"u_mountain_height", body.radius + 80.0)
	
	if body.name == "Mars":
		mat.set_shader_parameter(&"u_top_modulate", Color(1.0, 0.6, 0.3))
	
	var generator: VoxelGeneratorGraph = BasePlanetVoxelGraph.duplicate(true)
	var graph: VoxelGraphFunction = generator.get_main_function()
	var sphere_node_id := graph.find_node_by_name("sphere")
	
	if VoxelVersion.get_v() >= Vector3i(1, 4, 2):
		# TODO Could use a constant node now?
		graph.set_node_default_input(sphere_node_id, 3, body.radius)
	else:
		graph.set_node_param(sphere_node_id, 0, body.radius)

	var ravine_blend_noise_node_id := graph.find_node_by_name("ravine_blend_noise")
	var noise_param_id := 0
	var ravine_blend_noise = graph.get_node_param(ravine_blend_noise_node_id, noise_param_id)
	ravine_blend_noise.seed = body.name.hash()
	var cave_height_node_id := graph.find_node_by_name("cave_height_subtract")
	graph.set_node_default_input(cave_height_node_id, 1, body.radius - 100.0)
	var cave_noise_node_id := graph.find_node_by_name("cave_noise")
	var cave_noise = graph.get_node_param(cave_noise_node_id, noise_param_id)
	cave_noise.period = 900.0 / body.radius
	var ravine_depth_multiplier_node_id := graph.find_node_by_name("ravine_depth_multiplier")
	var ravine_depth: float = graph.get_node_default_input(ravine_depth_multiplier_node_id, 1)
	if settings.world_scale_x10:
		ravine_depth *= LARGE_SCALE
	graph.set_node_default_input(ravine_depth_multiplier_node_id, 1, ravine_depth)
	# var cave_height_multiplier_node_id = generator.find_node_by_name("cave_height_multiplier")
	# generator.set_node_default_input(cave_height_multiplier_node_id, 1, 0.015)
	generator.compile()

	generator.use_subdivision = true
	generator.subdivision_size = 8
	#generator.sdf_clip_threshold = 10.0
	generator.use_optimized_execution_map = true

	# ResourceSaver.save(generator, str("debug_data/generator_", body.name, ".tres"),
	# 			ResourceSaver.FLAG_BUNDLE_RESOURCES)

	#var sphere_normalmap = Image.new()
	#sphere_normalmap.create(512, 256, false, Image.FORMAT_RGB8)
	#generator.bake_sphere_normalmap(sphere_normalmap, body.radius * 0.95, 200.0 / body.radius)
	#sphere_normalmap.save_png(str("debug_data/test_sphere_normalmap_", body.name, ".png"))
	#var sphere_normalmap_tex = ImageTexture.create_from_image(sphere_normalmap)
	#mat.set_shader_parameter("u_global_normalmap", sphere_normalmap_tex)

	var extra_lods := 0
	if settings.world_scale_x10:
		var temp := int(LARGE_SCALE)
		while temp > 1:
			extra_lods += 1
			temp /= 2

	var pot := 1024
	while body.radius >= pot:
		pot *= 2

	var volume := VoxelLodTerrain.new()
	volume.lod_count = 7 + extra_lods
	volume.lod_distance = 60.0
	volume.collision_lod_count = 2
	volume.generator = generator
	var view_distance := 100000.0
	if settings.world_scale_x10:
		view_distance *= LARGE_SCALE
	volume.view_distance = view_distance
	volume.voxel_bounds = AABB(Vector3(-pot, -pot, -pot), Vector3(2 * pot, 2 * pot, 2 * pot))
	volume.lod_fade_duration = 0.3
	volume.threaded_update_enabled = true
	
	volume.normalmap_enabled = true
	volume.normalmap_tile_resolution_min = 4
	volume.normalmap_tile_resolution_max = 8
	volume.normalmap_begin_lod_index = 2
	volume.normalmap_max_deviation_degrees = 50
	volume.normalmap_octahedral_encoding_enabled = false
	volume.normalmap_use_gpu = true

	volume.material = mat
	# TODO Set before setting voxel bounds?
	volume.mesh_block_size = 32

	volume.mesher = VoxelMesherTransvoxel.new()
	#volume.mesher.mesh_optimization_enabled = true
	volume.mesher.mesh_optimization_error_threshold = 0.0025
	#volume.set_process_mode(VoxelLodTerrain.PROCESS_MODE_PHYSICS)
	body.volume = volume
	root.add_child(volume)

	_configure_instancing_for_planet(body, volume)


static func _configure_instancing_for_planet(body: StellarBody, volume: VoxelLodTerrain):
	for mesh in [Pebble1Mesh, Rock1Mesh, BigRock1Mesh]:
		mesh.surface_set_material(0, RockMaterial)

	var instancer := VoxelInstancer.new()
	instancer.set_up_mode(VoxelInstancer.UP_MODE_SPHERE)

	var library := VoxelInstanceLibrary.new()
	# Usually most of this is done in editor, but some features can only be setup by code atm.
	# Also if we want to procedurally-generate some of this, we may need code anyways.

	var instance_generator := VoxelInstanceGenerator.new()
	instance_generator.density = 0.15
	instance_generator.min_scale = 0.2
	instance_generator.max_scale = 0.4
	instance_generator.min_slope_degrees = 0
	instance_generator.max_slope_degrees = 40
	#instance_generator.set_layer_min_height(layer_index, body.radius * 0.95)
	instance_generator.random_vertical_flip = true
	instance_generator.vertical_alignment = 0.0
	instance_generator.emit_mode = VoxelInstanceGenerator.EMIT_FROM_FACES
	instance_generator.noise = FastNoiseLite.new()
	instance_generator.noise.frequency = 1.0 / 16.0
	instance_generator.noise.fractal_octaves = 2
	instance_generator.noise_on_scale = 1
	#instance_generator.noise.noise_type = FastNoiseLite.TYPE_PERLIN
	var item := VoxelInstanceLibraryMultiMeshItem.new()
	
	if body.name == "Earth":
		var grass_mesh: Node = GrassScene.instantiate()
		item.setup_from_template(grass_mesh)
		grass_mesh.free()

		#instance_generator.density = 0.32
		instance_generator.density = 2.0
		instance_generator.min_scale = 0.8
		instance_generator.max_scale = 1.6
		instance_generator.random_vertical_flip = false
		instance_generator.max_slope_degrees = 30

		item.name = "grass"
		
	else:
		item.set_mesh(Pebble1Mesh, 0)
		item.name = "pebbles"

	item.generator = instance_generator
	item.persistent = false
	item.lod_index = 0
	library.add_item(2, item)

	instance_generator = VoxelInstanceGenerator.new()
	instance_generator.density = 0.08
	instance_generator.min_scale = 0.5
	instance_generator.max_scale = 0.8
	instance_generator.min_slope_degrees = 0
	instance_generator.max_slope_degrees = 12
	instance_generator.vertical_alignment = 0.0
	item = VoxelInstanceLibraryMultiMeshItem.new()
	var rock1_template: Node = Rock1Scene.instantiate()
	item.setup_from_template(rock1_template)
	rock1_template.free()
	item.generator = instance_generator
	item.persistent = false
	item.lod_index = 2
	item.name = "rock"
	library.add_item(0, item)

	instance_generator = VoxelInstanceGenerator.new()
	instance_generator.density = 0.03
	instance_generator.min_scale = 0.6
	instance_generator.max_scale = 1.2
	instance_generator.min_slope_degrees = 0
	instance_generator.max_slope_degrees = 10
	instance_generator.vertical_alignment = 0.0
	item = VoxelInstanceLibraryMultiMeshItem.new()
	item.set_mesh(BigRock1Mesh, 0)
	item.generator = instance_generator
	item.persistent = false
	item.lod_index = 3
	item.name = "big_rock"
	library.add_item(1, item)

	instance_generator = VoxelInstanceGenerator.new()
	instance_generator.noise = FastNoiseLite.new()
	instance_generator.noise.frequency = 1.0 / 16.0
	instance_generator.noise.fractal_octaves = 2
	instance_generator.noise_on_scale = 1
	instance_generator.density = 0.06
	instance_generator.min_scale = 0.6
	instance_generator.max_scale = 3.0
	instance_generator.scale_distribution = VoxelInstanceGenerator.DISTRIBUTION_CUBIC
	instance_generator.min_slope_degrees = 140
	instance_generator.max_slope_degrees = 180
	instance_generator.vertical_alignment = 1.0
	instance_generator.offset_along_normal = -0.5
	item = VoxelInstanceLibraryMultiMeshItem.new()
	var cone := CylinderMesh.new()
	cone.radial_segments = 8
	cone.rings = 0
	cone.top_radius = 0.5
	cone.bottom_radius = 0.1
	cone.height = 2.5
	cone.material = RockMaterial
	item.set_mesh(cone, 0)
	item.generator = instance_generator
	item.persistent = false
	item.lod_index = 0
	item.name = "stalactite"
	library.add_item(3, item)

	instancer.library = library

	volume.add_child(instancer)
	body.instancer = instancer


static func setup_stellar_body(body: StellarBody, parent: Node,
	settings: Settings) -> DirectionalLight3D:
	var root := Node3D.new()
	root.name = body.name
	body.node = root
	parent.add_child(root)
	
	var sun_light: DirectionalLight3D = null

	if body.type == StellarBody.TYPE_SUN:
		sun_light = _setup_sun(body, root)
	
	elif body.type == StellarBody.TYPE_ROCKY:
		_setup_rocky_planet(body, root, settings)
		# Add an orbital LOD body sphere for long-range visibility (no placeholder — real material)
		# This ensures the planet is always visible as a proper 3D sphere from space
		var surface_type := SURFACE_ROCKY
		var b_col := Color(0.6, 0.55, 0.48)
		var s_col := Color(0.45, 0.40, 0.35)
		var t_col := Color(0.72, 0.68, 0.62)
		var ocean_col := Color(0.1, 0.3, 0.7, 1.0)
		var ocean_thresh := 0.0
		var night_int := 0.0
		match body.name:
			"Mercury":
				b_col = Color(0.55, 0.52, 0.48); s_col = Color(0.35, 0.33, 0.30)
				t_col = Color(0.70, 0.68, 0.65)
			"Venus":
				b_col = Color(0.92, 0.82, 0.52); s_col = Color(0.82, 0.68, 0.38)
				t_col = Color(1.0, 0.94, 0.72)
			"Earth":
				surface_type = SURFACE_EARTH
				b_col = Color(0.18, 0.58, 0.20); s_col = Color(0.48, 0.40, 0.26)
				t_col = Color(0.85, 0.82, 0.75)
				ocean_col = Color(0.04, 0.22, 0.75)
				ocean_thresh = 0.40; night_int = 0.75
			"Moon":
				b_col = Color(0.50, 0.50, 0.50); s_col = Color(0.32, 0.32, 0.32)
				t_col = Color(0.75, 0.75, 0.75)
			"Mars":
				b_col = Color(0.82, 0.36, 0.18); s_col = Color(0.45, 0.22, 0.14)
				t_col = Color(0.95, 0.95, 1.0)
		var lod_body := _setup_planet_body(body, root, surface_type,
			b_col, s_col, t_col, ocean_col, ocean_thresh, night_int)
		# The LOD body fades away when close so voxel terrain is the ground truth
		# We track it by name — solar_system.gd can toggle visibility by distance
		lod_body.set_meta("lod_orbital", true)

	if body.type == StellarBody.TYPE_GAS:
		_setup_gas_giant(body, root)
		_setup_solid_collider(body, body.radius)
	elif body.type == StellarBody.TYPE_ROCKY:
		_setup_solid_collider(body, get_solid_core_radius(body))

	if body.sea:
		_setup_sea(body, root)
	
	if body.atmosphere_mode != StellarBody.ATMOSPHERE_DISABLED:
		_setup_atmosphere(body, root, settings)
	
	return sun_light



# Solid sphere collider so a planet can never be entered. For gas planets it is the whole planet,
# for rocky ones it is an inner backstop under the voxel terrain (which streams in and can lag
# behind a fast ship). Only in the tree while the body is the reference frame (see SolarSystem).
static func _setup_solid_collider(body: StellarBody, core_radius: float):
	var shape := SphereShape3D.new()
	shape.radius = core_radius
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var sb := StaticBody3D.new()
	sb.name = "SolidCore"
	sb.add_child(cs)
	body.static_bodies.append(sb)


# Radius under which nothing may ever be. Rocky planets have terrain with caves and ravines below
# their nominal radius, so this stays well inside the surface.
static func get_solid_core_radius(body: StellarBody) -> float:
	if body.type == StellarBody.TYPE_ROCKY:
		return maxf(body.radius - 250.0, 0.5 * body.radius)
	return body.radius
