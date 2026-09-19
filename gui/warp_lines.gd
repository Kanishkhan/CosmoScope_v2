extends Control
## Draws an extremely cinematic hyperspeed warp effect during fast travel.
## Parent (FastTravelUI) sets meta "warp_progress" and calls queue_redraw().


func _draw() -> void:
	var progress : float = get_meta("warp_progress", 0.0)
	if progress <= 0.0:
		return

	var viewport_size := get_rect().size
	var center := viewport_size * 0.5
	var half_diag := center.length()

	var rng := RandomNumberGenerator.new()

	# ── Central radial glow ────────────────────────────────────────────────
	# Draws several concentric translucent circles that expand as progress peaks
	var glow_alpha := clampf(sin(progress * PI) * 0.55, 0.0, 0.55)
	var glow_r     := lerpf(half_diag * 0.05, half_diag * 0.45, progress)
	for ring in 4:
		var ra := glow_alpha * (1.0 - ring * 0.22)
		var rr := glow_r * (1.0 + ring * 0.35)
		draw_circle(center, rr, Color(0.3, 0.8, 1.0, ra * 0.5))

	# ── Warp streak layers ────────────────────────────────────────────────
	# Three layers for depth: white-core / cyan-mid / blue-outer
	var layers := [
		# [seed, count, inner_frac, outer_frac, max_len_frac, max_alpha, max_width, r, g, b]
		[11111, 60,  0.01, 0.12, 0.95, 0.95, 3.0, 1.0, 1.0, 1.0],   # white core
		[22222, 80,  0.05, 0.25, 0.85, 0.80, 2.0, 0.3, 0.85, 1.0],  # cyan mid
		[33333, 60,  0.12, 0.42, 0.70, 0.65, 1.2, 0.1, 0.45, 1.0],  # blue outer
	]

	for layer in layers:
		rng.seed = layer[0]
		var count       : int   = layer[1]
		var inner_frac  : float = layer[2]
		var outer_frac  : float = layer[3]
		var max_len_frac: float = layer[4]
		var max_alpha   : float = layer[5]
		var max_width   : float = layer[6]
		var lr          : float = layer[7]
		var lg          : float = layer[8]
		var lb          : float = layer[9]

		for i in count:
			var angle     := rng.randf() * TAU
			var inner_r   := rng.randf_range(half_diag * inner_frac, half_diag * outer_frac)
			# Lines grow from zero to full length as progress rises, then stay long
			var len_factor := clampf(progress * 2.2, 0.0, 1.0)
			var line_len  := lerpf(2.0, half_diag * max_len_frac * rng.randf_range(0.4, 1.0),
									len_factor)
			var alpha     := clampf(progress * 2.0, 0.0, max_alpha) * rng.randf_range(0.6, 1.0)
			var width     := lerpf(0.4, max_width, progress) * rng.randf_range(0.5, 1.0)

			var dir   := Vector2(cos(angle), sin(angle))
			var start := center + dir * inner_r
			var end_pt := center + dir * (inner_r + line_len)

			# Tail: fades from bright at start to transparent at end
			draw_line(start, end_pt, Color(lr, lg, lb, alpha), width)
			# Hot white core on the inner half
			if progress > 0.1:
				var core_end := center + dir * (inner_r + line_len * 0.25)
				draw_line(start, core_end, Color(1.0, 1.0, 1.0, alpha * 0.6), width * 0.5)

	# ── Background star flicker ───────────────────────────────────────────
	# Small dots scattered around, slightly transparent, adds depth
	rng.seed = 99999
	var star_alpha := clampf(progress * 1.5, 0.0, 0.35)
	for s in 55:
		var sx := rng.randf() * viewport_size.x
		var sy := rng.randf() * viewport_size.y
		var sr := rng.randf_range(0.8, 2.2)
		var sa := star_alpha * rng.randf_range(0.3, 1.0)
		draw_circle(Vector2(sx, sy), sr, Color(0.8, 0.95, 1.0, sa))
