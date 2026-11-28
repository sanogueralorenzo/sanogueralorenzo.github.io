shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, depth_draw_never, depth_test_inverted;

uniform vec4 outline_color : source_color = vec4(.09, .12, .20, 1.0);
uniform vec4 shell_color : source_color = vec4(1.0, .40, .23, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, .91, .68, 1.0);

void vertex() {
    vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    VERTEX = center + vec3(VERTEX.xy, 1.04);
}

void fragment() {
    vec2 point = abs(UV * 2.0 - 1.0);
    float diamond = point.x + point.y;
    float edge = max(fwidth(diamond) * .7, .035);
    vec3 color = mix(shell_color.rgb, outline_color.rgb, smoothstep(.68 - edge, .68 + edge, diamond));
    ALBEDO = mix(core_color.rgb, color, smoothstep(.23 - edge, .23 + edge, diamond));
    ALPHA = (1.0 - smoothstep(.91 - edge, .91 + edge, diamond)) * .85;
}
