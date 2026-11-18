shader_type canvas_item;
render_mode unshaded, blend_mix;

// Screen-space mist driven in world units so the shroud stays fixed to the map
// while the camera pans and zooms.
uniform vec2 view_origin = vec2(-720.0, -400.0);
uniform vec2 view_size = vec2(1440.0, 800.0);
uniform vec2 light_positions[24];
uniform float light_radii[24];
uniform int light_count : hint_range(0, 24) = 0;
uniform vec2 stealth_positions[8];
uniform int stealth_count : hint_range(0, 8) = 0;
uniform float fog_strength : hint_range(0.0, 1.0) = 0.88;
uniform float mist_speed = 0.015;
uniform vec4 mist_color : source_color = vec4(0.012, 0.017, 0.042, 1.0);
uniform vec4 shimmer_color : source_color = vec4(0.36, 0.5, 0.72, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec2 world = view_origin + SCREEN_UV * view_size;

	// Visibility field: soft holes punched by every friendly vision source.
	float visibility = 0.0;
	for (int i = 0; i < 24; i++) {
		if (i >= light_count) {
			break;
		}
		float radius = max(light_radii[i], 1.0);
		float d = distance(world, light_positions[i]);
		float reveal = 1.0 - smoothstep(radius * 0.55, radius, d);
		visibility = max(visibility, reveal);
	}

	// Two octaves of slow-drifting mist.
	vec2 drift = vec2(TIME * mist_speed, TIME * mist_speed * 0.6);
	float mist = value_noise(world * 0.011 + drift) * 0.6;
	mist += value_noise(world * 0.041 - drift * 2.2) * 0.4;

	float fog = 1.0 - visibility;
	fog = clamp(fog * fog_strength + mist * 0.14 * fog, 0.0, 0.96);

	vec3 colour = mist_color.rgb + vec3(0.018, 0.024, 0.052) * mist;

	// Presence Concealment: a translucent, breathing shimmer halo around a
	// stealthed Servant that its owner can still track.
	float shimmer = 0.0;
	for (int s = 0; s < 8; s++) {
		if (s >= stealth_count) {
			break;
		}
		float sd = distance(world, stealth_positions[s]);
		if (sd < 52.0) {
			float band = smoothstep(52.0, 20.0, sd);
			float breathe = 0.55 + 0.45 * sin(world.x * 0.08 + world.y * 0.06 + TIME * 2.4);
			shimmer += band * (0.10 + 0.13 * breathe);
		}
	}
	colour += shimmer_color.rgb * shimmer;

	float alpha = clamp(max(fog, shimmer * 0.55), 0.0, 0.97);
	COLOR = vec4(colour, alpha);
}
