extends Node

# ================================================================
#  LEVEL MANAGER  —  Autoload Singleton
#  ================================================================
#
#  SETUP (one-time, ~2 minutes)
#  ────────────────────────────
#  1. Create a new scene → root node = Node → save as level_manager.tscn
#  2. Attach this script to that root node
#  3. In the Inspector, fill in:
#       • levels[]       → drag each level .tscn in order
#       • player_scene   → drag your Player.tscn
#       • level_names[]  → optional display names (e.g. "World 1-1")
#  4. Project → Project Settings → Autoload
#       → Add level_manager.tscn   →  Name it  LevelManager
#  5. Done. Call LevelManager.next_level() from anywhere.
#
#  ADDING A NEW LEVEL
#  ──────────────────
#  • Create a new scene, design it however you like
#  • Add a Marker2D named "SpawnPoint" where the player should appear
#  • Add a LevelTrigger (level_trigger.gd) where the level ends
#  • Drag the new .tscn into LevelManager.levels[] in the Inspector
#  • Order in the array = play order
#
#  DEBUG CONTROLS  (only active when debug_mode = true)
#  ──────────────────────────────────────────────────────
#  F2          → previous level
#  F3          → next level
#  1 – 9       → jump straight to that level slot
#  ` (backtick)→ toggle the debug level-select panel
# ================================================================


@export_group("📦 Level Registry")
@export var levels        : Array[PackedScene] = []
@export var level_names   : Array[String]      = []
@export var player_scene  : PackedScene        = null

@export_group("🎬 Transition")
@export_range(0.05, 2.0, 0.05)
var transition_duration   : float = 0.35
@export var transition_color : Color = Color(0.0, 0.0, 0.0, 1.0)

@export_group("🚀 Start")
@export var start_level    : int   = 0
@export var persist_player : bool  = false

@export_group("🐛 Debug")
@export var debug_mode     : bool  = true


# ── Signals ──────────────────────────────────────────────────────
signal level_loaded(index : int)
signal level_changed(from_index : int, to_index : int)


# ── Internal state ────────────────────────────────────────────────
var current_index   : int  = -1
var _transitioning  : bool = false
var _level_root     : Node
var _player         : Node
var _overlay_canvas : CanvasLayer
var _overlay        : ColorRect
var _debug_canvas   : CanvasLayer
var _debug_panel    : PanelContainer
var _debug_visible  : bool = false
var _level_buttons  : Array[Button] = []
var _status_label   : Label
var _corner_label   : Label


# ================================================================
#  READY
# ================================================================

func _ready() -> void:
	_build_level_container()
	_build_transition_overlay()
	if debug_mode:
		_build_debug_panel()
	call_deferred("_load_start_level")


func _load_start_level() -> void:
	load_level(start_level)


# ================================================================
#  INPUT  (debug shortcuts)
# ================================================================

func _unhandled_input(event : InputEvent) -> void:
	if not debug_mode or _transitioning:
		return

	# Cast once — if not a key event, bail immediately
	var key_event : InputEventKey = event as InputEventKey
	if key_event == null:
		return
	if not key_event.pressed or key_event.echo:
		return

	var kc : int = int(key_event.keycode)

	if kc == int(KEY_F2):
		prev_level()
	elif kc == int(KEY_F3):
		next_level()
	elif kc == int(KEY_QUOTELEFT):
		_toggle_debug_panel()
	elif kc >= int(KEY_1) and kc <= int(KEY_9):
		var idx : int = kc - int(KEY_1)   # KEY_1 → 0,  KEY_2 → 1 …
		if idx < levels.size():
			load_level(idx)


# ================================================================
#  PUBLIC API
# ================================================================

func load_level(index : int) -> void:
	if _transitioning:
		return
	if levels.is_empty():
		push_error("LevelManager: levels[] array is empty. Add scenes in the Inspector.")
		return
	index = clampi(index, 0, levels.size() - 1)
	_run_transition(index)


func next_level() -> void:
	load_level((current_index + 1) % levels.size())


func prev_level() -> void:
	load_level((current_index - 1 + levels.size()) % levels.size())


func get_level_name(index : int) -> String:
	if index < level_names.size() and not level_names[index].is_empty():
		return level_names[index]
	return "Level %d" % (index + 1)


func get_player() -> Node:
	return _player


func get_current_level() -> Node:
	if _level_root.get_child_count() > 0:
		return _level_root.get_child(0)
	return null


# ================================================================
#  TRANSITION FLOW
# ================================================================

func _run_transition(to_index : int) -> void:
	_transitioning = true
	level_changed.emit(current_index, to_index)
	_update_debug_highlight(to_index)

	await _fade(_overlay, 0.0, 1.0, transition_duration)

	_unload_current_level()
	current_index = to_index
	_load_level_instance(to_index)

	await get_tree().process_frame

	await _fade(_overlay, 1.0, 0.0, transition_duration)

	_transitioning = false
	level_loaded.emit(current_index)
	_refresh_debug_status()


func _unload_current_level() -> void:
	if persist_player and is_instance_valid(_player):
		if _player.get_parent() != self:
			_player.reparent(self)
	for child in _level_root.get_children():
		child.queue_free()


