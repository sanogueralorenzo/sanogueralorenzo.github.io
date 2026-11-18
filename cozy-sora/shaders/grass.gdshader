shader_type spatial;
render_mode cull_disabled, world_vertex_coords, specular_disabled;

uniform vec3 grass_base = vec3(0.16, 0.26, 0.12);
uniform vec3 grass_mid = vec3(0.31, 0.39, 0.17);
uniform vec3 grass_tip = vec3(0.48, 0.49, 0.25);
uniform float band_lift = 0.0;
global uniform vec3 cat_position;
varying vec3 blade_normal;
varying vec2 blade_pigment;

void vertex() {
    vec3 origin = MODEL_MATRIX[3].xyz;
    float clump_height = length(MODEL_MATRIX[1].xyz);
    float weight = UV.y * UV.y * clump_height;
    float gust = sin(origin.x * 0.21 + origin.z * 0.16 + TIME * 1.7);
    float flutter = sin(TIME * 4.4 + dot(origin.xz, vec2(1.7, 2.6)) + COLOR.g * 6.0);
    VERTEX.xz += vec2(0.17 * gust + 0.036 * flutter, 0.082 * gust - 0.024 * flutter) * weight;
    vec2 away = VERTEX.xz - cat_position.xz;
    float separation = length(away);
    float near_cat = 1.0 - smoothstep(0.55, 1.55, abs(origin.y - cat_position.y));
    float push = (1.0 - smoothstep(0.14, 1.28, separation)) * weight * near_cat;
    VERTEX.xz += push * away / max(separation, 0.08) * 0.63;
    VERTEX.y -= push * 0.61;
    blade_normal = mat3(VIEW_MATRIX) * NORMAL;
    float soil = sin(origin.x * 0.47 + sin(origin.z * 0.83))
        * cos(origin.z * 0.53 + sin(origin.x * 0.72));
    blade_pigment = vec2(COLOR.r * (0.91 + soil * 0.13), clamp(COLOR.g + 0.24 * soil, 0.0, 0.94));
}

void fragment() {
    if (length(VERTEX) < 0.45) { discard; }
    float center = 1.0 - smoothstep(0.025, 0.095 + fwidth(UV.x), abs(UV.x - 0.5));
    float edge = smoothstep(0.28, 0.50, abs(UV.x - 0.5));
    vec3 summer = mix(mix(grass_base, grass_mid, smoothstep(0.0, 0.72, UV.y)),
        grass_tip, smoothstep(0.62, 1.0, UV.y) * 0.61);
    vec3 dried = mix(vec3(0.29, 0.30, 0.16), vec3(0.62, 0.54, 0.32), UV.y);
    vec3 pigment = mix(summer, dried, blade_pigment.y * smoothstep(0.37, 0.95, UV.y));
    ALBEDO = pow(pigment, vec3(2.2)) * blade_pigment.x * (0.71 + 0.29 * UV.y + 0.16 * center - 0.12 * edge);
    NORMAL = normalize(blade_normal);
    ROUGHNESS = 0.72;
    AO = 0.57 + 0.43 * smoothstep(0.0, 0.6, UV.y);
}

void light() {
    float broadside = abs(dot(NORMAL, LIGHT));
    float backlit = pow(max(dot(VIEW, -LIGHT), 0.0), 3.0) * (0.35 + 0.65 * UV.y);
    vec3 transmitted = (0.25 + broadside * 0.52 + band_lift) * vec3(1.0)
        + backlit * vec3(0.42, 0.39, 0.14);
    DIFFUSE_LIGHT += transmitted * ATTENUATION * LIGHT_COLOR / PI;
}
