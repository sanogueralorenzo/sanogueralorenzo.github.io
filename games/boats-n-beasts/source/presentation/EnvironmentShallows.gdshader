shader_type spatial;
render_mode unshaded, cull_disabled;
vec3 linear_color(vec3 c) { return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c)); }
void fragment() {
    // Two quiet polygon bands share the actual coast outline; no texture or glow.
    ALBEDO=linear_color(COLOR.rgb);
}
