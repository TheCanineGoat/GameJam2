extends Area2D
class_name LevelTrigger

# ================================================================
#  LEVEL TRIGGER
#  Node : Area2D  → drop anywhere inside a level scene
#
#  SCENE SETUP
#  ───────────
#  Area2D  [level_trigger.gd]
#  └── CollisionShape2D  ← size and position this as the exit zone
#
#  Set collision layer = 0
#  Set collision mask  = player's layer  (e.g. 1)
# ================================================================


@export_group("🚪 Trigger Settings")
@export var target_level      : int   = -1
@export var single_use        : bool  = true
@export var zone_color        : Color = Color(0.2, 0.9, 0.4, 0.35)
@export var show_zone_in_game : bool  = true

@export_group("⏱️ Timing")
@export_range(0.0, 5.0, 0.05)
var trigger_delay : float = 0.0


# ── Signals ──────────────────────────────────────────────────────
signal player_entered()
signal transition_triggered(to_index : int)


# ── Internal ─────────────────────────────────────────────────────
var _used     : bool      = false
var _poly_vis : Polygon2D = null


# ================================================================
#  READY
# ================================================================

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if show_zone_in_game:
		_draw_zone_visual()


# ================================================================
#  BODY DETECTION
# ================================================================

func _on_body_entered(body : Node2D) -> void:
	if single_use and _used:
		return
	if not _is_player(body):
		return

	_used = true
	player_entered.emit()

	if trigger_delay > 0.0:
		await get_tree().create_timer(trigger_delay).timeout

	_fire_transition()


func _is_player(body : Node2D) -> bool:
	if body.is_in_group("player"):
		return true
	for child in body.get_children():
		if child is HealthComponent:
			return true
	return false


func _fire_transition() -> void:
	var lm : Node = get_node_or_null("/root/LevelManager")
	if lm == null:
		push_error("LevelTrigger: /root/LevelManager not found. " +
				   "Register level_manager.tscn as an Autoload named 'LevelManager'.")
		return

	var total   : int = (lm as Node).get("levels").size()
	var current : int = int((lm as Node).get("current_index"))

	var to_index : int
	if target_level < 0:
		to_index = (current + 1) % total
	else:
		to_index = clampi(target_level, 0, total - 1)

	transition_triggered.emit(to_index)
	lm.call("load_level", to_index)
	_used = false


# ================================================================
#  RESET
# ================================================================

func reset() -> void:
	_used = false


# ================================================================
#  VISUAL ZONE
# ================================================================

func _draw_zone_visual() -> void:
	for child in get_children():
		if not (child is CollisionShape2D):
			continue

		var col_shape : CollisionShape2D = child as CollisionShape2D
		var shape     : Shape2D          = col_shape.shape

		if shape == null:
			break

		if shape is RectangleShape2D:
			var rect_shape : RectangleShape2D = shape as RectangleShape2D
			var hw         : float            = rect_shape.size.x * 0.5
			var hh         : float            = rect_shape.size.y * 0.5
			_add_poly(PackedVector2Array([
				Vector2(-hw, -hh), Vector2(hw, -hh),
				Vector2(hw,   hh), Vector2(-hw, hh)
			]), col_shape.position)

		elif shape is CircleShape2D:
			var circ_shape : CircleShape2D   = shape as CircleShape2D
			var r          : float           = circ_shape.radius
			var pts        : PackedVector2Array = PackedVector2Array()
			for i in 32:
				var a : float = TAU * float(i) / 32.0
				pts.append(Vector2(cos(a), sin(a)) * r)
			_add_poly(pts, col_shape.position)

		break   # only mirror the first collision shape


func _add_poly(pts : PackedVector2Array, offset : Vector2) -> void:
	_poly_vis          = Polygon2D.new()
	_poly_vis.polygon  = pts
	_poly_vis.position = offset
	_poly_vis.color    = zone_color
	add_child(_poly_vis)

	var lbl : Label = Label.new()
	lbl.text         = "▶ NEXT LEVEL"
	lbl.position     = offset + Vector2(-48.0, -22.0)
	lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5, 0.9))
	lbl.add_theme_font_size_override("font_size", 13)
	add_child(lbl)
