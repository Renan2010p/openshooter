shader_type canvas_item;
// Directional darkening used to keep menus readable over the 3D background.

uniform vec4 color : source_color = vec4(0.012, 0.016, 0.022, 1.0);
uniform bool horizontal = true;
uniform bool invert = false;
uniform float start : hint_range(0.0, 1.0) = 0.0;
uniform float end : hint_range(0.0, 1.0) = 0.85;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.92;
uniform float curve : hint_range(0.5, 3.0) = 1.0;

void fragment() {
	float t = horizontal ? UV.x : UV.y;
	if (invert) {
		t = 1.0 - t;
	}
	float a = (1.0 - smoothstep(start, end, pow(t, curve))) * max_alpha;
	COLOR = vec4(color.rgb, a);
}
