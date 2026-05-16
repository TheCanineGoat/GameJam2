extends Node2D

# ================================================================
#  TEST LEVEL — Auto-generated debug sandbox
#  Engine : Godot 4.5  |  Root node : Node2D
#
#  HOW TO USE
#  ──────────
#  1. Create a new scene, set root to Node2D
#  2. Attach this script to the root Node2D
#  3. In the Inspector, drag your Player .tscn into player_scene
#  4. Run the scene — everything is built at runtime
#
#  CONTROLS (in test scene)
#  ──────────────────────────
#  Arrow Keys / WASD  → Move
#  Space              → Jump / Double Jump
#  Shift              → Dash
#  Escape             → Respawn
#  F1                 → Toggle Debug HUD
# ================================================================

@export var player_scene : PackedScene  ## ← Drag your Player .tscn here


# ────────────────────────────────────────────────────────────────
#  PHYSICS REFERENCE  (tuned to player_controller.gd defaults)
#  jump_strength 520 / gravity 2000 → peak ~68px
#  double_jump   460               → +53px (total ~121px)
#  dash 680px/s × 0.14s            → ~95px
#  run speed 220px/s × ~0.46s air  → ~101px horizontal range
# ────────────────────────────────────────────────────────────────

const GROUND_Y    : float = 500.0     # Centre Y of the main floor
const TILE_H      : float = 32.0      # Platform thickness
const LEVEL_LEFT  : float = -200.0    # Left world boundary
const LEVEL_RIGHT : float = 8000.0    # Right world boundary

# ── Colour palette ───────────────────────────────────────────────
const C_GROUND    := Color("#2c3e50")  # Dark slate  — floor / walls
const C_MOVE      := Color("#27ae60")  # Green       — movement section
const C_COYOTE    := Color("#e67e22")  # Orange      — coyote jump
const C_DJUMP     := Color("#2980b9")  # Blue        — double jump
const C_DASH      := Color("#8e44ad")  # Purple      — dash
const C_RAGE      := Color("#c0392b")  # Red         — rage / combined
const C_SPAWN     := Color("#f39c12")  # Gold        — spawn pad
const C_KILL      := Color("#e74c3c")  # Red         — kill zone

# ── Internal state ───────────────────────────────────────────────
var _player         : CharacterBody2D = null
var _spawn_pos      : Vector2
var _debug_label    : RichTextLabel
var _hud_visible    : bool = true
var _world_labels   : Array[Dictionary] = []   # {pos, text, color, size}
var _death_count    : int = 0


# ================================================================
#  ENTRY
# ================================================================

func _ready() -> void:
	_build_level()
	_setup_kill_zone()
	_setup_ui()
	_spawn_player()


# ================================================================
#  MAIN LOOP
# ================================================================

func _process(_delta: float) -> void:
	_update_debug_hud()

	if Input.is_action_just_pressed("ui_cancel"):
		_respawn_player()

	if Input.is_action_just_pressed("ui_select"):   # F1 mapped to ui_select — or add "debug_toggle"
		_hud_visible = !_hud_visible
		if _debug_label:
			_debug_label.get_parent().visible = _hud_visible


func _draw() -> void:
	# World-space section labels painted directly into the scene
	var font := ThemeDB.fallback_font
	for entry in _world_labels:
		draw_string(
			font,
			entry["pos"],
			entry["text"],
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			entry["size"],
			entry["color"]
		)


# ================================================================
#  LEVEL BUILDER
# ================================================================

func _build_level() -> void:
	_build_spawn_section()
	_build_movement_section()
	_build_coyote_section()
	_build_double_jump_section()
	_build_dash_section()
	_build_rage_section()
	_build_world_bounds()
	queue_redraw()


