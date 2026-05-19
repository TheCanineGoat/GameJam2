// ================================================================
//  SILKSONG ATMOSPHERE SHADER
//  Full-screen overlay: darkness · dust · fog · smoke
//  Attach to a ColorRect inside a CanvasLayer (see atmosphere.gd)
// ================================================================

shader_type canvas_item;
render_mode unshaded, blend_mix;

// ── Darkness ─────────────────────────────────────────────────────
uniform float darkness          : hint_range(0.0, 1.0)  = 0.72;
uniform float vignette_softness : hint_range(0.1, 3.0)  = 1.3;
uniform float vignette_radius   : hint_range(0.0, 1.0)  = 0.62;
uniform vec4  dark_tint         : source_color           = vec4(0.03, 0.04, 0.10, 1.0);

// ── Dust particles ───────────────────────────────────────────────
uniform float dust_density      : hint_range(0.0, 1.0)  = 0.45;  // cell grid density
uniform float dust_size         : hint_range(0.001, 0.02) = 0.006;
uniform float dust_speed        : hint_range(0.0, 0.5)  = 0.04;
uniform float dust_brightness   : hint_range(0.0, 1.0)  = 0.65;
uniform vec4  dust_color        : source_color           = vec4(0.92, 0.95, 1.0, 1.0);

// ── Fog ──────────────────────────────────────────────────────────
uniform float fog_density       : hint_range(0.0, 1.0)  = 0.28;
uniform float fog_speed         : hint_range(0.0, 0.2)  = 0.018;
uniform float fog_scale         : hint_range(0.5, 8.0)  = 2.8;
uniform vec4  fog_color         : source_color           = vec4(0.80, 0.86, 1.0, 1.0);

// ── Smoke ────────────────────────────────────────────────────────
uniform float smoke_density     : hint_range(0.0, 1.0)  = 0.18;
uniform float smoke_speed       : hint_range(0.0, 0.3)  = 0.035;
uniform float smoke_scale       : hint_range(0.5, 12.0) = 5.5;
uniform vec4  smoke_color       : source_color           = vec4(0.70, 0.78, 0.92, 1.0);


// ================================================================
//  NOISE LIBRARY
// ================================================================

// Low-cost hash — returns [0, 1]
float hash1(vec2 p) {
	p  = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float hash1_f(float n) {
	return fract(sin(n) * 43758.5453);
}

// Smooth value noise
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f      = f * f * (3.0 - 2.0 * f);   // smoothstep

	float a = hash1(i);
	float b = hash1(i + vec2(1.0, 0.0));
	float c = hash1(i + vec2(0.0, 1.0));
	float d = hash1(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractional Brownian Motion — layered octaves of noise
float fbm(vec2 p) {
	float v   = 0.0;
	float amp = 0.50;
	float frq = 1.00;
	for (int i = 0; i < 5; i++) {
		v   += amp * vnoise(p * frq);
		frq *= 2.07;
		amp *= 0.48;
	}
	return v;
}


// ================================================================
//  DUST
// ================================================================
//
//  Cellular approach: tile UV into a grid, place one particle per
//  cell. Checking 3×3 neighbours handles particles near boundaries.
//  This runs in constant time regardless of particle count.

float dust_layer(vec2 uv) {
	float cell_size = dust_density * 0.18 + 0.04;
	vec2  cell      = floor(uv / cell_size);
	float result    = 0.0;

	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 nc   = cell + vec2(float(x), float(y));

			// Random resting position within the cell
			float rx  = hash1(nc);
			float ry  = hash1(nc + vec2(73.1, 113.7));

			// Per-particle drift direction & speed variation
			float spd = hash1(nc + vec2(17.3, 91.5)) * dust_speed + dust_speed * 0.3;
			float sx  = (hash1(nc + vec2(53.2, 7.4)) - 0.5) * 0.3;

			// Animated position — drift upward, slight horizontal sway
			float py  = fract(ry - TIME * spd);
			float px  = fract(rx + sin(TIME * 0.4 + rx * 6.28) * sx * 0.02);

			// World UV of this particle
			vec2 part = (nc + vec2(px, py)) * cell_size;
			float d   = length(uv - part);

			// Twinkle: opacity pulses per particle
			float twinkle = 0.6 + 0.4 * sin(TIME * (1.5 + hash1(nc) * 2.0) + hash1(nc + 1.0) * 6.28);

			result += smoothstep(dust_size, 0.0, d) * twinkle;
		}
	}
	return clamp(result, 0.0, 1.0);
}


