extends CanvasLayer
class_name DamageVignette

# ================================================================
#  DAMAGE VIGNETTE
#  Node : CanvasLayer  → child of the Player node
#
#  No health bar. The screen bleeds bluish-black as health drops.
#  How fast it darkens is driven by damage_rate — burst damage
#  snaps the screen dark instantly; slow chip damage creeps in.
#
#  SCENE SETUP
#  ───────────
#  CharacterBody2D
#  ├── HealthComponent  [health_component.gd]
#  ├── HurtBox          [hurtbox.gd]
#  └── DamageVignette   [damage_vignette.gd]   ← this script
#       (Camera2D can stay as child of CharacterBody2D — vignette
#        is a CanvasLayer so it always renders over the whole screen)
#
#  WIRING (in _ready or via Inspector signals)
#  ────────────────────────────────────────────
#  Connect HealthComponent.health_changed   → on_health_changed
#  Connect HealthComponent.damage_rate_changed → on_damage_rate_changed
#  Connect HealthComponent.died             → on_died
#  Connect HealthComponent.respawned        → on_respawned
#
#  OR set health_component export and let _ready wire everything.
# ================================================================


@export_group("🎨 Colour")

## The colour the edges bleed toward at low health (dark bluish-black)
@export var vignette_color : Color = Color(0.02, 0.04, 0.16, 1.0)

## Extra flash colour fired the instant damage is taken
@export var hit_flash_color : Color = Color(0.04, 0.06, 0.25, 1.0)

## Death fill colour — covers the whole screen on death
@export var death_color : Color = Color(0.01, 0.02, 0.10, 1.0)


@export_group("💧 Vignette Shape")

## How far the vignette reaches inward from the edges (0=tiny rim, 1=fills screen)
@export_range(0.0, 1.0, 0.01)
var vignette_radius : float = 0.70

## Edge softness — higher = softer gradient
@export_range(0.1, 3.0, 0.05)
var vignette_softness : float = 1.4

## Maximum vignette opacity at 0 HP (stays below 1 so center stays slightly visible)
@export_range(0.0, 1.0, 0.01)
var max_vignette_alpha : float = 0.92


@export_group("⚡ Transition Speed")

## Base lerp speed when barely any damage is being dealt
@export_range(0.1, 20.0, 0.1)
var base_speed : float = 2.5

## How much damage_rate adds to the transition speed
## (damage_rate spike of 10 × this = extra speed added)
@export_range(0.0, 2.0, 0.05)
var rate_speed_multiplier : float = 0.55

## Maximum lerp speed cap (prevents epileptic instant flicker)
@export_range(2.0, 60.0, 1.0)
var max_speed : float = 28.0


@export_group("🔌 Auto-wire")

## Drag your HealthComponent node here to wire signals automatically
@export var health_component : HealthComponent = null


# ── Internal ─────────────────────────────────────────────────────
var _persistent_alpha : float = 0.0   # tracks current low-health vignette
var _target_alpha     : float = 0.0   # where we lerp toward
var _flash_alpha      : float = 0.0   # short-lived hit flash on top
var _current_speed    : float = 0.0   # lerp speed this frame
var _is_dead          : bool  = false
var _death_alpha      : float = 0.0   # full-screen death fade
var _is_regenerating  : bool  = false # true while regen is active

var _shader_mat       : ShaderMaterial
var _rect             : ColorRect


# ================================================================
#  VIGNETTE SHADER (embedded — no external .gdshader file needed)
# ================================================================

const _SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float vignette_alpha    : hint_range(0.0, 1.0) = 0.0;
uniform float flash_alpha       : hint_range(0.0, 1.0) = 0.0;
uniform float death_alpha       : hint_range(0.0, 1.0) = 0.0;
uniform float vignette_radius   : hint_range(0.0, 1.0) = 0.7;
uniform float vignette_softness : hint_range(0.1, 3.0) = 1.4;
uniform vec4  vignette_color    : source_color = vec4(0.02, 0.04, 0.16, 1.0);
uniform vec4  hit_flash_color   : source_color = vec4(0.04, 0.06, 0.25, 1.0);
uniform vec4  death_color       : source_color = vec4(0.01, 0.02, 0.10, 1.0);

