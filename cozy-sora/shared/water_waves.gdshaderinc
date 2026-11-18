vec2 wave_slope(vec2 p, vec2 direction, float frequency, float steepness, float time) {
    float phase = dot(p, direction) * frequency + time;
    float footprint = fwidth(phase);
    float resolved = 1.0 - smoothstep(0.45, 2.8, footprint);
    return direction * steepness * cos(phase + 0.38 * sin(phase)) * resolved;
}

vec3 water_normal(vec2 p, float time, float strength) {
    float bend = sin(dot(p, vec2(0.17, 0.23)) + time * 0.27);
    vec2 slope = wave_slope(p, vec2(0.93, 0.37), 1.24, 0.085, time * 1.1 + bend);
    slope += wave_slope(p, vec2(-0.42, 0.91), 2.65, 0.051, time * 1.7);
    slope += wave_slope(p, vec2(0.83, 0.56), 7.8, 0.052, time * 2.1 + bend * 2.2);
    slope += wave_slope(p, vec2(0.99, -0.14), 19.4, 0.034, time * 3.2 + bend);
    return normalize(vec3(-slope.x * strength, 1.0, -slope.y * strength));
}
