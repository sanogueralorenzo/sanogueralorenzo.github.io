float wall_runoff(vec2 p) {
    vec2 trickle = p + vec2((noise(p * vec2(2.2, 0.62)) - 0.5) * 0.11, 0.0);
    float trails = noise(trickle * vec2(8.1, 0.49)) * 0.63 + noise(p * vec2(2.3, 0.77) + 15.0) * 0.37;
    return smoothstep(0.49, 0.79, trails) * smoothstep(0.35, 0.72, noise(p * 0.57));
}

float plaster_texture(vec2 p) {
    return noise(p * 3.6) * 0.34 + noise(p * 37.0) * 0.41 + noise(p * 117.0) * 0.25;
}