# ── 0. SPAWN ─────────────────────────────────────────────────────
func _build_spawn_section() -> void:
	_spawn_pos = Vector2(0.0, GROUND_Y - TILE_H - 40)

	# Large golden spawn pad
	_make_platform(Vector2(0, GROUND_Y), Vector2(500, TILE_H), C_SPAWN)
	_add_label(Vector2(0, GROUND_Y - 48),  "▼  SPAWN", C_SPAWN, 18)
	_add_label(Vector2(0, GROUND_Y - 70),  "Esc = Respawn", Color.LIGHT_GRAY, 13)


# ── 1. BASIC MOVEMENT ────────────────────────────────────────────
func _build_movement_section() -> void:
	var ox := 400.0
	_make_platform(Vector2(ox + 600, GROUND_Y), Vector2(1200, TILE_H), C_MOVE)
	_add_label(Vector2(ox + 600, GROUND_Y - 50), "MOVEMENT TEST", C_MOVE, 20)
	_add_label(Vector2(ox + 600, GROUND_Y - 28), "Run, check acceleration & friction", Color.LIGHT_GRAY, 13)


# ── 2. COYOTE JUMP ───────────────────────────────────────────────
# Gaps ≈ 80px — reachable only if you jump slightly after leaving the edge
func _build_coyote_section() -> void:
	var ox := 1800.0

	_add_label(Vector2(ox + 450, GROUND_Y - 90),  "COYOTE JUMP", C_COYOTE, 22)
	_add_label(Vector2(ox + 450, GROUND_Y - 65),  "Walk off the edge — you can still jump!", Color.LIGHT_GRAY, 13)

	# Platform sequence with deliberate gaps (~85px each)
	_make_platform(Vector2(ox,        GROUND_Y), Vector2(250, TILE_H), C_COYOTE)
	_make_platform(Vector2(ox + 335,  GROUND_Y), Vector2(200, TILE_H), C_COYOTE)  # 85px gap
	_make_platform(Vector2(ox + 635,  GROUND_Y), Vector2(200, TILE_H), C_COYOTE)  # 85px gap
	_make_platform(Vector2(ox + 935,  GROUND_Y), Vector2(200, TILE_H), C_COYOTE)  # 85px gap
	_make_platform(Vector2(ox + 1235, GROUND_Y), Vector2(300, TILE_H), C_COYOTE)  # landing pad


# ── 3. DOUBLE JUMP ───────────────────────────────────────────────
# Staircase — each rise ≈ 75px (beyond single jump's ~68px peak)
func _build_double_jump_section() -> void:
	var ox := 3400.0

	_add_label(Vector2(ox + 500, GROUND_Y - 200), "DOUBLE JUMP", C_DJUMP, 22)
	_add_label(Vector2(ox + 500, GROUND_Y - 175), "Each platform is out of single-jump reach", Color.LIGHT_GRAY, 13)

	# Ascending staircase
	_make_platform(Vector2(ox,        GROUND_Y),        Vector2(220, TILE_H), C_DJUMP)
	_make_platform(Vector2(ox + 290,  GROUND_Y - 80),   Vector2(150, TILE_H), C_DJUMP)  # +80 → needs double jump
	_make_platform(Vector2(ox + 510,  GROUND_Y - 155),  Vector2(150, TILE_H), C_DJUMP)
	_make_platform(Vector2(ox + 730,  GROUND_Y - 80),   Vector2(150, TILE_H), C_DJUMP)  # descend
	_make_platform(Vector2(ox + 950,  GROUND_Y - 155),  Vector2(150, TILE_H), C_DJUMP)
	_make_platform(Vector2(ox + 1170, GROUND_Y),        Vector2(250, TILE_H), C_DJUMP)  # back down