// ================================================================
//  FOG
// ================================================================
//
//  Two slow-moving fbm layers blended together.
//  Bottom-heavy — fog sits low in the frame.

float fog_layer(vec2 uv) {
	vec2 motion_a = vec2(TIME * fog_speed,       TIME * fog_speed * 0.4);
	vec2 motion_b = vec2(-TIME * fog_speed * 0.7, TIME * fog_speed * 0.3);

	float f_a = fbm((uv + motion_a) * fog_scale);
	float f_b = fbm((uv + motion_b) * fog_scale * 1.6 + vec2(4.3, 2.1));

	float fog = mix(f_a, f_b, 0.45);

	// Weight fog toward the bottom third of screen
	float ground_weight = smoothstep(0.3, 0.85, uv.y);
	fog  *= ground_weight;

	// Threshold — only thicker noise regions show as fog
	fog   = smoothstep(0.42, 0.70, fog);

	return clamp(fog * fog_density, 0.0, fog_density);
}


// ================================================================
//  SMOKE
// ================================================================
//
//  Sparse, wispy puffs that drift upward and dissipate.
//  Higher frequency than fog for more texture.

float smoke_layer(vec2 uv) {
	vec2 motion = vec2(TIME * smoke_speed * 0.5, -TIME * smoke_speed);

	float s_a = fbm((uv + motion) * smoke_scale);
	float s_b = fbm((uv + motion * 1.3 + vec2(2.7, 5.1)) * smoke_scale * 0.75);

	float smk = s_a * s_b * 2.2;

	// Smoke fades at bottom and top — hangs in the middle air
	float height_fade = smoothstep(0.9, 0.6, uv.y) * smoothstep(0.1, 0.3, uv.y);
	smk *= height_fade;

	// Occasional density — most of the time it's very faint
	smk = smoothstep(0.35, 0.60, smk);

	return clamp(smk * smoke_density, 0.0, smoke_density);
}


// ================================================================
//  VIGNETTE  (the surrounding darkness)
// ================================================================

float vignette(vec2 uv) {
	vec2  centered = uv - vec2(0.5);
	float dist     = length(centered);
	return smoothstep(vignette_radius - 0.3 / vignette_softness,
	                  vignette_radius + 0.3 / vignette_softness,
	                  dist * vignette_softness);
}


// ================================================================
//  FRAGMENT
// ================================================================

void fragment() {
	vec2 uv = UV;

	// ── 1. Base: transparent center ──────────────────────────────
	vec4 out_col = vec4(0.0);

	// ── 2. Dust particles ────────────────────────────────────────
	float d     = dust_layer(uv) * dust_brightness;
	out_col      = mix(out_col, vec4(dust_color.rgb, 1.0), d * dust_color.a);

	// ── 3. Fog ───────────────────────────────────────────────────
	float f     = fog_layer(uv);
	out_col      = mix(out_col, vec4(fog_color.rgb, 1.0), f * fog_color.a);

	// ── 4. Smoke  ────────────────────────────────────────────────
	float s     = smoke_layer(uv);
	out_col      = mix(out_col, vec4(smoke_color.rgb, 1.0), s * smoke_color.a);

	// ── 5. Vignette darkness ─────────────────────────────────────
	float vig   = vignette(uv) * darkness;
	out_col.rgb  = mix(out_col.rgb, dark_tint.rgb, vig);
	out_col.a    = max(out_col.a, vig);

	COLOR = out_col;
}
