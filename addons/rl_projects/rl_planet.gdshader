// SPDX-License-Identifier: GPL-3.0-or-later
// RL PROJECTS intro — one lit planet (sphere shading, bands, atmosphere,
// rings in front of / behind the disc). Drawn on a ColorRect whose half-size
// is `ext` planet radii.
shader_type canvas_item;

uniform vec3 base_color = vec3(0.7);
uniform int kind = 0;            // 0 rock, 1 ocean, 2 gas, 3 ringed
uniform vec3 light_dir = vec3(1.0, 0.0, 0.0);
uniform float ext = 1.25;
uniform float radius_px = 10.0;
uniform float sys_flat = 0.3;
uniform float sys_tilt = -0.3;
uniform float time_s = 0.0;
uniform float seed = 0.0;
uniform float opacity = 1.0;

void over(vec3 rgb, float a, inout vec3 acc, inout float acc_a) {
	acc = rgb * a + acc * (1.0 - a);
	acc_a = a + acc_a * (1.0 - a);
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * ext;
	float d2 = dot(p, p);
	float cover = clamp((1.0 - sqrt(d2)) * radius_px, 0.0, 1.0);
	float nz = sqrt(max(1.0 - d2, 0.0));
	vec3 n = vec3(p, nz);
	float lam = clamp(dot(n, light_dir), 0.0, 1.0);
	float shade = 0.05 + 0.95 * pow(lam, 0.85);
	vec3 col = base_color;
	float c = cos(sys_tilt), s = sin(sys_tilt);
	if (kind >= 2) {
		float band = -p.x * s + p.y * c;
		col *= 1.0 + 0.10 * sin(band * 17.0 + seed) + 0.06 * sin(band * 41.0);
	}
	if (kind == 1) {
		col *= 1.0 + 0.35 * clamp(sin(p.x * 9.0 + time_s * 0.3) * sin(p.y * 13.0 + 1.7), 0.0, 1.0);
	}
	vec3 lit = col * shade;
	float facing = clamp(dot(p, light_dir.xy), 0.0, 1.0);
	lit += pow(clamp(1.0 - nz, 0.0, 1.0), 3.0) * facing * 0.9 * vec3(1.0, 0.9, 0.75);
	if (kind == 1) {
		lit += pow(clamp(1.0 - nz, 0.0, 1.0), 2.0) * lam * vec3(0.3, 0.5, 1.0) * 0.9;
	}
	lit = min(lit * 1.25, vec3(1.0));

	vec3 acc = vec3(0.0);
	float acc_a = 0.0;
	float ring = 0.0;
	float uy = 0.0;
	if (kind == 3) {
		float cc = cos(-sys_tilt), ss = sin(-sys_tilt);
		float ux = p.x * cc - p.y * ss;
		uy = (p.x * ss + p.y * cc) / sys_flat;
		float rho = length(vec2(ux, uy));
		ring = (rho > 1.45 && rho < 2.25) ? (0.55 + 0.25 * sin(rho * 23.0)) * 0.8 : 0.0;
	}
	vec3 ring_col = vec3(0.82, 0.76, 0.62) * 0.85;
	if (uy <= 0.0) over(ring_col, ring, acc, acc_a);
	over(lit, cover, acc, acc_a);
	if (uy > 0.0) over(ring_col, ring, acc, acc_a);
	COLOR = vec4(acc / max(acc_a, 1e-4), acc_a * opacity);
}