# ── 4. DASH ──────────────────────────────────────────────────────
# Gaps ≈ 140px — too wide for a regular jump (range ~101px), need dash
func _build_dash_section() -> void:
	var ox := 5100.0

	_add_label(Vector2(ox + 500, GROUND_Y - 90), "DASH  [ Shift ]", C_DASH, 22)
	_add_label(Vector2(ox + 500, GROUND_Y - 65), "Gaps are too wide to jump — dash across", Color.LIGHT_GRAY, 13)

	# Gaps ≈ 140px (dash distance ≈ 95px but jump+dash clears it)
	_make_platform(Vector2(ox,        GROUND_Y), Vector2(220, TILE_H), C_DASH)
	_make_platform(Vector2(ox + 360,  GROUND_Y), Vector2(180, TILE_H), C_DASH)  # 140px gap
	_make_platform(Vector2(ox + 720,  GROUND_Y), Vector2(180, TILE_H), C_DASH)  # 140px gap
	_make_platform(Vector2(ox + 1100, GROUND_Y), Vector2(350, TILE_H), C_DASH)  # landing pad

	# Airborne dash puzzle — platform above, must dash mid-air
	_add_label(Vector2(ox + 1400, GROUND_Y - 160), "Air Dash ↑", C_DASH, 16)
	_make_platform(Vector2(ox + 1550, GROUND_Y),        Vector2(160, TILE_H), C_DASH)
	_make_platform(Vector2(ox + 1800, GROUND_Y - 100),  Vector2(160, TILE_H), C_DASH)  # gap + height
	_make_platform(Vector2(ox + 2080, GROUND_Y),        Vector2(250, TILE_H), C_DASH)


# ── 5. RAGE — Combined ───────────────────────────────────────────
# Tight precision: small platforms, mixed mechanics needed
func _build_rage_section() -> void:
	var ox := 7400.0

	_add_label(Vector2(ox + 350, GROUND_Y - 280), "RAGE SECTION", C_RAGE, 24)
	_add_label(Vector2(ox + 350, GROUND_Y - 252), "Dash  +  Double Jump  +  Precision", Color.LIGHT_GRAY, 13)

	_make_platform(Vector2(ox,        GROUND_Y),        Vector2(200, TILE_H), C_RAGE)
	_make_platform(Vector2(ox + 330,  GROUND_Y - 80),   Vector2(80,  TILE_H), C_RAGE)   # tiny ledge
	_make_platform(Vector2(ox + 520,  GROUND_Y - 155),  Vector2(80,  TILE_H), C_RAGE)   # tiny high
	_make_platform(Vector2(ox + 350,  GROUND_Y - 230),  Vector2(70,  TILE_H), C_RAGE)   # secret top
	_make_platform(Vector2(ox + 720,  GROUND_Y - 80),   Vector2(80,  TILE_H), C_RAGE)
	_make_platform(Vector2(ox + 500,  GROUND_Y - 310),  Vector2(60,  TILE_H), C_RAGE)   # highest point
	_make_platform(Vector2(ox + 950,  GROUND_Y),        Vector2(300, TILE_H), C_RAGE)   # finish


# ── WORLD BOUNDS (walls + ceiling) ───────────────────────────────
func _build_world_bounds() -> void:
	var h    := 1200.0
	var cy   := GROUND_Y - h * 0.5 + TILE_H * 0.5

	# Left wall
	_make_platform(Vector2(LEVEL_LEFT - TILE_H * 0.5, cy), Vector2(TILE_H, h), C_GROUND)
	# Right wall
	_make_platform(Vector2(LEVEL_RIGHT + TILE_H * 0.5, cy), Vector2(TILE_H, h), C_GROUND)
	# Ceiling
	_make_platform(Vector2((LEVEL_LEFT + LEVEL_RIGHT) * 0.5, GROUND_Y - h),
				   Vector2(LEVEL_RIGHT - LEVEL_LEFT + TILE_H * 2, TILE_H), C_GROUND)


# ================================================================
#  KILL ZONE  (anything below the floor)
# ================================================================

