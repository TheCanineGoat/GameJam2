extends Node
class_name HealthComponent

# ================================================================
#  HEALTH COMPONENT
#  Node : Node  → child of any damageable entity
#
#  SCENE SETUP
#  ───────────
#  CharacterBody2D
#  ├── HurtBox   [hurtbox.gd]
#  └── HealthComponent  [health_component.gd]   ← this script
#
#  SIGNALS TO CONNECT
#  ───────────────────
#  health_changed(old, new, delta)  → drive the vignette
#  damage_rate_changed(rate)        → set vignette transition speed
#  died()                           → trigger death animation / freeze
#  respawned()                      → teleport back to spawn, re-enable control
# ================================================================

@export_group("❤️ Health")

## Maximum / starting health
@export var max_health       : float = 100.0

## How long (seconds) between death and respawn
@export_range(0.1, 5.0, 0.1)
var respawn_delay            : float = 1.2

## Reference to a Marker2D or Node2D that marks the spawn position.
## If left empty the component emits respawned() and your scene handles it.
@export var spawn_point      : Node2D = null


@export_group("📈 Damage Rate Tracking")

## Damage rate decays toward 0 at this speed (units per second)
## Higher = rate disappears faster after taking a hit
@export_range(1.0, 50.0, 0.5)
var rate_decay_speed         : float = 12.0

## Scales how much a single hit spike the damage rate
## (damage × multiplier → added to rate)
@export_range(0.01, 2.0, 0.01)
var rate_spike_multiplier    : float = 0.5


@export_group("💚 Regeneration")

## Enable or disable the regen system entirely
@export var regen_enabled        : bool  = true

## Seconds of no damage required before regen begins
@export_range(0.5, 10.0, 0.1)
var regen_delay                  : float = 3.0

## Health restored per second once regen is active
@export_range(1.0, 200.0, 1.0)
var regen_rate                   : float = 30.0

## Regen eases in over this many seconds so it doesn't kick in jarringly
## (0 = starts at full regen_rate immediately)
@export_range(0.0, 3.0, 0.1)
var regen_ease_in_duration       : float = 0.8


# ── Signals ──────────────────────────────────────────────────────
## Fires every time health changes.
## old_val, new_val = actual values  |  delta = amount changed (positive = damage)
signal health_changed(old_val : float, new_val : float, delta : float)

## Continuously updated rate of health loss (0 = no recent damage)
## Wire this to DamageVignette.on_damage_rate_changed()
signal damage_rate_changed(rate : float)

## Fired the frame health reaches 0
signal died()

## Fired after respawn_delay when health is restored and the entity is reset
signal respawned()

## Fired the moment regen kicks in (after regen_delay with no damage)
signal regen_started()

## Fired when regen is interrupted by damage, or completes to full health
signal regen_stopped()


# ── Read-only state (access from other scripts) ──────────────────
var current_health   : float = 0.0
var is_dead          : bool  = false

## Rolling damage rate (units/s feel, decays over time)
var damage_rate      : float = 0.0

# ── Regen internal state ─────────────────────────────────────────
## True while health is actively being restored
var is_regenerating  : bool  = false

var _regen_timer     : float = 0.0   # counts up since last damage hit
var _regen_ease_t    : float = 0.0   # 0→1 ease-in progress


# ================================================================
#  READY
# ================================================================

func _ready() -> void:
	current_health = max_health


# ================================================================
#  PROCESS — damage rate decay + regen tick
# ================================================================

