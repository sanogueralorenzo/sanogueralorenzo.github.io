shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
uniform sampler2D leaf_texture : filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(0.298,0.478,0.227,1.0);
uniform float wind_amplitude = 0.16;
uniform float band_lift = 0.10;
uniform float band_scale = 1.0;
uniform bool color_texture = false;
uniform vec3 gradient_bottom = vec3(0.80,0.90,1.02);
uniform vec3 gradient_top = vec3(1.16,1.10,0.78);
uniform float near_fade = 1.2;
global uniform vec3 cat_position;
varying vec3 leaf_color;
varying vec3 canopy_normal;
void vertex() {
    vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float sway = COLOR.a;
    float wind = sin(world.x * 0.19 + world.z * 0.13 + TIME * 1.5) + 0.45 * sin(world.z * 0.61 + TIME * 2.3);
    VERTEX.x += wind * wind_amplitude * sway;
    VERTEX.z += cos(world.x * 0.22 + world.z * 0.12 + TIME * 1.15) * wind_amplitude * sway * 0.6;
    vec2 dc = world.xz-cat_position.xz;
    float distance_to_cat = length(dc);
    float near_cat = step(abs(world.y-cat_position.y),2.0);
    float push = (1.0-smoothstep(0.0,1.5,distance_to_cat))*sway*near_cat;
    VERTEX.xz += dc/max(distance_to_cat,0.05)*push*0.9;
    VERTEX.y -= push*0.55 + sway*sway*(1.0-smoothstep(0.6,3.2,distance_to_cat))*near_cat*0.55;
    leaf_color = COLOR.rgb;
    canopy_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL,0.0)).xyz);
}
void fragment() {
    if (length(VERTEX)<near_fade) { discard; }
    NORMAL = normalize(canopy_normal);
    vec4 leaf = texture(leaf_texture, UV);
    if (color_texture) { leaf.rgb = pow(leaf.rgb,vec3(2.2)); }
    ALBEDO = tint.rgb * leaf.rgb * leaf_color;
    if (!color_texture) { ALBEDO *= mix(gradient_bottom,gradient_top,1.0-UV.y); }
    ALPHA = leaf.a;
    ALPHA_SCISSOR_THRESHOLD = 0.45;
    ROUGHNESS = 1.0;
    BACKLIGHT = ALBEDO * 0.16;
}
void light() {
    float raw = dot(NORMAL,LIGHT);
    float band = (smoothstep(-0.40,0.15,raw)*0.50 + smoothstep(0.20,0.70,raw)*0.40)*band_scale + band_lift;
    DIFFUSE_LIGHT += band * ATTENUATION * LIGHT_COLOR / PI;
}
