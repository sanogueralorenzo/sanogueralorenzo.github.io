shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec2 seed_offset = vec2(0.0);
uniform vec2 world_origin = vec2(0.0);
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float surface_texture_scale = 0.08;
uniform vec3 shadow_sand : source_color = vec3(0.15, 0.09, 0.05);
uniform vec3 pale_sand : source_color = vec3(0.45, 0.32, 0.2);
uniform vec3 sunlit_sand : source_color = vec3(0.58, 0.4, 0.23);
uniform vec3 sandstone : source_color = vec3(0.28, 0.19, 0.13);
uniform vec3 shadow_grass : source_color = vec3(0.07, 0.11, 0.055);
uniform vec3 grass : source_color = vec3(0.19, 0.24, 0.12);
uniform vec3 sunlit_grass : source_color = vec3(0.28, 0.33, 0.16);

varying vec3 world_position;
varying vec3 world_normal;
varying float grass_weight;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	return mix(
		mix(hash(cell), hash(cell + vec2(1.0, 0.0)), local.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), local.x),
		local.y
	);
}

vec3 material_response(vec3 texel, float reference_luma, float chroma_strength, float value_strength) {
	float luma = dot(texel, vec3(0.299, 0.587, 0.114));
	vec3 restrained_texel = mix(vec3(luma), texel, chroma_strength);
	vec3 normalized_texel = clamp(
		restrained_texel / max(reference_luma, 0.025),
		vec3(0.72),
		vec3(1.3)
	);
	return mix(vec3(1.0), normalized_texel, value_strength);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	grass_weight = COLOR.r;
}

void fragment() {
	vec2 logical_position = world_position.xz + world_origin;
	vec2 p = logical_position + seed_offset;
	vec2 surface_uv = p * surface_texture_scale;
	mat2 detail_rotation = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	vec2 detail_uv = detail_rotation * surface_uv * 0.57 + vec2(13.1, -7.4);
	float view_distance = length(CAMERA_POSITION_WORLD - world_position);
	float texel_footprint = max(length(fwidth(surface_uv)), length(fwidth(detail_uv)));
	float micro_visibility = (
		(1.0 - smoothstep(80.0, 360.0, view_distance))
		* (1.0 - smoothstep(0.055, 0.18, texel_footprint))
	);
	float primary_weight = mix(0.56, 0.76, micro_visibility);
	vec3 sand_texel = mix(
		texture(sand_albedo, detail_uv).rgb,
		texture(sand_albedo, surface_uv).rgb,
		primary_weight
	);
	vec3 grass_texel = mix(
		texture(grass_albedo, detail_uv).rgb,
		texture(grass_albedo, surface_uv).rgb,
		primary_weight
	);
	float broad = noise(p * 0.0035);
	float middle = noise(p * 0.012 + vec2(-53.0, 29.0));
	float wind_phase = dot(logical_position, normalize(vec2(0.95, 0.31))) * 0.22 + middle * 2.2;
	float wind_visibility = (
		(1.0 - smoothstep(0.35, 1.25, fwidth(wind_phase)))
		* (0.38 + micro_visibility * 0.62)
	);
	float wind_lines = 0.5 + sin(wind_phase) * 0.5 * wind_visibility;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float stone = smoothstep(0.34, 0.67, slope + (broad - 0.5) * 0.16);
	float wind_crest = smoothstep(0.78, 0.97, wind_lines) * (1.0 - smoothstep(0.22, 0.52, slope));
	vec3 sand_palette = mix(pale_sand, sunlit_sand, 0.26 + broad * 0.48 + wind_lines * 0.08);
	vec3 sand_surface = sand_palette * material_response(sand_texel, 0.22, 0.12, 0.52);
	sand_surface *= mix(0.96, 1.055, wind_crest);
	vec3 grass_palette = mix(grass, sunlit_grass, 0.3 + broad * 0.34 + middle * 0.18);
	vec3 grass_surface = grass_palette * material_response(grass_texel, 0.075, 0.08, 0.5);
	grass_surface *= mix(vec3(0.93, 0.96, 0.91), vec3(1.02, 1.0, 0.9), middle);
	float transition_mottle = (middle - 0.5) * 0.1 * (1.0 - abs(grass_weight * 2.0 - 1.0));
	float biome_blend = smoothstep(0.08, 0.92, grass_weight + transition_mottle);
	vec3 rideable_surface = mix(sand_surface, grass_surface, biome_blend);
	vec3 rock = mix(shadow_sand * 0.62, sandstone, broad);
	ALBEDO = mix(rideable_surface, rock, stone);
	float surface_luma = mix(dot(sand_texel, vec3(0.299, 0.587, 0.114)), dot(grass_texel, vec3(0.299, 0.587, 0.114)), biome_blend);
	ROUGHNESS = mix(mix(0.88 + surface_luma * 0.08 - wind_crest * 0.07, 0.96, biome_blend), 0.84, stone);
	SPECULAR = mix(0.18, 0.08, stone);
	// Real scene lights own slope illumination instead of a frozen albedo light cue.
}
