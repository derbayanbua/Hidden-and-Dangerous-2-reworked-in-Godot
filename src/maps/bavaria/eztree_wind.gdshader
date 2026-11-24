// Bäume aus dem EZ-Tree-Generator (MIT): Rinde und Laubkarten mit leichtem Wind per Vertex-Animation.
// Ausschlag wächst quadratisch mit der Höhe über dem Stammfuß (Modellraum) → Stamm steht, Krone wiegt.
// Phase aus der Weltlage des Baums (MultiMesh: je Instanz) → Bäume schwingen nicht im Gleichtakt.
// Laub (11/2026): Kronen-Normalen (Karten werden wie eine gewölbte Krone beleuchtet statt als flache Pappe),
// Kronenverschattung innen/unten, Farbstreuung je Baum, Karten in Streifansicht ausgeblendet (keine Striche/Kanten).
// Rinde: Verschattung/Erdfarbe am Stammfuß, Farbstreuung je Baum.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = true;
uniform vec4 tint : source_color = vec4(1.0);
uniform float roughness_value = 0.9;
uniform bool is_leaf = false;
uniform float alpha_cut = 0.45;
uniform float tree_height = 12.0;    // Modellhöhe [m] (vor Instanzskalierung)
uniform float sway = 0.06;           // Ausschlag an der Spitze [Modelleinheiten je Modellhöhe]
uniform float flutter = 0.025;       // zusätzliches Blattzittern (nur Laub)
uniform float wind_speed = 1.1;
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform float translucency = 0.35;
// Krone (Anteile der Modellhöhe): Mitte und Halbmesser für Kronen-Normalen/Verschattung; crown_normal 0 = alt
uniform float crown_center = 0.6;
uniform float crown_radius = 0.3;
uniform float crown_normal = 0.0;
uniform float crown_ao = 0.0;        // 0 = keine Kronenverschattung, 1 = innen/unten bis ~45 % dunkler
uniform float color_vary = 0.0;      // Helligkeits-/Farbstreuung je Baum
uniform float saturation = 1.0;
uniform float edge_fade = 0.0;       // Streifansicht: Schwelle zusätzlich anheben (0 = aus)
uniform float base_dark = 0.0;       // Rinde: Abdunklung/Erdton bis base_height über dem Fuß
uniform float base_height = 0.6;

varying float v_ao;
varying vec3 v_vary;
varying vec3 v_card_n;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = dot(origin.xz, vec2(0.37, 0.21));
	vec3 rest = VERTEX;
	float h = clamp(VERTEX.y / max(tree_height, 0.1), 0.0, 1.5);
	float bend = h * h * sway * tree_height;
	float t = TIME * wind_speed + phase;
	float gust = sin(t) * 0.6 + sin(t * 2.3 + 1.7) * 0.3 + sin(t * 0.37) * 0.4;
	vec2 d = normalize(wind_dir);
	VERTEX.xz += d * bend * gust;
	VERTEX.y -= abs(bend * gust) * 0.15;
	float r1 = hash(origin.xz);
	float r2 = hash(origin.zx + 3.1);
	v_vary = vec3(1.0 + (r1 - 0.5) * color_vary, 1.0 + (r2 - 0.5) * color_vary * 0.6, 1.0 + (r1 - r2) * color_vary * 0.5);
	v_card_n = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	if (is_leaf) {
		float f = sin(TIME * 6.0 + VERTEX.x * 3.1 + VERTEX.z * 2.7 + phase * 5.0);
		VERTEX += NORMAL * f * flutter * h * tree_height * 0.05;
		vec3 c = vec3(0.0, crown_center * tree_height, 0.0);
		vec3 rel = (rest - c) / max(crown_radius * tree_height, 0.1);
		float len = length(rel);
		if (crown_normal > 0.0 && len > 0.001) {
			NORMAL = normalize(mix(NORMAL, rel / len, crown_normal));
		}
		// außen/oben hell, innen/unten dunkel (Selbstverschattung der Krone)
		float outer = clamp(len, 0.0, 1.0);
		float up = clamp(rel.y * 0.5 + 0.5, 0.0, 1.0);
		v_ao = mix(1.0, mix(0.62, 1.0, clamp(outer * 0.65 + up * 0.45, 0.0, 1.0)), crown_ao);
	} else {
		v_ao = mix(1.0, smoothstep(0.0, base_height, rest.y) * 0.45 + 0.55, base_dark);
	}
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	vec3 col = c.rgb * tint.rgb * v_vary;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, saturation);
	ALBEDO = col * v_ao;
	ROUGHNESS = roughness_value;
	SPECULAR = is_leaf ? 0.2 : 0.15;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	if (is_leaf) {
		// Rückseite: Godot wendet die Normale; die Kronen-Normale zeigt aber für beide Seiten nach außen
		if (!FRONT_FACING && crown_normal > 0.5) {
			NORMAL = -NORMAL;
		}
		ALPHA = c.a;
		float facing = length(v_card_n) > 1e-5 ? abs(dot(normalize(v_card_n), VIEW)) : 1.0;
		ALPHA_SCISSOR_THRESHOLD = mix(min(alpha_cut + edge_fade, 0.98), alpha_cut, smoothstep(0.12, 0.45, facing));
		ALPHA_ANTIALIASING_EDGE = 0.3;
		BACKLIGHT = col * translucency * v_ao;
	}
}
