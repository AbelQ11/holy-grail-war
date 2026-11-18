shader_type canvas_item;
render_mode unshaded, blend_mix;

// Full-viewport Reality Marble treatment. The radial shockwave expands from the
// caster, then leaves an animated sky/ground tint and rotating rune spokes.
uniform vec2 view_origin = vec2(-720.0, -400.0);
uniform vec2 view_size = vec2(1440.0, 800.0);
uniform vec2 marble_center = vec2(0.0, 0.0);
uniform float shock_progress : hint_range(0.0, 1.0) = 1.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.9, 0.22, 0.52, 1.0);
uniform float arena_half_extent = 720.0;

void fragment() {
	vec2 world = view_origin + SCREEN_UV * view_size;
	vec2 local = world - marble_center;
	float d = length(local);
	float angle = atan(local.y, local.x);

	float shock_radius = mix(8.0, arena_half_extent * 1.85, shock_progress);
	float ring = 1.0 - smoothstep(0.0, 86.0, abs(d - shock_radius));
	float wash = smoothstep(shock_radius, shock_radius - 260.0, d);

	// Sky gradient: brighter near the horizon, deeper at the top of the field.
	float vertical = clamp((world.y + arena_half_extent) / (arena_half_extent * 2.0), 0.0, 1.0);
	vec3 sky = mix(tint.rgb * 1.15, tint.rgb * 0.32, 1.0 - vertical);
	vec3 ground = mix(tint.rgb * 0.28, tint.rgb * 0.62, vertical);

	// Slow rotating spokes and drifting grain keep the domain alive.
	float spokes = smoothstep(0.9, 1.0, abs(sin(angle * 9.0 + TIME * 0.45)));
	float grain = 0.5 + 0.5 * sin(world.x * 0.05 + TIME * 0.9) * sin(world.y * 0.043 - TIME * 0.7);
	float pulse = 0.5 + 0.5 * sin(TIME * 1.6 + d * 0.01);

	vec3 colour = mix(ground, sky, 0.35 + 0.25 * grain);
	colour += tint.rgb * (0.10 + 0.06 * pulse) * spokes;
	colour += tint.rgb * ring * 0.85;

	float alpha = intensity * (0.075 + wash * 0.085 + spokes * 0.02 + pulse * 0.015);
	alpha += ring * intensity * 0.55;
	COLOR = vec4(colour, clamp(alpha, 0.0, 0.62));
}
