shader_type canvas_item;
render_mode unshaded, blend_mix;

// Applied directly to a stealthed Servant. Refracts the screen through a
// breathing cloak and washes the silhouette with a cold translucent shimmer.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float distortion = 0.0035;
uniform float cloak_opacity : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec2 uv = SCREEN_UV;
	float wave_x = sin(uv.y * 84.0 + TIME * 4.1) * distortion;
	float wave_y = sin(uv.x * 66.0 - TIME * 3.3) * distortion * 0.7;
	vec4 behind = texture(screen_texture, uv + vec2(wave_x, wave_y));

	float breathe = 0.5 + 0.5 * sin(TIME * 3.0 + uv.x * 34.0 + uv.y * 18.0);
	vec3 cloak = vec3(0.40, 0.54, 0.78) * (0.22 + breathe * 0.20);

	vec3 refracted = behind.rgb * 0.82 + cloak;
	vec3 mixed = mix(COLOR.rgb, refracted, cloak_opacity);
	float alpha = max(COLOR.a * 0.55, 0.34);
	COLOR = vec4(mixed, alpha);
}
