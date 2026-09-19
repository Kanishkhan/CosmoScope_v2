// planet_surface.gdshader
// Procedural planet body shader — supports rocky and gas giant visual styles.
// Used to render a SphereMesh orbital-LOD body for each planet.

shader_type spatial;
render_mode depth_draw_opaque, cull_back, specular_schlick_ggx;

// -- Common parameters
uniform int planet_type : hint_range(0, 3) = 0;
// 0 = rocky/barren, 1 = lush/earth, 2 = gas_giant, 3 = ice_giant

uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);
uniform vec4 base_color : source_color = vec4(0.6, 0.5, 0.4, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.4, 0.3, 0.25, 1.0);
uniform vec4 tertiary_color : source_color = vec4(0.8, 0.7, 0.6, 1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.9;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.0;

// -- Gas/Ice giant band params
uniform float band_frequency : hint_range(1.0, 30.0) = 8.0;
uniform float band_warp : hint_range(0.0, 5.0) = 1.2;
uniform float storm_x : hint_range(-1.0, 1.0) = 0.1;
uniform float storm_y : hint_range(-1.0, 1.0) = -0.2;
uniform float storm_radius : hint_range(0.0, 0.5) = 0.12;
uniform vec4 storm_color : source_color = vec4(0.85, 0.45, 0.3, 1.0);

// -- Night lights (Earth)
uniform vec4 night_color : source_color = vec4(1.0, 0.9, 0.4, 1.0);
uniform float night_light_intensity : hint_range(0.0, 1.0) = 0.4;
// -- Ocean
uniform vec4 ocean_color : source_color = vec4(0.1, 0.3, 0.7, 1.0);
uniform float ocean_threshold : hint_range(-1.0, 1.0) = 0.0;

// Simple hash for procedural detail
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p, int octaves) {
	float v = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	for (int i = 0; i < octaves; i++) {
		v += amp * noise(p * freq);
		freq *= 2.0;
		amp *= 0.5;
	}
	return v;
}

varying vec3 v_local_pos;
varying vec3 v_world_normal;

