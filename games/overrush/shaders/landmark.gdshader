shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform float route_length = 1450.0;
uniform vec2 region_breaks = vec2(0.32, 0.66);

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
	float progress = clamp(-world_position.z / max(route_length, 1.0), 0.0, 1.0);
	float verdant_weight = 1.0 - smoothstep(region_breaks.x - 0.075, region_breaks.x + 0.075, progress);
	float prism_weight = smoothstep(region_breaks.y - 0.075, region_breaks.y + 0.075, progress);
	float ember_weight = max(0.0, 1.0 - verdant_weight - prism_weight);
	vec3 verdant = mix(vec3(0.11, 0.025, 0.34), vec3(0.92, 0.10, 0.46), band);
	vec3 ember = mix(vec3(0.30, 0.018, 0.12), vec3(1.0, 0.46, 0.07), band);
	vec3 prism = mix(vec3(0.035, 0.08, 0.42), vec3(0.13, 0.82, 0.87), band);
	vec3 color = verdant * verdant_weight + ember * ember_weight + prism * prism_weight;
	color = mix(color, vec3(1.0, 0.62, 0.13), facing * smoothstep(0.62, 0.94, band) * 0.38);
	ALBEDO = color;
	ROUGHNESS = 0.76;
	SPECULAR = 0.24;
}
