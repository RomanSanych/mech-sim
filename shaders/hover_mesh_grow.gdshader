shader_type spatial;
// Ободок циан на исходном меше (material_overlay).
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back, specular_disabled, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(0.0, 0.745, 0.953, 1.0);
uniform float fill : hint_range(0.0, 0.5, 0.01) = 0.18;
uniform float rim_pow : hint_range(0.5, 6.0, 0.1) = 2.2;
uniform float rim_strength : hint_range(0.0, 3.0, 0.05) = 0.95;

void fragment() {
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - ndv, rim_pow);
	float a = fill + rim * rim_strength;
	ALBEDO = glow_color.rgb;
	EMISSION = glow_color.rgb * (0.4 + rim * 0.7);
	ALPHA = clamp(a, 0.0, 0.92);
}