void vertex() {
	v_local_pos = normalize(VERTEX);
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// UV from local spherical coordinates (fixed to planet surface)
	vec3 p = v_local_pos;
	float u = 0.5 + atan(p.z, p.x) / (2.0 * 3.14159265);
	float v = 0.5 - asin(clamp(p.y, -1.0, 1.0)) / 3.14159265;
	vec2 uv = vec2(u, v);

	vec4 color;
	float metal = metallic_val;
	float rough = roughness_val;

	if (planet_type == 2 || planet_type == 3) {
		// ── Gas / Ice Giant ─────────────────────────────────────────
		// Latitude banding with warp noise
		float lat = p.y;
		float warp = fbm(uv * vec2(4.0, 2.0), 3) * band_warp;
		float band = sin((lat + warp * 0.25) * band_frequency);
		float band_t = clamp(band * 0.5 + 0.5, 0.0, 1.0);

		// Secondary thin stripe oscillations
		float micro_band = sin(lat * band_frequency * 3.5 + warp);
		band_t = clamp(mix(band_t, micro_band * 0.5 + 0.5, 0.25), 0.0, 1.0);

		// Swirl detail noise
		float detail = fbm(uv * vec2(8.0, 4.0) + vec2(0.5, 0.0), 4) * 0.35;
		band_t = clamp(band_t + detail - 0.15, 0.0, 1.0);

		color = mix(base_color, secondary_color, band_t);
		color = mix(color, tertiary_color, fbm(uv * 14.0, 3) * 0.3);

		// Great Red Spot / Dark Spot
		if (storm_radius > 0.001) {
			vec3 storm_dir = normalize(vec3(cos(storm_x * 3.14159), storm_y, sin(storm_x * 3.14159)));
			float storm_dist = distance(p, storm_dir);
			float storm_t = 1.0 - smoothstep(storm_radius * 0.4, storm_radius, storm_dist);
			if (storm_t > 0.0) {
				// Internal swirl inside the spot
				float swirl = fbm(vec2(storm_dist * 20.0, uv.x * 10.0), 3);
				vec4 spot_col = mix(storm_color, storm_color * 1.25, swirl * 0.5);
				color = mix(color, spot_col, storm_t * 0.92);
			}
		}

		rough = 0.8;
		metal = 0.0;

	} else if (planet_type == 1) {
		// ── Earth-like (Vibrant Blue Marble) ─────────────────────────
		float continent = fbm(uv * 3.5, 6);
		float ocean_mask = smoothstep(ocean_threshold - 0.04, ocean_threshold + 0.04, continent);
		
		// Continents: rich vegetation, dry land, mountains
		float biome = fbm(uv * 7.0, 4);
		vec4 land_color = mix(secondary_color, base_color, biome);
		float mtn = fbm(uv * 15.0, 3);
		land_color = mix(land_color, tertiary_color, step(0.65, mtn) * 0.4);

		// Polar ice caps
		vec4 polar_color = vec4(0.95, 0.98, 1.0, 1.0);
		float polar = smoothstep(0.68, 0.82, abs(p.y));
		land_color = mix(land_color, polar_color, polar);

		// Ocean with shallow coastal shelf
		vec4 deep_ocean = ocean_color;
		vec4 shallow_ocean = mix(ocean_color, vec4(0.05, 0.55, 0.65, 1.0), 0.45);
		float coastal = smoothstep(ocean_threshold - 0.1, ocean_threshold, continent);
		vec4 sea_col = mix(deep_ocean, shallow_ocean, coastal);

		color = mix(sea_col, land_color, ocean_mask);
		if (abs(p.y) > 0.78) {
			color = mix(color, polar_color, smoothstep(0.78, 0.88, abs(p.y)));
		}

		// Swirling white clouds layer
		float cloud_val = fbm(uv * vec2(6.0, 3.0) + vec2(0.2, 0.1), 5);
		float cloud_mask = smoothstep(0.52, 0.72, cloud_val);
		color = mix(color, vec4(1.0, 1.0, 1.0, 1.0), cloud_mask * 0.75);

		rough = mix(0.05, 0.85, ocean_mask);
		metal = 0.0;

	} else {
		// ── Rocky / Barren (Mercury, Venus, Moon, Mars) ──────────────
		float detail = fbm(uv * 5.0, 5);
		float craters = noise(uv * 14.0);
		float crater_mask = step(0.82, craters);
		
		color = mix(base_color, secondary_color, detail);
		color = mix(color, tertiary_color, crater_mask * 0.5);

		// Polar ice for Mars if tertiary is white-ish
		if (tertiary_color.r > 0.8 && tertiary_color.g > 0.8 && tertiary_color.b > 0.8) {
			float polar = smoothstep(0.80, 0.92, abs(p.y));
			color = mix(color, tertiary_color, polar);
		}

		rough = 0.9;
		metal = 0.0;
	}

	// ── Lighting: Day / Night terminator in WORLD space ─────────────
	vec3 sun_dir_norm = normalize(sun_direction);
	float sun_dot = dot(v_world_normal, sun_dir_norm);
	// Smooth transition across terminator
	float day_factor = smoothstep(-0.15, 0.25, sun_dot);
	float night_factor = 1.0 - day_factor;

	// Ambient space starlight — keeps planet silhouette and colors visible
	// so it never collapses into a featureless black hole
	float ambient_light = 0.22;
	vec3 lit_color = mix(color.rgb * ambient_light, color.rgb, day_factor);

	// Atmospheric rim scattering glow on sunlit limb
	vec3 view_dir_world = normalize((INV_VIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz);
	float rim = 1.0 - clamp(dot(v_world_normal, -view_dir_world), 0.0, 1.0);
	rim = pow(rim, 3.0) * max(sun_dot, 0.0);
	lit_color += tertiary_color.rgb * rim * 0.35;

	// Night city lights for Earth
	if (planet_type == 1) {
		float continent = fbm(uv * 3.5, 6);
		float land_mask = smoothstep(ocean_threshold, ocean_threshold + 0.04, continent);
		float night_lights = fbm(uv * 12.0, 3) * night_light_intensity * land_mask;
		lit_color += night_color.rgb * night_lights * night_factor * 0.8;
	}

	ALBEDO = lit_color;
	METALLIC = metal;
	ROUGHNESS = rough;
	EMISSION = lit_color * 0.04;
}
