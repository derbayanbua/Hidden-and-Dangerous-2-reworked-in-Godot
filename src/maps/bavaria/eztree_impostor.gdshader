// Ferne EZ-Tree-Bäume als Kreuz-Billboard (2 gekreuzte Quads, Atlas links vorn / rechts Seite, gerendert von
// tests/render_eztree_impostors.gd). Beleuchtet (Tageszeit/Nacht wirken), Normale als gewölbte Krone angenähert
// (Mitte zum Betrachter, Ränder seitlich, oben nach oben) – keine flache Pappwand im Streiflicht.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform float alpha_cut = 0.5;
uniform float sway = 0.01;
uniform float translucency = 0.3;
uniform vec4 tint : source_color = vec4(1.0);   // Abgleich an die Laubfarbe der 3D-Bäume (eztree.gd)
uniform float saturation = 1.0;

varying vec2 quad_uv;

void vertex() {
	quad_uv = UV2;     // 0..1 je Quad (x quer, y von unten)
	float h = UV2.y;
	float t = TIME * 1.1 + dot(MODEL_MATRIX[3].xz, vec2(0.37, 0.21));
	VERTEX.xz += vec2(0.8, 0.6) * h * h * sway * VERTEX.y * (sin(t) * 0.6 + sin(t * 2.3 + 1.7) * 0.3);
}

void fragment() {
	vec4 c = texture(atlas, UV);
	c.rgb *= tint.rgb;
	c.rgb = mix(vec3(dot(c.rgb, vec3(0.299, 0.587, 0.114))), c.rgb, saturation);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	// Kronenwölbung: Quadnormale (zum Betrachter gedreht) + Seiten-/Aufwärtsanteil aus der Lage im Quad
	vec3 n = NORMAL;     // Rückseite: von Godot bereits gewendet
	vec3 side = normalize(cross(n, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz));
	vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	float sx = (quad_uv.x - 0.5) * 1.6;
	float sy = (quad_uv.y - 0.45) * 1.2;
	NORMAL = normalize(n + side * sx + up * max(sy, 0.0) * 0.8);
	// Schatten im Kroneninneren / unten dunkler
	ALBEDO *= mix(0.75, 1.0, clamp(quad_uv.y * 1.4, 0.0, 1.0));
	BACKLIGHT = c.rgb * translucency;
}
