extends CharacterBody2D

# ================================================================
#  RAGE PLATFORMER — Player Controller
#  Engine  : Godot 4.5
#  Node    : CharacterBody2D
#  Inspired by Silksong / hollow-knight feel
# ================================================================
#
#  INPUT MAP  (Project → Project Settings → Input Map)
#  ─────────────────────────────────────────────────────
#  ui_left   → A / Arrow Left   (built-in)
#  ui_right  → D / Arrow Right  (built-in)
#  ui_accept → Space / Z        (built-in, used for Jump)
#  dash      → Left Shift / X   ← ADD THIS ACTION YOURSELF
#
# ================================================================

#Onready
@onready var  Run = $Icon
@onready var  Run2 =$AnimationPlayer
@onready var  Idle2 = $AnimationPlayer
@onready var  Idle1= $Icon
@onready var  Sprite = $Icon

# ────────────────────────────────────────────────────────────────
#  EXPORTED TUNING VARIABLES
# ────────────────────────────────────────────────────────────────

@export_group("🏃 Movement")
## Top horizontal speed (px/s)
@export var move_speed        : float = 220.0
## How fast we reach top speed on the ground
@export var ground_accel      : float = 1800.0
## Friction applied when no input on the ground
@export var ground_friction   : float = 1600.0
## Acceleration while airborne (less control in the air)
@export var air_accel         : float = 1000.0
## Friction applied while airborne with no input
@export var air_friction      : float = 500.0

@export_group("🦘 Jump")
## Upward impulse on a normal jump
@export var jump_strength       : float = 520.0
## Upward impulse on the second (air) jump
@export var double_jump_strength: float = 460.0
## Multiplier applied to upward velocity when jump is released early
## (0 = instant cut, 1 = no cut — rage games love ~0.35–0.5)
@export_range(0.0, 1.0, 0.01)
var jump_cut_multiplier         : float = 0.40

@export_group("🌍 Gravity")
## Base downward acceleration (px/s²)
@export var gravity_strength       : float = 2000.0
## Extra multiplier applied while falling (makes arcs feel snappier)
@export_range(1.0, 4.0, 0.05)
var fall_gravity_multiplier        : float = 1.70
## Hard cap on downward speed
@export var max_fall_speed         : float = 1000.0

@export_group("💨 Dash")
## Horizontal speed during the dash
@export var dash_speed     : float = 680.0
## How long the dash lasts (seconds)
@export var dash_duration  : float = 0.14
## Cooldown before the next dash is allowed (seconds)
@export var dash_cooldown  : float = 0.75

@export_group("🐱 Coyote & Jump Buffer")
## Seconds after walking off a ledge that a jump is still allowed
@export var coyote_time       : float = 0.12
## Seconds before landing that a jump input is remembered and executed
@export var jump_buffer_time  : float = 0.13


# ────────────────────────────────────────────────────────────────
#  INTERNAL STATE
# ────────────────────────────────────────────────────────────────

# Coyote jump
var _coyote_timer       : float = 0.0

# Jump-input buffer
var _jump_buffer_timer  : float = 0.0

# Whether the jump key is currently held (for jump-cut logic)
var _jump_held          : bool  = false

# Tracks if we were grounded last frame (to detect the moment of leaving)
var _was_on_floor       : bool  = false

# Double-jump availability
var _can_double_jump    : bool  = false

# Dash state
var _is_dashing         : bool  = false
var _dash_timer         : float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_dir           : float = 1.0   # +1 right, -1 left

# Store facing direction so dash fires the right way even from standstill
var _facing_dir         : float = 1.0


# ────────────────────────────────────────────────────────────────
#  PHYSICS PROCESS  (main loop)
# ────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()

	# ── 1. Tick all timers ──────────────────────────────────────
	_tick_timers(delta, on_floor)

	# ── 2. Dash takes over completely while active ───────────────
	if _is_dashing:
		_update_dash(delta)
		move_and_slide()
		_was_on_floor = on_floor
		return
	
	
	player_flip(_facing_dir)

	# ── 3. Gravity ───────────────────────────────────────────────
	_apply_gravity(delta, on_floor)

	# ── 4. Horizontal movement ───────────────────────────────────
	_apply_movement(delta, on_floor)

	# ── 5. Jump (including coyote + buffer) ──────────────────────
	_handle_jump(on_floor)

	# ── 6. Dash initiation ───────────────────────────────────────
	_handle_dash_input()

	# ── 7. Integrate ─────────────────────────────────────────────
	move_and_slide()

	_was_on_floor = on_floor


# ────────────────────────────────────────────────────────────────
#  TIMER MANAGEMENT
# ────────────────────────────────────────────────────────────────

