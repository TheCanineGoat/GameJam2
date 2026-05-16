extends Area2D
class_name HurtBox

# ================================================================
#  HURTBOX — receives damage from HitBoxes, forwards to HealthComponent
#  Node : Area2D  → attach to the player or any damageable entity
#
#  SCENE SETUP
#  ───────────
#  CharacterBody2D
#  ├── HurtBox  [hurtbox.gd]          ← this script
#  │   └── CollisionShape2D
#  └── HealthComponent  [health_component.gd]
#
#  Set collision layer  to THIS entity's layer   (e.g. layer 1 = player)
#  Set collision mask   to 0 (HurtBox is passive — HitBox finds it)
# ================================================================

@export_group("🛡️ Hurt Settings")

## Toggle the entire hurtbox — set false during i-frames, cutscenes, etc.
@export var active : bool = true :
	set(v):
		active      = v
		monitorable = v     # mirrors whether we can be detected

## Seconds of invincibility granted after taking a hit
@export_range(0.0, 5.0, 0.05)
var invincibility_duration : float = 0.4

## Flash the sprite when invincible (expects a Sprite2D or AnimatedSprite2D sibling)
@export var flash_on_invincibility : bool = true

## Flash interval while invincible
@export_range(0.02, 0.3, 0.01)
var flash_interval : float = 0.08


# ── Signals ──────────────────────────────────────────────────────
signal hit_received(damage : float, knockback : Vector2, source : HitBox)
signal invincibility_started()
signal invincibility_ended()


# ── Internal ─────────────────────────────────────────────────────
var _invincible      : bool = false
var _health_comp     : HealthComponent = null
var _sprite          : Node2D = null     # Sprite2D or AnimatedSprite2D


# ================================================================
#  READY
# ================================================================

func _ready() -> void:
	monitorable = active
	monitoring  = false     # hurtboxes don't scan — hitboxes do the scanning

	# Auto-locate HealthComponent on the parent node
	_health_comp = _find_health_component()
	if not _health_comp:
		push_warning("HurtBox: No HealthComponent found on parent '%s'." % get_parent().name)

	# Auto-locate sprite for flashing
	if flash_on_invincibility:
		_sprite = _find_sprite()


# ================================================================
#  PUBLIC — called by HitBox
# ================================================================

func receive_hit(damage : float, knockback : Vector2, source : HitBox) -> void:
	if not active or _invincible:
		print("ouch I felt that")
		return

	# Apply knockback directly to parent if it is a CharacterBody2D
	var parent := get_parent()
	if parent is CharacterBody2D:
		parent.velocity += knockback

	# Forward damage to health component
	if _health_comp:
		_health_comp.take_damage(damage)

	hit_received.emit(damage, knockback, source)

	if invincibility_duration > 0.0:
		_run_invincibility_frames()


## Set active state from code (mirrors the exported setter)
func set_active(value : bool) -> void:
	active = value


## Manually grant invincibility for a given duration (e.g. dash i-frames)
func grant_invincibility(duration : float) -> void:
	if _invincible:
		return
	invincibility_duration = duration
	_run_invincibility_frames()


# ================================================================
#  INVINCIBILITY FRAMES
# ================================================================

func _run_invincibility_frames() -> void:
	_invincible = true
	invincibility_started.emit()

	if flash_on_invincibility and _sprite:
		_flash_sprite()

	await get_tree().create_timer(invincibility_duration).timeout

	_invincible = false
	invincibility_ended.emit()

	# Restore sprite visibility
	if flash_on_invincibility and _sprite:
		_sprite.modulate.a = 1.0


func _flash_sprite() -> void:
	var elapsed := 0.0
	while _invincible:
		if not is_instance_valid(_sprite):
			break
		_sprite.modulate.a = 0.25
		await get_tree().create_timer(flash_interval).timeout
		if not _invincible:
			break
		_sprite.modulate.a = 1.0
		await get_tree().create_timer(flash_interval).timeout
		elapsed += flash_interval * 2.0


# ================================================================
#  HELPERS
# ================================================================

func _find_health_component() -> HealthComponent:
	var parent := get_parent()
	for child in parent.get_children():
		if child is HealthComponent:
			return child
	return null


func _find_sprite() -> Node2D:
	var parent := get_parent()
	for child in parent.get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			return child
	return null
