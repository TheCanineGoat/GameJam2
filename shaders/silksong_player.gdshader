// ================================================================
//  SILKSONG PLAYER SHADER
//  Attach to your Sprite2D or AnimatedSprite2D
//
//  HOW TO APPLY
//  ─────────────
//  1. Select your Sprite2D / AnimatedSprite2D
//  2. Inspector → CanvasItem → Material → New ShaderMaterial
//  3. ShaderMaterial → Shader → Load → pick this file
// ================================================================

shader_type canvas_item;
render_mode blend_mix;

// ── Sky blue illumination ────────────────────────────────────────
uniform vec4  glow_color     : source_color = vec4(0.35, 0.65, 1.0, 1.0);
uniform float tint_strength  : hint_range(0.0, 1.0) = 0.28;

// ── Rim / edge glow ──────────────────────────────────────────────
uniform float rim_radius     : hint_range(1.0, 8.0)  = 3.0;
uniform float rim_strength   : hint_range(0.0, 2.0)  = 0.90;

// ── Breathing flicker ────────────────────────────────────────────
uniform float flicker_speed  : hint_range(0.0, 5.0)  = 1.1;
uniform float flicker_amount : hint_range(0.0, 0.4)  = 0.12;

// ── Darkness bias ────────────────────────────────────────────────
uniform float shadow_bias    : hint_range(0.0, 0.8)  = 0.18;


// ── Helpers ──────────────────────────────────────────────────────

// Soft breathing pulse — gives the rim glow a "living soul" feel
float flicker(float speed, float amount) {
	float f  = sin(TIME * speed) * 0.5 + 0.5;
	      f += sin(TIME * speed * 2.371) * 0.25;
	return 1.0 + (f - 0.5) * amount;
}

// Sample alpha at a pixel offset.
// pixel_size must be passed in from fragment() because built-ins
// (TEXTURE_PIXEL_SIZE) are not accessible inside helper functions.
float sample_alpha(sampler2D tex, vec2 uv, vec2 offset, vec2 pixel_size) {
	vec2 s = clamp(uv + offset * pixel_size, vec2(0.0), vec2(1.0));
	return texture(tex, s).a;
}


// ── Fragment ─────────────────────────────────────────────────────

void fragment() {
	vec4 sprite      = texture(TEXTURE, UV);
	vec2 pixel_size  = TEXTURE_PIXEL_SIZE;   // capture here, pass into helpers

	if (sprite.a < 0.01) {
		// ── Transparent pixel — build the rim glow ───────────────
		float rim = 0.0;
		float r   = rim_radius;

		for (float i = 1.0; i <= r; i += 1.0) {
			// Cardinal directions
			rim += sample_alpha(TEXTURE, UV, vec2( i,  0.0), pixel_size);
			rim += sample_alpha(TEXTURE, UV, vec2(-i,  0.0), pixel_size);
			rim += sample_alpha(TEXTURE, UV, vec2( 0.0,  i), pixel_size);
			rim += sample_alpha(TEXTURE, UV, vec2( 0.0, -i), pixel_size);
			// Diagonal directions (weighted down so corners aren't too strong)
			rim += sample_alpha(TEXTURE, UV, vec2( i,  i), pixel_size) * 0.7;
			rim += sample_alpha(TEXTURE, UV, vec2(-i,  i), pixel_size) * 0.7;
			rim += sample_alpha(TEXTURE, UV, vec2( i, -i), pixel_size) * 0.7;
			rim += sample_alpha(TEXTURE, UV, vec2(-i, -i), pixel_size) * 0.7;
		}

		rim  = clamp(rim / (r * 6.8), 0.0, 1.0);
		rim *= rim_strength * flicker(flicker_speed, flicker_amount);
		rim  = smoothstep(0.0, 1.0, rim);

		COLOR = vec4(glow_color.rgb, rim * glow_color.a);

	} else {
		// ── Opaque pixel — sky-blue tint + shadow bias ───────────
		float pulse  = flicker(flicker_speed, flicker_amount * 0.5);
		float luma   = dot(sprite.rgb, vec3(0.299, 0.587, 0.114));

		vec3 tinted  = mix(sprite.rgb, glow_color.rgb, tint_strength * pulse);
		tinted      *= (1.0 - shadow_bias);

		// Restore bright highlights so the sprite doesn't go flat
		tinted       = mix(tinted, sprite.rgb, luma * 0.35);

		COLOR        = vec4(tinted, sprite.a);
	}
}
