extends Camera2D

# ================================================================
#  RAGE PLATFORMER — Camera Controller
#  Engine  : Godot 4.5
#  Node    : Camera2D  (drag into your Player node as a child)
#
#  HOW TO USE
#  ──────────
#  1. Add a Camera2D node as a child of your CharacterBody2D
#  2. Attach this script to that Camera2D
#  3. Done — it auto-detects its parent as the follow target
#
#  From anywhere in your project you can call:
#      %Camera.shake(strength, duration)   → screen shake
#      %Camera.zoom_to(value)              → smooth zoom transition
#      %Camera.set_follow_speed(x, y)      → runtime speed change
# ================================================================


# ────────────────────────────────────────────────────────────────
#  EXPORTED TUNING VARIABLES
# ────────────────────────────────────────────────────────────────

@export_group("📐 Follow Smoothing")
## Horizontal lerp speed — higher = snappier, lower = dreamier
@export_range(0.5, 30.0, 0.5) var follow_speed_x : float = 10.0
## Vertical lerp speed — keep slightly lower than X for a floaty feel
@export_range(0.5, 30.0, 0.5) var follow_speed_y  : float = 7.0
## Smoothing style — LERP feels organic, DAMP feels weighted/heavy
@export var smooth_mode : SmoothMode = SmoothMode.LERP

@export_group("🔭 Lookahead / Drag")
## How far (px) the camera peeks ahead in the movement direction
@export_range(0.0, 300.0, 5.0) var lookahead_distance : float = 90.0
## How fast the lookahead offset eases into place
@export_range(0.5, 20.0, 0.5) var lookahead_speed     : float = 4.5
## Speed threshold below which lookahead retracts (avoids jitter at rest)
@export var lookahead_threshold : float = 20.0
## Vertical lookahead scale relative to horizontal (0 = horizontal-only)
@export_range(0.0, 1.0, 0.05) var vertical_lookahead_scale : float = 0.4

@export_group("🔍 Zoom")
## Default zoom level (1.0 = native, 0.5 = zoomed out, 2.0 = zoomed in)
@export_range(0.1, 5.0, 0.05) var default_zoom   : float = 1.0
## How fast smooth zoom transitions complete
@export_range(0.5, 20.0, 0.5) var zoom_lerp_speed : float = 5.0

@export_group("📦 Bounds (optional)")
## Clamp the camera inside a rectangle (leave at 0 to disable)
@export var use_bounds   : bool = false
@export var bounds_rect  : Rect2 = Rect2(0, 0, 0, 0)

@export_group("💥 Screen Shake")
## How quickly shake decays per second (higher = snappier shake)
@export_range(1.0, 30.0, 0.5) var shake_decay : float = 8.0


# ────────────────────────────────────────────────────────────────
#  ENUMS
# ────────────────────────────────────────────────────────────────

enum SmoothMode {
	LERP,   ## Linear interpolation — constant rate, feels snappy
	DAMP    ## Exponential damping — eases at the end, feels weighted
}


# ────────────────────────────────────────────────────────────────
#  INTERNAL STATE
# ────────────────────────────────────────────────────────────────

var _player            : CharacterBody2D          # auto-detected parent
var _target_pos        : Vector2 = Vector2.ZERO   # where we want to be
var _lookahead_offset  : Vector2 = Vector2.ZERO   # current lookahead shift
var _target_zoom       : float   = 1.0            # goal zoom level

# Shake
var _shake_strength    : float   = 0.0
var _shake_duration    : float   = 0.0
var _shake_timer       : float   = 0.0

# Used for DAMP mode
var _cam_velocity      : Vector2 = Vector2.ZERO


# ────────────────────────────────────────────────────────────────
#  READY
# ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Detach from parent transform so we control position ourselves
	top_level = true

	# Grab the player (expected parent)
	if get_parent() is CharacterBody2D:
		_player = get_parent() as CharacterBody2D
	else:
		push_warning("Camera: parent is not a CharacterBody2D — follow disabled.")

	# Start at player position immediately (no lerp pop on scene start)
	if _player:
		global_position = _player.global_position

	# Apply initial zoom
	_target_zoom = default_zoom
	zoom         = Vector2.ONE * default_zoom

	# Disable Godot's built-in smoothing — we handle it ourselves
	position_smoothing_enabled = false
	drag_horizontal_enabled    = false
	drag_vertical_enabled      = false


# ────────────────────────────────────────────────────────────────
#  PHYSICS PROCESS  (runs in sync with player movement)
# ────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not _player:
		return

	# ── 1. Compute lookahead offset ─────────────────────────────
	_update_lookahead(delta)

	# ── 2. Build target camera position ─────────────────────────
	_target_pos = _player.global_position + _lookahead_offset

	# ── 3. Clamp to bounds if enabled ───────────────────────────
	if use_bounds and bounds_rect.size != Vector2.ZERO:
		_target_pos = _clamp_to_bounds(_target_pos)

	# ── 4. Move camera toward target ────────────────────────────
	_apply_follow(delta)

	# ── 5. Screen shake ─────────────────────────────────────────
	_apply_shake(delta)

	# ── 6. Smooth zoom ──────────────────────────────────────────
	zoom = zoom.lerp(Vector2.ONE * _target_zoom, zoom_lerp_speed * delta)


