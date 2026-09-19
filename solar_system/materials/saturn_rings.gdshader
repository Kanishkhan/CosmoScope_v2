// saturn_rings.gdshader
// Realistic translucent ring disc for Saturn (and Uranus with tilt).
// Correctly uses normalized radial distance from center computed from world position.

shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 ring_color_inner : source_color = vec4(0.85, 0.78, 0.62, 0.85);
uniform vec4 ring_color_outer : source_color = vec4(0.6, 0.55, 0.45, 0.4);
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);

// inner/outer fraction: inner skip zone as fraction of full radius
uniform float inner_radius_frac : hint_range(0.0, 1.0) = 0.35;
uniform float cassini_start : hint_range(0.0, 1.0) = 0.58;
uniform float cassini_end : hint_range(0.0, 1.0) = 0.62;

// Max radius of disc in world units — must match the PlaneMesh half-size
uniform float disc_half_size : hint_range(1.0, 100000.0) = 5000.0;

varying float v_radius_norm; // normalized 0..1 from centre to outer edge

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	// Compute normalized radial distance from disc centre (in local space)
	// VERTEX is in local space for a flat disc on Y=0 plane
	float dist = length(vec2(VERTEX.x, VERTEX.z));
	v_radius_norm = dist / disc_half_size;
}

void fragment() {
	float r = v_radius_norm;

	// Discard centre hole
	if (r < inner_radius_frac) discard;
	// Cassini Division
	if (r > cassini_start && r < cassini_end) discard;
	// Discard outer edge
	if (r > 1.0) discard;

	// Normalized position within ring
	float ring_t = (r - inner_radius_frac) / (1.0 - inner_radius_frac);
	ring_t = clamp(ring_t, 0.0, 1.0);

	// Density variation bands
	float density_var = 0.7 + 0.3 * sin(ring_t * 40.0 + hash(ring_t * 100.0) * 6.28);
	density_var *= 0.8 + 0.2 * sin(ring_t * 120.0);
	density_var *= 0.9 + 0.1 * sin(ring_t * 300.0);

	// Color gradient inner → outer
	vec4 col = mix(ring_color_inner, ring_color_outer, ring_t);
	col.a *= density_var;

	// Edge fade
	float edge_fade = 1.0 - smoothstep(0.92, 1.0, r);
	col.a *= edge_fade;

	// Sun scatter
	float sun_dot = dot(NORMAL, normalize(sun_direction));
	float scatter = clamp(0.4 + 0.6 * abs(sun_dot), 0.2, 1.0);
	col.rgb *= scatter;

	ALBEDO = col.rgb;
	ALPHA = clamp(col.a, 0.0, 1.0);
}
