extends Control

## Fast Travel confirmation dialog + warp cinematic overlay.
## Signals:
##   travel_confirmed(body) -- player pressed "Travel"
##   travel_cancelled       -- player pressed "Cancel"

signal travel_confirmed(body)
signal travel_cancelled

const StellarBody = preload("../solar_system/stellar_body.gd")

var _target_body  = null  # StellarBody

@onready var _label        : Label     = $Panel/VBox/Label
@onready var _confirm_btn  : Button    = $Panel/VBox/Buttons/ConfirmBtn
@onready var _cancel_btn   : Button    = $Panel/VBox/Buttons/CancelBtn
@onready var _warp_overlay : ColorRect = $WarpOverlay

# ── Warp VFX state ──────────────────────────────────────────────────────────
var _warp_active   := false
var _warp_progress := 0.0
const WARP_DURATION := 5.0   # seconds – must match solar_system.gd WARP_DURATION
const WARP_PEAK     := 0.15  # fraction at which we're at full brightness (stays bright most of journey)


func _ready() -> void:
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	hide()
	_warp_overlay.hide()
	# WarpLines is a child Control with a script; nothing extra needed here.


# ── Public API ───────────────────────────────────────────────────────────────

func show_for_body(body) -> void:
	_target_body = body
	_label.text  = "Fast travel to\n%s?" % body.name
	show()
	# Free mouse so the player can click buttons
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Focus so keyboard/gamepad can confirm without the mouse
	_confirm_btn.grab_focus()


## Called by SolarSystem when the warp coroutine actually starts.
func begin_warp_vfx() -> void:
	_warp_active   = true
	_warp_progress = 0.0
	_warp_overlay.show()
	_warp_overlay.modulate.a = 0.0


## Called by SolarSystem when the warp coroutine finishes.
func end_warp_vfx() -> void:
	_warp_active = false
	_warp_overlay.hide()
	_warp_overlay.modulate.a = 0.0
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ── Internal ─────────────────────────────────────────────────────────────────

func _on_confirm_pressed() -> void:
	hide()
	travel_confirmed.emit(_target_body)


func _on_cancel_pressed() -> void:
	hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	travel_cancelled.emit()


func _process(delta: float) -> void:
	if not _warp_active:
		return

	_warp_progress = minf(_warp_progress + delta / WARP_DURATION, 1.0)

	# Ease the alpha: ramp up fast, stay bright through journey, fade out at arrival
	var alpha : float
	if _warp_progress < WARP_PEAK:
		# Quick ramp-up at start
		alpha = _warp_progress / WARP_PEAK
	elif _warp_progress < 0.8:
		# Stay bright for most of the journey
		alpha = 1.0
	else:
		# Fade out as we arrive
		alpha = 1.0 - (_warp_progress - 0.8) / 0.2
	alpha = clampf(alpha, 0.0, 1.0)

	# Colour shifts white → cyan → deep blue as we travel
	var r := lerpf(1.0, 0.05, _warp_progress)
	var g := lerpf(1.0, 0.55, _warp_progress)
	var b := 1.0
	_warp_overlay.color   = Color(r, g, b, 1.0)
	_warp_overlay.modulate.a = alpha

	# Trigger redraw of the warp lines child
	var warp_lines := _warp_overlay.get_node_or_null("WarpLines")
	if warp_lines != null:
		warp_lines.set_meta("warp_progress", _warp_progress)
		warp_lines.queue_redraw()
	# NOTE: end_warp_vfx() is called exclusively by SolarSystem._finish_warp()
	# to avoid a race condition between the render-frame VFX timer and the
	# physics-frame warp movement completing at the same time.


# Keyboard / gamepad shortcuts so the dialog never depends on the mouse:
# Enter or gamepad A = Travel, Escape or gamepad B = Cancel.
func _input(event: InputEvent) -> void:
	if not visible or _warp_active:
		return
	var confirm := false
	var cancel := false
	if event is InputEventKey and event.pressed and not event.echo:
		confirm = event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER
		cancel = event.keycode == KEY_ESCAPE
	elif event is InputEventJoypadButton and event.pressed:
		confirm = event.button_index == JOY_BUTTON_A
		cancel = event.button_index == JOY_BUTTON_B
	if confirm:
		get_viewport().set_input_as_handled()
		_on_confirm_pressed()
	elif cancel:
		get_viewport().set_input_as_handled()
		_on_cancel_pressed()
