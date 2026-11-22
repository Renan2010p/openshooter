// SPDX-License-Identifier: GPL-3.0-or-later
// RL PROJECTS intro — reveals the wordmark only right of `clip_x` (local px),
// with a soft edge, so it seems to slide out from behind the galaxy.
shader_type canvas_item;

uniform float clip_x = 0.0;
uniform float feather = 1.0;

varying float local_x;

void vertex() {
	local_x = VERTEX.x;
}

void fragment() {
	float k = clamp((local_x - clip_x) / max(feather, 0.001), 0.0, 1.0);
	COLOR.a *= k * k * (3.0 - 2.0 * k);
}