func _setup_kill_zone() -> void:
	var area  := Area2D.new()
	area.name  = "KillZone"
	add_child(area)

	var mid_x   := (LEVEL_LEFT + LEVEL_RIGHT) * 0.5
	var width   := LEVEL_RIGHT - LEVEL_LEFT + 800.0
	area.position = Vector2(mid_x, GROUND_Y + 250)

	var col   := CollisionShape2D.new()
	var rect  := RectangleShape2D.new()
	rect.size  = Vector2(width, 120)
	col.shape  = rect
	area.add_child(col)

	# Visual danger stripe
	var poly     := Polygon2D.new()
	var hw       := width * 0.5
	poly.polygon  = PackedVector2Array([
		Vector2(-hw, -60), Vector2(hw, -60),
		Vector2(hw,   60), Vector2(-hw, 60)
	])
	poly.color = Color(C_KILL, 0.28)
	area.add_child(poly)

	_add_label(Vector2(mid_x, GROUND_Y + 232), "☠  KILL ZONE", C_KILL, 15)
	area.body_entered.connect(_on_kill_zone_body_entered)


func _on_kill_zone_body_entered(body: Node2D) -> void:
	if body == _player:
		_death_count += 1
		get_tree().create_timer(0.12).timeout.connect(_respawn_player)


# ================================================================
#  PLAYER SPAWN / RESPAWN
# ================================================================

func _spawn_player() -> void:
	if player_scene == null:
		push_warning(
			"TestLevel: player_scene is not assigned!\n" +
			"Select the root Node2D → Inspector → player_scene → drag your Player.tscn"
		)
		return

	_player          = player_scene.instantiate() as CharacterBody2D
	_player.position = _spawn_pos
	add_child(_player)


func _respawn_player() -> void:
	if not is_instance_valid(_player):
		return
	_player.global_position = _spawn_pos
	_player.velocity        = Vector2.ZERO

	# Snap camera if the camera script exposes snap_to_player()
	var cam := _player.get_node_or_null("Camera2D")
	if cam and cam.has_method("snap_to_player"):
		cam.snap_to_player()


# ================================================================
#  DEBUG HUD
# ================================================================

func _setup_ui() -> void:
	var canvas    := CanvasLayer.new()
	canvas.layer   = 10
	add_child(canvas)

	# ── Panel ──────────────────────────────────────────────────
	var panel     := PanelContainer.new()
	panel.position = Vector2(12, 12)
	canvas.add_child(panel)

	_debug_label                       = RichTextLabel.new()
	_debug_label.bbcode_enabled        = true
	_debug_label.fit_content           = true
	_debug_label.custom_minimum_size   = Vector2(290, 0)
	panel.add_child(_debug_label)

	# ── Section colour legend ──────────────────────────────────
	var legend        := PanelContainer.new()
	legend.position    = Vector2(12, 0)
	legend.anchor_top  = 1.0
	legend.anchor_bottom = 1.0
	legend.offset_top  = -145
	legend.offset_bottom = -8
	canvas.add_child(legend)

	var vbox := VBoxContainer.new()
	legend.add_child(vbox)

	var legend_title := Label.new()
	legend_title.text = " SECTION LEGEND"
	legend_title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(legend_title)

	var entries := [
		["  ■ Green   — Movement test",      C_MOVE],
		["  ■ Orange  — Coyote jump",         C_COYOTE],
		["  ■ Blue    — Double jump",          C_DJUMP],
		["  ■ Purple  — Dash challenge",       C_DASH],
		["  ■ Red     — Rage / combined",      C_RAGE],
	]
	for e in entries:
		var lbl := Label.new()
		lbl.text = e[0]
		lbl.add_theme_color_override("font_color", e[1])
		vbox.add_child(lbl)

	# ── Controls bar ───────────────────────────────────────────
	var hint := Label.new()
	hint.text = "Move: ←→ / AD    Jump: Space    Dash: Shift    Respawn: Esc    Toggle HUD: F1"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.anchor_left   = 0.0
	hint.anchor_right  = 1.0
	hint.anchor_top    = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top    = -28
	hint.offset_bottom = -4
	hint.add_theme_color_override("font_color", Color.WHITE)
	canvas.add_child(hint)


