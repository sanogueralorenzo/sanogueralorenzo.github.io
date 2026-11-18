shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler3D cloud_noise : repeat_enable, filter_linear;
uniform vec3 sun_direction = vec3(-0.568, 0.723, -0.393);

float density(vec3 p) {
    float body = texture(cloud_noise, p * vec3(0.072, 0.095, 0.072)).r;
    float wisps = texture(cloud_noise, p * 0.39 + vec3(0.31, 0.15, 0.82)).r;
    float height = clamp((p.y - 1.0) / 1.8, 0.0, 1.0);
    float envelope = smoothstep(0.0, 0.14, height) * (1.0 - smoothstep(0.42, 1.0, height));
    float opening = exp(-dot(p.xz, p.xz) * 0.055);
    return max(0.0, (body - 0.558) * 2.75 + (wisps - 0.5) * 0.58 - 0.25 * opening - (1.0 - envelope) * 0.56);
}

vec3 daylight(vec3 ray) {
    float elevation = max(ray.y, 0.0);
    float air = exp(-elevation * 4.7);
    float alignment = max(dot(ray, sun_direction), 0.0);
    vec3 clear_sky = mix(vec3(0.039, 0.118, 0.29), vec3(0.32, 0.47, 0.61), air);
    clear_sky += vec3(0.45, 0.33, 0.18) * pow(alignment, 12.0);
    clear_sky += vec3(7.0, 5.8, 4.3) * smoothstep(0.99997, 0.999995, alignment);
    if (ray.y <= 0.012) { return clear_sky; }
    float rise = sqrt(elevation * elevation + 0.004);
    float travel = 1.0 / rise;
    float step_length = min(1.8 / rise, 24.0) / 80.0;
    float offset = fract(52.9829189 * fract(dot(ray.xz, vec2(721.23, 419.45))));
    float transmission = 1.0;
    vec3 scattered = vec3(0.0);
    for (int i = 0; i < 80; i++) {
        vec3 p = vec3(ray.x, rise, ray.z) * (travel + (float(i) + offset) * step_length);
        float cloud = density(p);
        if (cloud > 0.001) {
            float overburden = density(p + sun_direction * 0.23) * 0.48
                + density(p + sun_direction * 0.70) * 0.78
                + density(p + sun_direction * 1.55) * 0.85;
            float direct = exp(-overburden * 4.8);
            vec3 irradiance = vec3(0.19, 0.25, 0.34) + direct * vec3(0.90, 0.86, 0.76);
            float opacity = 1.0 - exp(-cloud * step_length * 7.0);
            scattered += transmission * opacity * irradiance;
            transmission *= 1.0 - opacity;
            if (transmission < 0.012) { break; }
        }
    }
    vec3 result = scattered + transmission * clear_sky;
    return mix(clear_sky, result, smoothstep(0.012, 0.095, elevation));
}

void fragment() {
    float longitude = UV.x * TAU;
    float latitude = UV.y * PI;
    vec3 ray = vec3(sin(longitude) * sin(latitude), cos(latitude), -cos(longitude) * sin(latitude));
    COLOR = vec4(daylight(ray), 1.0);
}
