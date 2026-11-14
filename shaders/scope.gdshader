shader_type canvas_item;
// Visão da luneta do Fuzil: preto fora do círculo e uma cruz fina no meio.

uniform float aspect = 1.777;
uniform float radius = 0.42;
uniform float line_width = 0.0015;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float r = length(p);
	float ring = smoothstep(radius, radius + 0.005, r);
	float cross_line = (abs(p.x) < line_width || abs(p.y) < line_width) ? 1.0 : 0.0;
	COLOR = vec4(0.0, 0.0, 0.0, max(ring, cross_line * (1.0 - ring)));
}