func _update_debug_hud() -> void:
	if not _debug_label or not is_instance_valid(_player):
		return

	var vel      := _player.velocity
	var on_floor := _player.is_on_floor()

	# Pull from player public API (defined in player_controller.gd)
	var dashing   : bool  = _player.is_dashing()                if _player.has_method("is_dashing")                  else false
	var has_djump : bool  = _player.has_double_jump()            if _player.has_method("has_double_jump")             else false
	var dash_cd   : float = _player.get_dash_cooldown_remaining() if _player.has_method("get_dash_cooldown_remaining") else 0.0
	var facing    : float = _player.get_facing_dir()             if _player.has_method("get_facing_dir")              else 1.0

	var face_str   := "→  RIGHT" if facing > 0 else "←  LEFT"
	var floor_col  := "green"   if on_floor else "orange"
	var floor_str  := "ON FLOOR" if on_floor else "IN AIR  "
	var dash_str   : String
	if dashing:
		dash_str = "[color=violet]⚡ DASHING[/color]"
	elif dash_cd <= 0.0:
		dash_str = "[color=green]READY[/color]"
	else:
		dash_str = "[color=red]CD  %.2fs[/color]" % dash_cd
	var djump_str := "[color=cyan]✓ AVAILABLE[/color]" if has_djump else "[color=gray]✗ USED[/color]"

	_debug_label.text = (
		"[b]──── DEBUG HUD ────[/b]\n" +
		"[color=gray]Deaths :[/color]  [color=red]%d[/color]\n" % _death_count +
		"[color=gray]Pos    :[/color]  [color=yellow]%.0f , %.0f[/color]\n" % [_player.global_position.x, _player.global_position.y] +
		"[color=gray]Vel X  :[/color]  [color=yellow]%.1f px/s[/color]\n" % vel.x +
		"[color=gray]Vel Y  :[/color]  [color=yellow]%.1f px/s[/color]\n" % vel.y +
		"[color=gray]Speed  :[/color]  [color=yellow]%.1f px/s[/color]\n" % vel.length() +
		"[color=gray]Facing :[/color]  %s\n" % face_str +
		"[color=gray]Ground :[/color]  [color=%s]%s[/color]\n" % [floor_col, floor_str] +
		"[color=gray]Dash   :[/color]  %s\n" % dash_str +
		"[color=gray]AirJump:[/color]  %s\n" % djump_str
	)


# ================================================================
#  HELPERS
# ================================================================

## Build a static coloured platform centred at pos.
func _make_platform(pos: Vector2, size: Vector2, color: Color) -> StaticBody2D:
	var body    := StaticBody2D.new()
	body.position = pos
	add_child(body)

	# Collision
	var col   := CollisionShape2D.new()
	var rect  := RectangleShape2D.new()
	rect.size  = size
	col.shape  = rect
	body.add_child(col)

	var hw := size.x * 0.5
	var hh := size.y * 0.5

	# Fill
	var fill     := Polygon2D.new()
	fill.polygon  = PackedVector2Array([
		Vector2(-hw, -hh), Vector2(hw, -hh),
		Vector2(hw,   hh), Vector2(-hw, hh)
	])
	fill.color = color
	body.add_child(fill)

	# Top highlight stripe (helps read platform edges instantly)
	var stripe     := Polygon2D.new()
	stripe.polygon  = PackedVector2Array([
		Vector2(-hw, -hh),    Vector2(hw, -hh),
		Vector2(hw,  -hh + 5), Vector2(-hw, -hh + 5)
	])
	stripe.color = Color(color.lightened(0.45), 0.9)
	body.add_child(stripe)

	# Bottom shadow stripe
	var shadow     := Polygon2D.new()
	shadow.polygon  = PackedVector2Array([
		Vector2(-hw, hh - 4), Vector2(hw, hh - 4),
		Vector2(hw,  hh),     Vector2(-hw, hh)
	])
	shadow.color = Color(color.darkened(0.35), 0.9)
	body.add_child(shadow)

	return body


## Register a world-space label drawn in _draw().
func _add_label(pos: Vector2, text: String, color: Color, size: int = 16) -> void:
	_world_labels.append({ "pos": pos, "text": text, "color": color, "size": size })
