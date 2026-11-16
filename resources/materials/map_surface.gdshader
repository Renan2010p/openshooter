shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Per-vertex material data packed by the native mesher:
//   COLOR.rgb = albedo (sRGB), COLOR.a = roughness
//   UV2.x     = metallic,      UV2.y     = emission strength
void fragment() {
	// Vertex colors already arrive in linear space, so no sRGB conversion here.
	ALBEDO = COLOR.rgb;
	METALLIC = clamp(UV2.x, 0.0, 1.0);
	ROUGHNESS = clamp(COLOR.a, 0.04, 1.0);
	EMISSION = COLOR.rgb * max(UV2.y, 0.0);
}