func _tick_timers(delta: float, on_floor: bool) -> void:

	# Coyote timer — starts the frame we leave the floor without jumping
	if _was_on_floor and not on_floor and velocity.y >= 0.0:
		_coyote_timer = coyote_time
	elif on_floor:
		_coyote_timer = 0.0
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	# Jump buffer — remembers a jump press for a short window
	if Input.is_action_just_pressed("ui_accept"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	# Dash cooldown countdown
	_dash_cooldown_timer = maxf(_dash_cooldown_timer - delta, 0.0)

	# Land reset
	if on_floor:
		_can_double_jump = true
		# Only clear jump-held if we have landed properly
		if velocity.y >= 0.0:
			_jump_held = false


# ────────────────────────────────────────────────────────────────
#  GRAVITY
# ────────────────────────────────────────────────────────────────

func _apply_gravity(delta: float, on_floor: bool) -> void:
	if on_floor:
		# Snap velocity.y to 0 to avoid accumulation on slopes
		if velocity.y > 0.0:
			velocity.y = 0.0
		return

	var grav := gravity_strength

	if velocity.y > 0.0:
		# Falling — apply heavier gravity for that snappy rage-game arc
		grav *= fall_gravity_multiplier
	elif _jump_held and not Input.is_action_pressed("ui_accept") and velocity.y < 0.0:
		# Jump-cut: player released jump early → cut upward velocity sharply
		velocity.y *= jump_cut_multiplier
		_jump_held = false

	velocity.y = minf(velocity.y + grav * delta, max_fall_speed)


# ────────────────────────────────────────────────────────────────
#  HORIZONTAL MOVEMENT
# ────────────────────────────────────────────────────────────────

func _apply_movement(delta: float, on_floor: bool) -> void:
	var dir := Input.get_axis("ui_left", "ui_right")

	if dir != 0.0:
		_facing_dir = dir
		var accel := ground_accel if on_floor else air_accel
		velocity.x = move_toward(velocity.x, dir * move_speed, accel * delta)
		Run.play("Run")
		Run2.play("Run")
	else:
		var fric := ground_friction if on_floor else air_friction
		velocity.x = move_toward(velocity.x, 0.0, fric * delta)
		Idle1.play("idle")
		Idle2.play("Idle")


# ────────────────────────────────────────────────────────────────
#  JUMP
# ────────────────────────────────────────────────────────────────

func _handle_jump(on_floor: bool) -> void:
	if _jump_buffer_timer <= 0.0:
		return

	var can_coyote := _coyote_timer > 0.0 and not on_floor

	if on_floor or can_coyote:
		# ── Normal jump (or coyote jump) ───────────────────────
		_do_jump(jump_strength)
		_jump_buffer_timer = 0.0
		_coyote_timer      = 0.0

	elif _can_double_jump:
		# ── Double jump (air) ──────────────────────────────────
		_do_double_jump()
		_jump_buffer_timer = 0.0


func _do_jump(strength: float) -> void:
	velocity.y   = -strength
	_jump_held   = true


func _do_double_jump() -> void:
	velocity.y      = -double_jump_strength
	_can_double_jump = false
	_jump_held       = true


# ────────────────────────────────────────────────────────────────
#  DASH
# ────────────────────────────────────────────────────────────────

func _handle_dash_input() -> void:
	if not Input.is_action_just_pressed("dash"):
		return
	if _is_dashing or _dash_cooldown_timer > 0.0:
		return

	# Pick direction: prefer current movement input, fall back to facing
	var input_dir := Input.get_axis("ui_left", "ui_right")
	_dash_dir = input_dir if input_dir != 0.0 else _facing_dir

	_is_dashing         = true
	_dash_timer         = dash_duration
	_dash_cooldown_timer = dash_cooldown

	# Zero out vertical velocity so dash always travels horizontally
	velocity.y = 0.0
	velocity.x = _dash_dir * dash_speed


func _update_dash(delta: float) -> void:
	_dash_timer -= delta
	velocity.x   = _dash_dir * dash_speed
	velocity.y   = 0.0   # freeze vertical during dash

	if _dash_timer <= 0.0:
		_is_dashing = false
		# Preserve a sliver of momentum so the exit doesn't feel jarring
		velocity.x  = _dash_dir * move_speed


# ────────────────────────────────────────────────────────────────
#  UTILITY / PUBLIC HELPERS
# ────────────────────────────────────────────────────────────────

## Returns true while the dash is active (use for animation / VFX triggers)
func is_dashing() -> bool:
	return _is_dashing

## Returns true if the double jump is still available this airtime
func has_double_jump() -> bool:
	return _can_double_jump

## Returns the dash cooldown remaining (0 = ready)
func get_dash_cooldown_remaining() -> float:
	return _dash_cooldown_timer

## Returns the current facing direction (+1 right, -1 left)
func get_facing_dir() -> float:
	return _facing_dir

## Externally kill all movement (useful for death / respawn sequences)
func freeze_movement() -> void:
	velocity = Vector2.ZERO
	set_physics_process(false)

## Re-enable after freeze_movement()
func unfreeze_movement() -> void:
	set_physics_process(true)
func player_flip(delta: float)-> void:
	
	if delta ==1:
		Sprite.flip_h = false
	else:
		Sprite.flip_h = true
