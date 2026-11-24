shader_type spatial;
// Umlaufende Fernkulisse als echter Ring (src/maps/bavaria/panorama_ring.gd): gleiche Bilder, Sektoren und Überblendung
// wie alps_sky.gdshader, aber als Geometrie mit Parallaxe; eigener leichter Dunst statt Szenennebel (fog_disabled).
// Zeichenreihenfolge: vor allen anderen durchsichtigen Dingen (render_priority), damit Rauch davor nicht verdeckt wird.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

uniform sampler2D panorama : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool south_enabled = true;
// Südstreifen (panorama_south.png) statt Alpenband; Parameter ohne Zoom (natürlicher Maßstab, 120°)
uniform bool far_south_enabled = false;
uniform sampler2D far_south : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 far_south_p = vec4(0.7667,2.439,0.4775,0.5);
uniform sampler2D far_north : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D far_east : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D far_west : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 far_north_p = vec4(0.72,5.954,0.6141,0.6109);
uniform vec4 far_east_p = vec4(0.70,6.115,0.5208,0.5272);
uniform vec4 far_west_p = vec4(0.70,5.801,0.6391,0.5867);
uniform vec3 south_direction = vec3(0.817,0.0,0.576);
uniform float panorama_repeats = 3.0;
uniform vec3 ring_center = vec3(0.0,1.4,0.0);   // Kartenmitte auf Augenhöhe: Bildhorizont liegt dort
uniform float daylight = 0.0;
uniform float overcast = 0.0;     // Wetter: 0 = unverändert, 1 = geschlossene Wolkendecke
uniform float rain_haze = 0.0;    // Wetter: Regendunst über der Fernkulisse
uniform float night = 0.0;
uniform vec3 sun_direction = vec3(-0.576,-0.035,0.817);
uniform float zoom = 1.6;        // Bildwinkel-Vergrößerung Nord/Ost/West (waagrecht = senkrecht, unverzerrt)
uniform float alps_zoom = 2.2;   // dito Alpenband Süd (im natürlichen Maßstab nur ≈ 3° hoch)
uniform float haze = 0.08;          // leichter eigener Dunst (Tag); Dämmerung/Nacht etwas mehr
uniform float sharpen = 0.22;       // leichtes Nachschärfen gegen die nächstgröbere Mipstufe
uniform float top_fade = 0.13;      // Oberkante [rad Höhenwinkel], darüber weich ausgeblendet
uniform float fill_below = 0.022;  // mittlere Höhe [rad] der fernen Waldkante (Anschluss an Boden/Wald)

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

float wrap_angle(float a) {
	return a-6.28318530718*floor((a+3.14159265359)/6.28318530718);
}
float sector_weight(float d) {
	return 1.0-smoothstep(0.62,0.98,abs(d));
}
float edge_fade(float u) {
	return smoothstep(0.0,0.10,u)*(1.0-smoothstep(0.90,1.0,u));
}
vec3 sharp_sample(sampler2D tex, vec2 uv, out float a) {
	vec4 s = texture(tex,uv);
	vec3 soft = texture(tex,uv,1.5).rgb;
	a = s.a;
	return max(s.rgb+(s.rgb-soft)*sharpen,vec3(0.0));
}
vec3 tint(vec3 source, vec3 horizon) {
	vec3 dusk = mix(source*vec3(0.46,0.48,0.60),horizon,haze*2.2);
	vec3 day = mix(source*vec3(0.97,0.98,1.0),horizon,haze);
	vec3 col = mix(dusk,day,daylight);
	return mix(col,source*vec3(0.03,0.035,0.055)+horizon*0.30,night);
}
float skyline(float u) {
	if (u<0.1) return mix(0.48,0.55,u/0.1);
	if (u<0.2) return mix(0.55,0.53,(u-0.1)/0.1);
	if (u<0.3) return mix(0.53,0.51,(u-0.2)/0.1);
	if (u<0.4) return mix(0.51,0.54,(u-0.3)/0.1);
	if (u<0.5) return mix(0.54,0.59,(u-0.4)/0.1);
	if (u<0.6) return mix(0.59,0.61,(u-0.5)/0.1);
	if (u<0.7) return mix(0.61,0.53,(u-0.6)/0.1);
	if (u<0.8) return mix(0.53,0.55,(u-0.7)/0.1);
	return mix(0.55,0.68,(u-0.8)/0.2);
}
vec4 mountain_band(float u, float elevation, vec3 horizon) {
	float v = 0.77-elevation*5.4;
	float a;
	vec3 source = sharp_sample(panorama,vec2(u,clamp(v,0.0,1.0)),a);
	float alpha = smoothstep(skyline(u),skyline(u)+0.035,v);
	alpha *= smoothstep(-0.025,0.025,source.b-source.g);
	alpha *= smoothstep(0.88,0.78,v)*smoothstep(0.46,0.50,v);
	alpha *= step(0.0,u)*step(u,1.0);
	return vec4(tint(source,horizon),alpha);
}
vec4 far_band(sampler2D tex, vec4 p, float d, float elevation, vec3 horizon) {
	float u = p.w-d*p.z;
	float v = p.x-elevation*p.y;
	// unter dem Bild (v > 1) die unterste Zeile fortsetzen: Land bis zum Boden, kein Spalt
	float inside = step(0.0,u)*step(u,1.0)*step(0.0,v);
	float a;
	vec3 c = sharp_sample(tex,clamp(vec2(u,v),vec2(0.0),vec2(1.0,0.999)),a);
	float soft = smoothstep(0.0,0.02,u)*(1.0-smoothstep(0.98,1.0,u));
	return vec4(tint(c,horizon),a*inside*soft);
}

