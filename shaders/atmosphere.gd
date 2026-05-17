extends CanvasLayer

# ================================================================
#  SILKSONG ATMOSPHERE  —  runtime setup
#  Attach to any CanvasLayer node in your level scene.
#
#  QUICK SETUP
#  ───────────
#  1. In your level scene add a CanvasLayer node
#  2. Attach this script
#  3. Set layer = 10 (above world, below HUD)
#  4. Drag silksong_atmosphere.gdshader into the shader slot below
#  5. Run — done
#
#  You can also create a second CanvasLayer with layer = -1 and
#  attach this script there to darken the background behind the
#  player rather than in front.
# ================================================================

@export var atmosphere_shader : Shader = null

## Render layer — keep between world (0) and HUD (100)
## Use a low layer (e.g. 5) so it sits BEHIND the player's rim glow
## Use a higher layer (e.g. 15) to fog OVER the player
@export_range(-128, 128, 1) var canvas_layer : int = 8

## Master opacity of the whole atmosphere overlay
@export_range(0.0, 1.0, 0.01) var master_opacity : float = 1.0


var _rect : ColorRect
var _mat  : ShaderMaterial


func _ready() -> void:
	layer = canvas_layer

	_rect              = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.modulate.a   = master_opacity
	add_child(_rect)

	if atmosphere_shader != null:
		_mat        = ShaderMaterial.new()
		_mat.shader = atmosphere_shader
		_rect.material = _mat
	else:
		push_warning(
			"Atmosphere: no shader assigned.\n" +
			"Drag silksong_atmosphere.gdshader into the 'Atmosphere Shader' slot."
		)


# ── Public API ───────────────────────────────────────────────────

## Fade the atmosphere in or out smoothly.
func set_opacity(target : float, duration : float = 1.0) -> void:
	var tw : Tween = create_tween()
	tw.tween_property(_rect, "modulate:a", target, duration) \
	  .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Adjust any shader parameter at runtime.
## E.g.: $Atmosphere.set_param("darkness", 0.9)
func set_param(param_name : String, value : Variant) -> void:
	if _mat != null:
		_mat.set_shader_parameter(param_name, value)
