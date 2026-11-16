shader_type canvas_item;
// Cinematic edge darkening used by menus and the in-match HUD.

uniform vec4 color : source_color = vec4(0.012, 0.016, 0.022, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.55;
uniform float softness : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec2 p = UV - vec2(0.5);
	p.x *= 0.92;
	float d = length(p);
	float a = smoothstep(0.32 - softness * 0.1, 0.78, d) * strength;
	COLOR = vec4(color.rgb, a);
}