void fragment() {
	vec3 d3 = world_pos-ring_center;
	float elevation = atan(d3.y,length(d3.xz));
	vec3 ray = normalize(d3);
	vec3 east = vec3(south_direction.z,0.0,-south_direction.x);
	// Dunstfarbe = Horizontfarbe des Himmels (alps_sky.gdshader)
	vec2 sun_flat = normalize(sun_direction.xz+vec2(0.00001));
	float glow = pow(max(dot(normalize(ray.xz+vec2(0.00001)),sun_flat),0.0),3.0);
	float low_sun = (1.0-smoothstep(0.05,0.35,sun_direction.y))*smoothstep(-0.30,-0.06,sun_direction.y);
	vec3 horizon_dusk = mix(vec3(0.30,0.34,0.47),vec3(0.65,0.36,0.27),glow);
	vec3 horizon_day = mix(vec3(0.66,0.74,0.84),vec3(0.88,0.78,0.62),glow*low_sun);
	vec3 horizon = mix(mix(horizon_dusk,horizon_day,daylight),vec3(0.040,0.050,0.085),night);
	float azimuth = atan(dot(ray,east),dot(ray,south_direction));
	float d_s = azimuth;
	float d_e = wrap_angle(azimuth-1.5707963);
	float d_n = wrap_angle(azimuth-3.1415927);
	float d_w = wrap_angle(azimuth+1.5707963);
	float us = 0.5+d_s/alps_zoom*panorama_repeats/6.28318530718;
	if (far_south_enabled) us = far_south_p.w-d_s*far_south_p.z;
	float w_s = (south_enabled || far_south_enabled) ? sector_weight(d_s)*edge_fade(us) : 0.0;
	float w_e = sector_weight(d_e)*edge_fade(far_east_p.w-d_e/zoom*far_east_p.z);
	float w_n = sector_weight(d_n)*edge_fade(far_north_p.w-d_n/zoom*far_north_p.z);
	float w_w = sector_weight(d_w)*edge_fade(far_west_p.w-d_w/zoom*far_west_p.z);
	w_s *= w_s; w_e *= w_e; w_n *= w_n; w_w *= w_w;
	vec4 s = far_south_enabled ? far_band(far_south,far_south_p,d_s,elevation,horizon)
			: mountain_band(us,elevation/alps_zoom,horizon);
	// Alpenband zählt nur, wo es Berge zeigt: unter/neben der Bergkontur übernimmt das Land der Nachbarstreifen voll
	// (sonst heller Dunstkeil an den Nähten Süd/Ost und Süd/West)
	w_s *= smoothstep(0.0,0.5,s.a);
	float wsum = max(w_s+w_e+w_n+w_w,0.05);   // Untergrenze: Streifen laufen am Sektorende weich aus
	vec4 e = far_band(far_east,far_east_p,d_e/zoom,elevation/zoom,horizon);
	vec4 n = far_band(far_north,far_north_p,d_n/zoom,elevation/zoom,horizon);
	vec4 w = far_band(far_west,far_west_p,d_w/zoom,elevation/zoom,horizon);
	float a_s = s.a*w_s/wsum;
	float a_e = e.a*w_e/wsum;
	float a_n = n.a*w_n/wsum;
	float a_w = w.a*w_w/wsum;
	float coverage = a_s+a_e+a_n+a_w;
	vec3 col = (s.rgb*a_s+e.rgb*a_e+n.rgb*a_n+w.rgb*a_w)/max(coverage,0.00001);
	float c_s = s.a*smoothstep(0.0,0.25,w_s/wsum);
	float c_e = e.a*smoothstep(0.0,0.25,w_e/wsum);
	float c_n = n.a*smoothstep(0.0,0.25,w_n/wsum);
	float c_w = w.a*smoothstep(0.0,0.25,w_w/wsum);
	coverage = clamp(max(coverage,max(max(c_s,c_e),max(c_n,c_w))),0.0,1.0);
	// Sektorende ohne Nachbarbild (Süd neben den Alpen): Streifen weich auslaufen lassen statt grauer Kante
	coverage *= smoothstep(0.0,0.3,w_s+w_e+w_n+w_w);
	// Unterkante: dunkler Waldsaum, wo kein Bild deckt (Süden unter den Alpen) → nahtlos zum Außenboden
	// unregelmäßige ferne Waldkante (≈ 0,4–1,3°): schließt die Lücke unter dem Alpenband und an den Bildenden
	float tl = fill_below+0.0045*sin(azimuth*23.0+1.3)+0.003*sin(azimuth*57.0)+0.002*sin(azimuth*131.0+0.7);
	tl = max(tl,0.004);
	float fill = 1.0-smoothstep(tl-0.0012,tl,elevation);
	vec3 forest = tint(vec3(0.16,0.20,0.13),horizon);
	col = mix(forest,col,coverage);
	coverage = max(coverage,fill);
	coverage *= 1.0-smoothstep(top_fade*0.92,top_fade,elevation);
	// Wetter (weather.gd): Bewölkung entsättigt und dunkelt die Fernkulisse ab, Regendunst hebt sie an
	float lum = dot(col,vec3(0.299,0.587,0.114));
	col = mix(col,mix(vec3(lum*0.78),vec3(0.42,0.44,0.46)*max(daylight,0.15),rain_haze),clamp(overcast*0.6+rain_haze*0.4,0.0,1.0));
	ALBEDO = col;
	ALPHA = coverage;
}