# ────────────────────────────────────────────────────────────────
#  LOOKAHEAD
# ────────────────────────────────────────────────────────────────

func _update_lookahead(delta: float) -> void:
	var vel := _player.velocity

	var target_offset := Vector2.ZERO

	# Horizontal lookahead — based on horizontal velocity direction
	if abs(vel.x) > lookahead_threshold:
		target_offset.x = sign(vel.x) * lookahead_distance

	# Vertical lookahead — only while falling (helps show what's below)
	if abs(vel.y) > lookahead_threshold:
		target_offset.y = sign(vel.y) * lookahead_distance * vertical_lookahead_scale

	# Ease the offset toward the target (so it trails smoothly)
	_lookahead_offset = _lookahead_offset.lerp(target_offset, lookahead_speed * delta)


# ────────────────────────────────────────────────────────────────
#  FOLLOW
# ────────────────────────────────────────────────────────────────

func _apply_follow(delta: float) -> void:
	match smooth_mode:

		SmoothMode.LERP:
			# Independent X / Y speeds → great for platformers
			global_position.x = lerp(global_position.x, _target_pos.x, follow_speed_x * delta)
			global_position.y = lerp(global_position.y, _target_pos.y, follow_speed_y * delta)

		SmoothMode.DAMP:
			# Critically-damped spring — overshoots a tiny bit then settles
			var avg_speed := (follow_speed_x + follow_speed_y) * 0.5
			global_position = _damp_spring(
				global_position,
				_target_pos,
				_cam_velocity,
				avg_speed,
				delta
			)


## Critically-damped spring (no oscillation, no overshoot, feels weighted)
func _damp_spring(current: Vector2, target: Vector2,
				  ref_vel: Vector2, speed: float, delta: float) -> Vector2:
	var omega    := 2.0 * speed
	var d        := target - current
	var friction := omega * delta
	var factor   := 1.0 / (1.0 + friction + 0.48 * friction * friction
						   + 0.235 * friction * friction * friction)
	_cam_velocity = (_cam_velocity + omega * d) * factor
	return current + (_cam_velocity + omega * d) * delta * factor


# ────────────────────────────────────────────────────────────────
#  BOUNDS CLAMP
# ────────────────────────────────────────────────────────────────

func _clamp_to_bounds(pos: Vector2) -> Vector2:
	# Account for viewport half-size at current zoom so edges stay visible
	var half := get_viewport_rect().size / (2.0 * zoom)
	var min_x := bounds_rect.position.x + half.x
	var max_x := bounds_rect.end.x       - half.x
	var min_y := bounds_rect.position.y  + half.y
	var max_y := bounds_rect.end.y       - half.y
	return Vector2(clampf(pos.x, min_x, max_x), clampf(pos.y, min_y, max_y))


# ────────────────────────────────────────────────────────────────
#  SCREEN SHAKE
# ────────────────────────────────────────────────────────────────

func _apply_shake(delta: float) -> void:
	if _shake_timer > 0.0:
		_shake_timer     = maxf(_shake_timer - delta, 0.0)
		# Decay strength over the duration
		var t            := _shake_timer / _shake_duration if _shake_duration > 0.0 else 0.0
		var strength     := _shake_strength * t
		offset           = Vector2(
			randf_range(-strength, strength),
			randf_range(-strength, strength)
		)
	else:
		offset = offset.lerp(Vector2.ZERO, shake_decay * delta)


# ────────────────────────────────────────────────────────────────
#  PUBLIC API
# ────────────────────────────────────────────────────────────────

## Trigger a screen shake.
## strength → max pixel displacement (try 8–25 for hits, 30–60 for death)
## duration → seconds the shake lasts
func shake(strength: float, duration: float) -> void:
	_shake_strength = strength
	_shake_duration = duration
	_shake_timer    = duration


## Smoothly transition to a new zoom level.
## value → 1.0 = native | 0.5 = zoomed out | 2.0 = zoomed in
func zoom_to(value: float) -> void:
	_target_zoom = value


## Reset zoom back to the exported default_zoom value.
func zoom_reset() -> void:
	_target_zoom = default_zoom


## Override follow speeds at runtime (e.g. slow-mo section).
func set_follow_speed(x: float, y: float) -> void:
	follow_speed_x = x
	follow_speed_y = y


## Instantly snap the camera to the player — use on respawn to avoid
## a long lerp crawl back from the death position.
func snap_to_player() -> void:
	if _player:
		global_position  = _player.global_position
		_lookahead_offset = Vector2.ZERO
		_cam_velocity     = Vector2.ZERO
