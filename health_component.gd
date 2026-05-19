extends Node
class_name HealthComponent

# ================================================================
#  HEALTH COMPONENT
#  Node : Node  → child of any damageable entity
#
#  SCENE SETUP
#  ───────────
#  CharacterBody2D
#  ├── HurtBox          [hurtbox.gd]
#  └── HealthComponent  [health_component.gd]
#
#  spawn_point export is OPTIONAL.
#  If left empty the component automatically searches the scene
#  tree for a Marker2D / Node2D named "SpawnPoint".
# ================================================================


@export_group("❤️ Health")
@export var max_health    : float  = 100.0
@export_range(0.1, 5.0, 0.1)
var respawn_delay         : float  = 1.2
## Optional — leave null to auto-find a node named "SpawnPoint"
@export var spawn_point   : Node2D = null


@export_group("📈 Damage Rate Tracking")
@export_range(1.0, 50.0, 0.5)
var rate_decay_speed      : float = 12.0
@export_range(0.01, 2.0, 0.01)
var rate_spike_multiplier : float = 0.5


@export_group("💚 Regeneration")
@export var regen_enabled           : bool  = true
@export_range(0.5, 10.0, 0.1)
var regen_delay                     : float = 3.0
@export_range(1.0, 200.0, 1.0)
var regen_rate                      : float = 30.0
@export_range(0.0, 3.0, 0.1)
var regen_ease_in_duration          : float = 0.8


# ── Signals ──────────────────────────────────────────────────────
signal health_changed(old_val : float, new_val : float, delta : float)
signal damage_rate_changed(rate : float)
signal died()
signal respawned()
signal regen_started()
signal regen_stopped()


# ── State ─────────────────────────────────────────────────────────
var current_health  : float = 0.0
var is_dead         : bool  = false
var damage_rate     : float = 0.0
var is_regenerating : bool  = false

var _regen_timer    : float = 0.0
var _regen_ease_t   : float = 0.0
var _death_pending  : bool  = false   # prevents double-death calls


# ================================================================
#  READY
# ================================================================

func _ready() -> void:
	current_health = max_health


# ================================================================
#  PROCESS
# ================================================================

func _process(delta : float) -> void:
	if is_dead:
		return

	# ── Damage rate decay ───────────────────────────────────────
	if damage_rate > 0.0:
		damage_rate = maxf(damage_rate - rate_decay_speed * delta, 0.0)
		damage_rate_changed.emit(damage_rate)

	# ── Regen gate ──────────────────────────────────────────────
	if not regen_enabled or current_health >= max_health:
		return

	_regen_timer += delta

	if _regen_timer < regen_delay:
		if is_regenerating:
			is_regenerating = false
			_regen_ease_t   = 0.0
			regen_stopped.emit()
		return

	# ── Regen active ─────────────────────────────────────────────
	if not is_regenerating:
		is_regenerating = true
		_regen_ease_t   = 0.0
		regen_started.emit()

	_regen_ease_t = minf(
		_regen_ease_t + (delta / regen_ease_in_duration if regen_ease_in_duration > 0.0 else 1.0),
		1.0
	)

	var old_val        : float = current_health
	current_health              = minf(current_health + regen_rate * _regen_ease_t * delta, max_health)
	health_changed.emit(old_val, current_health, -(current_health - old_val))

	if current_health >= max_health:
		is_regenerating = false
		_regen_ease_t   = 0.0
		regen_stopped.emit()


# ================================================================
#  PUBLIC API
# ================================================================

func take_damage(amount : float) -> void:
	if is_dead or amount <= 0.0:
		return

	var old_val    : float = current_health
	current_health          = maxf(current_health - amount, 0.0)

	damage_rate    += amount * rate_spike_multiplier
	damage_rate_changed.emit(damage_rate)

	_regen_timer    = 0.0
	_regen_ease_t   = 0.0
	if is_regenerating:
		is_regenerating = false
		regen_stopped.emit()

	health_changed.emit(old_val, current_health, amount)

	if current_health <= 0.0:
		_trigger_death()