void fragment() {
    // ── Vignette mask ───────────────────────────────────────
    vec2  uv        = UV - vec2(0.5);
    float dist      = length(uv * vec2(1.0, 1.0));
    float edge      = smoothstep(vignette_radius - 0.35 / vignette_softness,
                                 vignette_radius + 0.35 / vignette_softness,
                                 dist * vignette_softness);

    // ── Layer 1: persistent low-health vignette ─────────────
    vec4 vig = vec4(vignette_color.rgb, edge * vignette_alpha);

    // ── Layer 2: hit flash (brighter center pulse) ──────────
    float flash_mask = (1.0 - edge) * 0.6 + edge;   // stronger at edges
    vec4 flash       = vec4(hit_flash_color.rgb, flash_mask * flash_alpha);

    // ── Layer 3: full-screen death cover ────────────────────
    vec4 death       = vec4(death_color.rgb, death_alpha);

    // ── Composite (back to front) ────────────────────────────
    vec4 out_col     = vig;
    out_col          = mix(out_col, flash,  flash_alpha  * flash_mask);
    out_col.a        = clamp(out_col.a + flash.a + death_alpha, 0.0, 1.0);
    out_col.rgb      = mix(out_col.rgb, death_color.rgb, death_alpha);

    COLOR = out_col;
}
"""


# ================================================================
#  READY
# ================================================================

func _ready() -> void:
	layer = 99   # render above everything

	# ── Full-screen ColorRect ───────────────────────────────────
	_rect                  = ColorRect.new()
	_rect.color            = Color.TRANSPARENT
	_rect.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)

	# ── Build shader material ───────────────────────────────────
	var shader             := Shader.new()
	shader.code             = _SHADER_CODE
	_shader_mat             = ShaderMaterial.new()
	_shader_mat.shader      = shader
	_rect.material          = _shader_mat

	# Push static tuning params into shader
	_shader_mat.set_shader_parameter("vignette_color",    vignette_color)
	_shader_mat.set_shader_parameter("hit_flash_color",   hit_flash_color)
	_shader_mat.set_shader_parameter("death_color",       death_color)
	_shader_mat.set_shader_parameter("vignette_radius",   vignette_radius)
	_shader_mat.set_shader_parameter("vignette_softness", vignette_softness)

	# ── Auto-wire signals if health_component is set ────────────
	if health_component:
		health_component.health_changed.connect(on_health_changed)
		health_component.damage_rate_changed.connect(on_damage_rate_changed)
		health_component.died.connect(on_died)
		health_component.respawned.connect(on_respawned)
		health_component.regen_started.connect(on_regen_started)
		health_component.regen_stopped.connect(on_regen_stopped)


# ================================================================
#  PROCESS — smooth all values toward their targets each frame
# ================================================================

func _process(delta : float) -> void:
	# While regen is active, hold the fade-out speed boosted
	if _is_regenerating and not _is_dead:
		_current_speed = maxf(_current_speed, base_speed * 3.0)

	# Persistent vignette lerps at damage-rate-adjusted speed
	_persistent_alpha = lerpf(_persistent_alpha, _target_alpha,
							  _current_speed * delta)

	# Hit flash decays quickly on its own
	_flash_alpha = lerpf(_flash_alpha, 0.0, 18.0 * delta)

	# Death cover lerps in / out
	if _is_dead:
		_death_alpha = lerpf(_death_alpha, 1.0, 3.5 * delta)
	else:
		_death_alpha = lerpf(_death_alpha, 0.0, 4.0 * delta)

	# Push updated values to shader
	_shader_mat.set_shader_parameter("vignette_alpha", _persistent_alpha)
	_shader_mat.set_shader_parameter("flash_alpha",    _flash_alpha)
	_shader_mat.set_shader_parameter("death_alpha",    _death_alpha)


# ================================================================
#  SIGNAL HANDLERS — wire these to HealthComponent
# ================================================================

## Called by HealthComponent.health_changed
func on_health_changed(old_val : float, new_val : float, delta : float) -> void:
	var health_pct  := new_val / health_component.max_health if health_component \
					   else clampf(new_val / 100.0, 0.0, 1.0)

	# Persistent target: more damage = darker vignette
	_target_alpha    = (1.0 - health_pct) * max_vignette_alpha

	# Spike a hit flash whenever actual damage is taken
	if delta > 0.0:
		_flash_alpha = clampf(delta / 25.0, 0.15, 0.6)


## Called by HealthComponent.damage_rate_changed
## rate = rolling damage-per-second feel emitted by HealthComponent
func on_damage_rate_changed(rate : float) -> void:
	# Faster damage rate → faster vignette transition
	_current_speed = clampf(base_speed + rate * rate_speed_multiplier, base_speed, max_speed)


## Called by HealthComponent.died
func on_died() -> void:
	_is_dead      = true
	_target_alpha = max_vignette_alpha


## Called by HealthComponent.respawned
func on_respawned() -> void:
	_is_dead        = false
	_is_regenerating = false
	_target_alpha   = 0.0
	_flash_alpha    = 0.0
	_current_speed  = base_speed


## Called by HealthComponent.regen_started
## Regen is active — speed up the vignette fade-out so the screen clears
func on_regen_started() -> void:
	_is_regenerating = true
	# Fade the vignette out faster while regen is active
	_current_speed   = maxf(_current_speed, base_speed * 3.0)


## Called by HealthComponent.regen_stopped (interrupted by a hit or reached full HP)
func on_regen_stopped() -> void:
	_is_regenerating = false
	_current_speed   = base_speed


# ================================================================
#  PUBLIC API
# ================================================================

## Manually trigger a flash (e.g. environmental damage, cutscene hit)
func flash(strength : float = 0.4) -> void:
	_flash_alpha = clampf(strength, 0.0, 1.0)


## Hard-reset all vignette values instantly (use after scene transitions)
func reset() -> void:
	_persistent_alpha = 0.0
	_target_alpha     = 0.0
	_flash_alpha      = 0.0
	_death_alpha      = 0.0
	_is_dead          = false
	_shader_mat.set_shader_parameter("vignette_alpha", 0.0)
	_shader_mat.set_shader_parameter("flash_alpha",    0.0)
	_shader_mat.set_shader_parameter("death_alpha",    0.0)