func _process(delta : float) -> void:
	# ── Damage rate decay ───────────────────────────────────────
	if damage_rate > 0.0:
		damage_rate = maxf(damage_rate - rate_decay_speed * delta, 0.0)
		damage_rate_changed.emit(damage_rate)

	# ── Regen gate ──────────────────────────────────────────────
	if not regen_enabled or is_dead or current_health >= max_health:
		return

	# Count up the "no damage" window
	_regen_timer += delta

	if _regen_timer < regen_delay:
		# Still waiting — make sure we're not marked as regenerating
		if is_regenerating:
			is_regenerating = false
			_regen_ease_t   = 0.0
			regen_stopped.emit()
		return

	# ── Regen is active ─────────────────────────────────────────
	if not is_regenerating:
		is_regenerating = true
		_regen_ease_t   = 0.0
		regen_started.emit()

	# Ease in the regen rate so it ramps up smoothly
	if regen_ease_in_duration > 0.0:
		_regen_ease_t = minf(_regen_ease_t + delta / regen_ease_in_duration, 1.0)
	else:
		_regen_ease_t = 1.0

	var effective_rate := regen_rate * _regen_ease_t
	var old_val        := current_health
	current_health      = minf(current_health + effective_rate * delta, max_health)

	health_changed.emit(old_val, current_health, -(current_health - old_val))

	# Regen complete
	if current_health >= max_health:
		is_regenerating = false
		_regen_ease_t   = 0.0
		regen_stopped.emit()


# ================================================================
#  PUBLIC API
# ================================================================

## Deal damage to this entity.
func take_damage(amount : float) -> void:
	if is_dead or amount <= 0.0:
		return

	var old_val       := current_health
	current_health     = maxf(current_health - amount, 0.0)

	# Spike the damage rate — faster hits = higher sustained rate
	damage_rate       += amount * rate_spike_multiplier
	damage_rate_changed.emit(damage_rate)

	# Reset regen countdown — any hit resets the whole 3-second window
	_regen_timer   = 0.0
	_regen_ease_t  = 0.0
	if is_regenerating:
		is_regenerating = false
		regen_stopped.emit()

	health_changed.emit(old_val, current_health, amount)

	if current_health <= 0.0:
		_trigger_death()


## Restore health (clamped to max_health).
func heal(amount : float) -> void:
	if is_dead or amount <= 0.0:
		return

	var old_val    := current_health
	current_health  = minf(current_health + amount, max_health)
	health_changed.emit(old_val, current_health, -amount)


## Instantly kill this entity (bypasses damage checks).
func kill() -> void:
	if is_dead:
		return
	var old_val    := current_health
	current_health  = 0.0
	health_changed.emit(old_val, 0.0, old_val)
	_trigger_death()


## Returns health as a 0–1 normalised value.
func get_health_percent() -> float:
	return current_health / max_health


## Returns true while invincibility frames / death lockout are active.
func is_alive() -> bool:
	return not is_dead


# ================================================================
#  DEATH & RESPAWN
# ================================================================

func _trigger_death() -> void:
	is_dead         = true
	is_regenerating = false
	_regen_timer    = 0.0
	_regen_ease_t   = 0.0
	died.emit()

	# Disable physics on the parent while dead (prevents physics glitches)
	var parent := get_parent()
	if parent.has_method("set_physics_process"):
		parent.set_physics_process(false)
	if parent.has_method("set_process_input"):
		parent.set_process_input(false)

	await get_tree().create_timer(respawn_delay).timeout
	_do_respawn()


func _do_respawn() -> void:
	# Restore health and regen state
	current_health  = max_health
	is_dead         = false
	is_regenerating = false
	damage_rate     = 0.0
	_regen_timer    = 0.0
	_regen_ease_t   = 0.0

	damage_rate_changed.emit(0.0)
	health_changed.emit(0.0, max_health, -max_health)

	# Move parent to spawn point if one is assigned
	var parent := get_parent()
	if spawn_point and parent is Node2D:
		(parent as Node2D).global_position = spawn_point.global_position

	# Snap camera if it exposes the method
	var cam := parent.get_node_or_null("Camera2D")
	if cam and cam.has_method("snap_to_player"):
		cam.snap_to_player()

	# Re-enable physics
	if parent.has_method("set_physics_process"):
		parent.set_physics_process(true)
	if parent.has_method("set_process_input"):
		parent.set_process_input(true)

	respawned.emit()
