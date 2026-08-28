shader_type sky;
render_mode use_half_res_pass;

uniform vec3 sky_top_color : source_color = vec3(0.025, 0.18, 0.34);
uniform vec3 sky_horizon_color : source_color = vec3(0.24, 0.58, 0.72);
uniform vec3 ground_bottom_color : source_color = vec3(0.07, 0.13, 0.18);
uniform vec3 cloud_shadow_color : source_color = vec3(0.50, 0.61, 0.65);
uniform vec3 cloud_light_color : source_color = vec3(0.96, 0.91, 0.80);
uniform float cloud_coverage : hint_range(0.35, 0.75) = 0.50;
uniform float cloud_opacity : hint_range(0.0, 0.5) = 0.34;
uniform float sky_energy = 1.08;

float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	float lower = mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), local.x);
	float upper = mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), local.x);
	return mix(lower, upper, local.y);
}

float fbm(vec2 point) {
	float value = 0.0;
	float amplitude = 0.57;
	for (int octave = 0; octave < 3; octave++) {
		value += value_noise(point) * amplitude;
		point = point * 2.07 + vec2(1.7, -2.3);
		amplitude *= 0.46;
	}
	return value;
}

vec3 generate_atmosphere(vec3 direction) {
	float up = clamp(direction.y, 0.0, 1.0);
	float sky_blend = pow(up, 0.62);
	vec3 sky_color = mix(sky_horizon_color, sky_top_color, sky_blend);
	float horizon_haze = exp(-abs(direction.y) * 8.0);
	sky_color = mix(sky_color, sky_horizon_color * 1.06, horizon_haze * 0.2);

	if (LIGHT0_ENABLED && direction.y > 0.0) {
		float sun_angle = acos(clamp(dot(direction, LIGHT0_DIRECTION), -1.0, 1.0));
		float sun_glow = 1.0 - smoothstep(0.018, 0.115, sun_angle);
		float sun_disk = 1.0 - smoothstep(0.006, 0.016, sun_angle);
		sky_color += LIGHT0_COLOR * LIGHT0_ENERGY * (sun_glow * 0.34 + sun_disk * 1.65);
	}

	float below_horizon = clamp(-direction.y, 0.0, 1.0);
	vec3 ground_color = mix(sky_horizon_color, ground_bottom_color, pow(below_horizon, 0.54));
	return mix(ground_color, sky_color, step(0.0, direction.y)) * sky_energy;
}

vec4 generate_clouds(vec3 direction) {
	float elevation = max(direction.y, 0.12);
	vec2 plane = direction.xz / elevation;
	vec2 cloud_point = vec2(
		plane.x * 0.48 + plane.y * 0.16,
		plane.y * 1.08 - plane.x * 0.07
	) + vec2(17.4, -3.1);
	float cloud_body = fbm(cloud_point);
	float cloud_filament = value_noise(cloud_point * vec2(3.6, 1.7) + vec2(-4.2, 7.1));
	float cloud_field = cloud_body * 0.84 + cloud_filament * 0.16;
	float cloud_mask = smoothstep(cloud_coverage, cloud_coverage + 0.13, cloud_field);
	float cloud_altitude = smoothstep(0.06, 0.24, direction.y) * (1.0 - smoothstep(0.88, 0.99, direction.y));
	float cloud_alpha = cloud_mask * cloud_altitude * cloud_opacity;
	vec3 cloud_color = mix(cloud_shadow_color, cloud_light_color, smoothstep(0.48, 0.78, cloud_body));
	return vec4(cloud_color, cloud_alpha);
}

void sky() {
	if (AT_HALF_RES_PASS) {
		vec4 clouds = generate_clouds(EYEDIR);
		COLOR = clouds.rgb;
		ALPHA = clouds.a;
	} else if (AT_CUBEMAP_PASS) {
		vec3 atmosphere = generate_atmosphere(EYEDIR);
		vec4 clouds = generate_clouds(EYEDIR);
		COLOR = mix(atmosphere, clouds.rgb, clouds.a);
	} else {
		COLOR = mix(generate_atmosphere(EYEDIR), HALF_RES_COLOR.rgb, HALF_RES_COLOR.a);
	}
}