func _load_level_instance(index : int) -> void:
	var scene    : PackedScene = levels[index]
	var instance : Node        = scene.instantiate()
	_level_root.add_child(instance)

	var spawn_pt : Node = _find_spawn_point(instance)

	if persist_player and is_instance_valid(_player):
		_player.reparent(instance)
		if spawn_pt and _player is Node2D:
			(_player as Node2D).global_position = (spawn_pt as Node2D).global_position
		var cam : Node = _player.get_node_or_null("Camera2D")
		if cam and cam.has_method("snap_to_player"):
			cam.snap_to_player()
	else:
		if player_scene:
			_player = player_scene.instantiate()
			instance.add_child(_player)
			if spawn_pt and _player is Node2D:
				(_player as Node2D).global_position = (spawn_pt as Node2D).global_position
		else:
			push_warning("LevelManager: player_scene is not set.")

	if is_instance_valid(_player):
		var hc : Node = _player.get_node_or_null("HealthComponent")
		if hc and hc.has_signal("respawned"):
			if not hc.respawned.is_connected(_on_player_respawned):
				hc.respawned.connect(_on_player_respawned)


func _find_spawn_point(level_instance : Node) -> Node:
	return _recursive_find(level_instance, "SpawnPoint")


func _recursive_find(node : Node, target_name : String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var result : Node = _recursive_find(child, target_name)
		if result:
			return result
	return null


func _on_player_respawned() -> void:
	if not is_instance_valid(_player):
		return
	var cam : Node = _player.get_node_or_null("Camera2D")
	if cam and cam.has_method("snap_to_player"):
		cam.snap_to_player()


# ================================================================
#  FADE HELPER
# ================================================================

func _fade(target : CanvasItem, from_alpha : float,
		   to_alpha : float, duration : float) -> void:
	var tween : Tween = create_tween()
	target.modulate.a = from_alpha
	tween.tween_property(target, "modulate:a", to_alpha, duration) \
		 .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


# ================================================================
#  SCENE CONSTRUCTION
# ================================================================

func _build_level_container() -> void:
	_level_root      = Node.new()
	_level_root.name = "LevelContainer"
	add_child(_level_root)


func _build_transition_overlay() -> void:
	_overlay_canvas        = CanvasLayer.new()
	_overlay_canvas.layer  = 128
	add_child(_overlay_canvas)

	_overlay               = ColorRect.new()
	_overlay.color         = transition_color
	_overlay.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.modulate.a    = 0.0
	_overlay_canvas.add_child(_overlay)


# ================================================================
#  DEBUG PANEL
# ================================================================

func _build_debug_panel() -> void:
	_debug_canvas       = CanvasLayer.new()
	_debug_canvas.layer = 100
	add_child(_debug_canvas)

	_debug_panel          = PanelContainer.new()
	_debug_panel.visible  = false
	_debug_panel.position = Vector2(12.0, 12.0)
	_debug_canvas.add_child(_debug_panel)

	var vbox : VBoxContainer = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(220.0, 0.0)
	_debug_panel.add_child(vbox)

	var title : Label = Label.new()
	title.text = "── LEVEL SELECT ──"
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	for i in levels.size():
		var btn : Button = Button.new()
		btn.text         = "%d  %s" % [i + 1, get_level_name(i)]
		btn.alignment    = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(load_level.bind(i))
		vbox.add_child(btn)
		_level_buttons.append(btn)

	vbox.add_child(HSeparator.new())

	_status_label      = Label.new()
	_status_label.text = "No level loaded"
	_status_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_label)

	var hint : Label = Label.new()
	hint.text         = "F2 ← Prev   F3 → Next   1-9 Jump"
	hint.add_theme_color_override("font_color", Color("#888888"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)

	# Always-visible corner label
	var corner_canvas : CanvasLayer = CanvasLayer.new()
	corner_canvas.layer = 99
	add_child(corner_canvas)

	_corner_label                = Label.new()
	_corner_label.name           = "CornerLabel"
	_corner_label.text           = ""
	_corner_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6, 0.85))
	_corner_label.add_theme_font_size_override("font_size", 13)
	_corner_label.anchor_left    = 1.0
	_corner_label.anchor_right   = 1.0
	_corner_label.anchor_top     = 0.0
	_corner_label.offset_left    = -260.0
	_corner_label.offset_right   = -10.0
	_corner_label.offset_top     = 10.0
	corner_canvas.add_child(_corner_label)


func _toggle_debug_panel() -> void:
	if not _debug_panel:
		return
	_debug_visible       = !_debug_visible
	_debug_panel.visible = _debug_visible


func _update_debug_highlight(next_index : int) -> void:
	if not debug_mode:
		return
	for i in _level_buttons.size():
		var btn : Button = _level_buttons[i]
		if i == next_index:
			btn.add_theme_color_override("font_color",       Color.YELLOW)
			btn.add_theme_color_override("font_hover_color", Color.YELLOW)
		else:
			btn.remove_theme_color_override("font_color")
			btn.remove_theme_color_override("font_hover_color")


func _refresh_debug_status() -> void:
	if not debug_mode:
		return
	var text : String = "[%d/%d]  %s" % [current_index + 1, levels.size(),
										  get_level_name(current_index)]
	if _status_label:
		_status_label.text = text
	if _corner_label:
		_corner_label.text = "` = levels  |  " + text
