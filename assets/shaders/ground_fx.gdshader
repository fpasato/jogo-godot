shader_type canvas_item;

// ============================================================
// GROUND FX — chão mágico escuro (círculo de invocação)
// ============================================================

// --- Paleta ---
uniform vec4 base_dark : source_color = vec4(0.010, 0.005, 0.022, 1.0);
uniform vec4 base_deep : source_color = vec4(0.035, 0.015, 0.090, 1.0);
uniform vec4 glow_color : source_color = vec4(0.14, 0.42, 1.0, 1.0);
uniform vec4 accent_color : source_color = vec4(0.55, 0.85, 1.0, 1.0);

// --- Geometria do círculo ---
uniform vec2  center = vec2(0.5, 0.5);
uniform float circle_radius    : hint_range(0.05, 1.5)  = 0.38;
uniform float circle_thickness : hint_range(0.001, 0.05) = 0.006;

// --- Animação ---
uniform float time_scale   : hint_range(0.0, 4.0) = 1.0;
uniform float pulse_speed  : hint_range(0.0, 5.0) = 1.6;
uniform float rot_speed    : hint_range(-2.0, 2.0) = 0.18;
uniform float noise_scale  : hint_range(1.0, 20.0) = 6.0;

// --- Intensidades ---
uniform float circle_intensity  : hint_range(0.0, 3.0) = 1.2;
uniform float veins_intensity   : hint_range(0.0, 3.0) = 1.0;
uniform float glow_intensity    : hint_range(0.0, 3.0) = 1.5;
uniform float vignette_strength : hint_range(0.0, 2.0) = 1.0;

// ============================================================
// Utilidades
// ============================================================

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * noise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

// banda circular com anti-alias
float band(float d, float r, float w) {
	return smoothstep(w, 0.0, abs(d - r));
}

// ============================================================
// Fragment
// ============================================================

void fragment() {
	vec2 uv = UV;
	vec2 p  = uv - center;
	float t = TIME * time_scale;

	float dist  = length(p);
	float angle = atan(p.y, p.x);

	// ---------- Base: gradiente escuro central ----------
	vec3 base = mix(base_deep.rgb, base_dark.rgb, smoothstep(0.0, 0.95, dist));

	// ---------- Rachaduras orgânicas (FBM) ----------
	vec2 nq = uv * noise_scale + vec2(t * 0.15, -t * 0.10);
	float n1 = fbm(nq);
	float n2 = fbm(nq * 1.7 + 4.0);

	float cracks = smoothstep(0.72, 0.90, n1)
	             + smoothstep(0.78, 0.95, n2) * 0.6;

	// respiração: pulso viajando pelo chão
	float pulse = 0.5 + 0.5 * sin(t * pulse_speed - dist * 18.0);
	cracks *= cracks * (0.40 + 0.60 * pulse);

	// ---------- Veias radiais (energia vindo do centro) ----------
	float warp  = fbm(vec2(angle * 3.0, t * 0.30)) * 4.0;
	float veins = sin(angle * 9.0 + t * 0.40 + warp);
	float veins_mask = smoothstep(0.85, 1.0, veins)
	                 * smoothstep(0.95, 0.20, dist);
	veins_mask *= 0.5 + 0.5 * sin(t * 2.5 + dist * 12.0);

	// ---------- Círculo mágico ----------
	float rot   = t * rot_speed;
	float a_rot = angle + rot;
	float cr    = circle_radius;

	float circle_outer = band(dist, cr,          circle_thickness);
	float circle_inner = band(dist, cr * 0.78,   circle_thickness * 0.8);
	float circle_mid   = band(dist, cr * 0.55,   circle_thickness * 1.2) * 0.6;

	// runas no anel externo (giram num sentido)
	float rune_a = sin(a_rot * 40.0) * 0.5 + 0.5;
	float runes_outer = smoothstep(0.60, 1.0, rune_a)
	                  * band(dist, cr * 0.90, circle_thickness * 3.0);

	// runas no anel interno (sentido oposto)
	float rune_b = sin(-a_rot * 28.0) * 0.5 + 0.5;
	float runes_inner = smoothstep(0.70, 1.0, rune_b)
	                  * band(dist, cr * 0.67, circle_thickness * 2.5);

	// ticks finos atravessando o anel externo
	float ticks = smoothstep(0.92, 1.0, cos(a_rot * 16.0))
	            * band(dist, cr, circle_thickness * 5.0) * 0.5;

	float circle_glow = circle_outer + circle_inner + circle_mid;
	circle_glow += (runes_outer + runes_inner + ticks) * 1.5;

	// pulso do círculo inteiro
	float circle_pulse = 0.60 + 0.40 * sin(t * pulse_speed * 1.5);
	circle_glow *= circle_pulse * circle_intensity;

	// halo suave em volta do anel
	float halo = exp(-pow((dist - cr) * 22.0, 2.0)) * 0.45;

	// ---------- Núcleo de energia no centro ----------
	float core = exp(-dist * 10.0) * (0.70 + 0.30 * sin(t * pulse_speed * 2.0));

	// ---------- Compõe ----------
	vec3 col = base;

	col += glow_color.rgb   * cracks       * veins_intensity * 0.85;
	col += glow_color.rgb   * veins_mask   * veins_intensity * 0.60;
	col += mix(glow_color.rgb, accent_color.rgb, 0.4) * circle_glow * 0.90;
	col += accent_color.rgb * halo * 0.70;
	col += accent_color.rgb * core * glow_intensity;

	// anel de choque expandindo periodicamente
	float ring_phase = fract(t * 0.55);
	float ring_r     = ring_phase * 0.85;
	float shock      = band(dist, ring_r, 0.008) * (1.0 - ring_phase);
	col += accent_color.rgb * shock * glow_intensity * 0.80;

	// brilho ambiente sutil perto do centro
	col += glow_color.rgb * smoothstep(0.60, 0.0, dist) * 0.12;

	// ---------- Vinheta (escurece as bordas) ----------
	float vig = smoothstep(0.35, 0.95, dist);
	col *= 1.0 - vig * vignette_strength;

	COLOR = vec4(col, 1.0);
}