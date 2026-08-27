shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec3 world_position;
varying vec3 world_normal;

float stripes(vec3 point) {
	float wave = sin(point.y * 0.075 + sin(point.x * 0.045) * 2.2 + sin(point.z * 0.038) * 1.6);
	return wave * 0.5 + 0.5;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	float band = stripes(world_position);
	float facing = pow(1.0 - abs(dot(normalize(world_normal), vec3(0.0, 1.0, 0.0))), 1.4);
	vec3 indigo = vec3(0.12, 0.035, 0.34);
	vec3 rose = vec3(0.84, 0.09, 0.42);
	vec3 gold = vec3(0.98, 0.48, 0.08);
	vec3 color = mix(indigo, rose, smoothstep(0.18, 0.82, band));
	color = mix(color, gold, facing * smoothstep(0.62, 0.94, band) * 0.52);
	ALBEDO = color;
	ROUGHNESS = 0.76;
	SPECULAR = 0.24;
}