func heal(amount : float) -> void:
	if is_dead or amount <= 0.0:
		return
	var old_val    : float = current_health
	current_health          = minf(current_health + amount, max_health)
	health_changed.emit(old_val, current_health, -amount)


func kill() -> void:
	if is_dead:
		return
	var old_val    : float = current_health
	current_health          = 0.0
	health_changed.emit(old_val, 0.0, old_val)
	_trigger_death()


func get_health_percent() -> float:
	return current_health / max_health if max_health > 0.0 else 0.0


func is_alive() -> bool:
	return not is_dead


# ================================================================
#  DEATH & RESPAWN
# ================================================================

func _trigger_death() -> void:
	if _death_pending or is_dead:
		return                          # ← prevent double-trigger
	is_dead         = true
	_death_pending  = true
	is_regenerating = false
	_regen_timer    = 0.0
	_regen_ease_t   = 0.0
	died.emit()

	# Freeze the parent CharacterBody2D
	var parent : Node = get_parent()
	if is_instance_valid(parent):
		parent.set_physics_process(false)
		parent.set_process_input(false)

	await get_tree().create_timer(respawn_delay).timeout

	# Safety — node or scene may have been freed during the wait
	if not is_instance_valid(self):
		return

	_do_respawn()


func _do_respawn() -> void:
	# ── Reset state ───────────────────────────────────────────────
	current_health  = max_health
	is_dead         = false
	_death_pending  = false
	is_regenerating = false
	damage_rate     = 0.0
	_regen_timer    = 0.0
	_regen_ease_t   = 0.0

	damage_rate_changed.emit(0.0)
	health_changed.emit(0.0, max_health, -max_health)

	var parent : Node = get_parent()
	if not is_instance_valid(parent):
		respawned.emit()
		return

	# ── Find spawn position ───────────────────────────────────────
	# Priority 1: exported spawn_point
	# Priority 2: auto-search the scene tree for a node named "SpawnPoint"
	# Priority 3: stay in place (no movement)
	var sp : Node2D = spawn_point

	if sp == null:
		sp = _find_spawn_point()

	if sp != null and parent is Node2D:
		(parent as Node2D).global_position = sp.global_position
	elif sp == null:
		push_warning(
			"HealthComponent: No SpawnPoint found. " +
			"Add a Marker2D named 'SpawnPoint' to your level, or assign spawn_point in the Inspector."
		)

	# ── Snap camera ───────────────────────────────────────────────
	var cam : Node = parent.get_node_or_null("Camera2D")
	if cam != null and cam.has_method("snap_to_player"):
		cam.snap_to_player()

	# ── Re-enable physics ─────────────────────────────────────────
	parent.set_physics_process(true)
	parent.set_process_input(true)

	# Reset velocity so the player doesn't fly off
	if parent is CharacterBody2D:
		(parent as CharacterBody2D).velocity = Vector2.ZERO

	respawned.emit()


# ================================================================
#  SPAWN POINT SEARCH
# ================================================================

## Walks up the scene tree from the parent, then searches each
## ancestor's subtree for a node named "SpawnPoint".
func _find_spawn_point() -> Node2D:
	var parent : Node = get_parent()
	if not is_instance_valid(parent):
		return null

	# Search the parent's parent (the level scene root) first
	var level : Node = parent.get_parent()
	if level != null:
		var found : Node = _search_subtree(level, "SpawnPoint")
		if found != null and found is Node2D:
			return found as Node2D

	# Widen search to scene root as a fallback
	var root : Node = get_tree().current_scene
	if root != null:
		var found : Node = _search_subtree(root, "SpawnPoint")
		if found != null and found is Node2D:
			return found as Node2D

	return null


func _search_subtree(node : Node, target_name : String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var result : Node = _search_subtree(child, target_name)
		if result != null:
			return result
	return null
