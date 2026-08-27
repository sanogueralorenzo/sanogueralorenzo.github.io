shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec3 world_position;
varying vec3 world_normal;

float random_value(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	float a = random_value(cell);
	float b = random_value(cell + vec2(1.0, 0.0));
	float c = random_value(cell + vec2(0.0, 1.0));
	float d = random_value(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

float fbm(vec2 point) {
	float value = 0.0;
	float amplitude = 0.5;
	mat2 rotation = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int octave = 0; octave < 5; octave++) {
		value += value_noise(point) * amplitude;
		point = rotation * point * 2.03 + vec2(19.1, 7.7);
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	float broad_pattern = fbm(world_position.xz * 0.0055);
	float fine_pattern = fbm(world_position.xz * 0.018 + vec2(31.0, -17.0));
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float rock_mask = smoothstep(0.20, 0.72, slope + (fine_pattern - 0.5) * 0.27);
	float highland = smoothstep(65.0, 180.0, world_position.y);

	vec3 emerald = vec3(0.008, 0.22, 0.13);
	vec3 lime = vec3(0.32, 0.72, 0.055);
	vec3 grass = mix(emerald, lime, smoothstep(0.2, 0.88, broad_pattern));
	float turquoise_patch = smoothstep(0.58, 0.83, fine_pattern) * (1.0 - rock_mask);
	grass = mix(grass, vec3(0.015, 0.48, 0.5), turquoise_patch * 0.5);
	float warm_patch = smoothstep(0.72, 0.92, broad_pattern + fine_pattern * 0.18);
	grass = mix(grass, vec3(0.78, 0.43, 0.045), warm_patch * 0.32);
	vec3 violet = vec3(0.24, 0.045, 0.42);
	vec3 coral = vec3(0.95, 0.16, 0.34);
	vec3 rock = mix(violet, coral, smoothstep(0.18, 0.84, fine_pattern));
	vec3 sunlit = vec3(0.95, 0.62, 0.12);
	rock = mix(rock, sunlit, highland * broad_pattern * 0.46);

	ALBEDO = mix(grass, rock, rock_mask);
	ROUGHNESS = mix(0.92, 0.68, rock_mask);
	SPECULAR = 0.18;
}
