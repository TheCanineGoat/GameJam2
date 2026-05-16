extends Area2D
class_name HitBox

# ================================================================
#  HITBOX — deals damage to any HurtBox it overlaps
#  Node : Area2D  → attach to enemies, projectiles, hazards
#
#  SCENE SETUP
#  ───────────
#  Area2D  [hitbox.gd]
#  └── CollisionShape2D   ← size this to the attack area
#
#  Set collision layer  to the ATTACKER's layer  (e.g. layer 2 = enemy)
#  Set collision mask   to the RECEIVER's layer  (e.g. layer 1 = player)
# ================================================================

@export_group("⚔️ Hit Settings")

## Toggle the entire hitbox on / off at runtime
@export var active : bool = true :
	set(v):
		active    = v
		monitoring = v          # Area2D monitoring mirrors active flag

## Damage dealt to the HurtBox on contact
@export var damage : float = 10.0

## Optional knockback applied to the receiver's velocity
## (X = horizontal push, Y = upward push)
@export var knockback_force : Vector2 = Vector2(200.0, -150.0)

## If true, only registers one hit per overlap entry (prevents spam per frame)
@export var single_hit_per_overlap : bool = true

## How long this hitbox is disabled after landing a hit (0 = no lockout)
@export var hit_lockout_duration : float = 0.0


# ── Internal ─────────────────────────────────────────────────────
var _locked_out    : bool = false
var _hit_bodies    : Array[Node] = []   # track current overlaps


# ================================================================
#  READY
# ================================================================

func _ready() -> void:
	monitoring  = active
	monitorable = false      # hitboxes don't need to be detected themselves

	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


# ================================================================
#  OVERLAP HANDLING
# ================================================================

func _on_area_entered(area: Area2D) -> void:
	if not active or _locked_out:
		return
	if not area is HurtBox:
		return
	if single_hit_per_overlap and area in _hit_bodies:
		return

	var hurtbox := area as HurtBox
	if not hurtbox.active:
		return

	# Pass damage + knockback to the hurtbox
	hurtbox.receive_hit(damage, knockback_force, self)

	if single_hit_per_overlap:
		_hit_bodies.append(area)

	if hit_lockout_duration > 0.0:
		_start_lockout()


func _on_area_exited(area: Area2D) -> void:
	_hit_bodies.erase(area)


# ================================================================
#  PUBLIC API
# ================================================================

## Enable or disable this hitbox (also exposed in the Inspector)
func set_active(value: bool) -> void:
	active = value          # triggers the setter above


## Temporarily disable after a hit (useful for melee swings)
func _start_lockout() -> void:
	_locked_out = true
	await get_tree().create_timer(hit_lockout_duration).timeout
	_locked_out = false
