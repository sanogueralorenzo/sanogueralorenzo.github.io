shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, depth_test_inverted;

void fragment() {
    float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
    float stripe = smoothstep(.76, .98, sin((FRAGCOORD.x + FRAGCOORD.y * .63) * .75));
    ALBEDO = mix(vec3(.32, .85, .75), vec3(1.0, .89, .58), rim * rim);
    ALPHA = .085 + .48 * smoothstep(.47, .92, rim) + stripe * .18;
}
