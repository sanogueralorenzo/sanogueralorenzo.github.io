shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
varying vec3 tint;
varying vec3 canopy_normal;
global uniform vec3 cat_position;
uniform vec3 grass_base = vec3(0.16,0.28,0.16);
uniform vec3 grass_mid = vec3(0.28,0.40,0.19);
uniform vec3 grass_tip = vec3(0.47,0.50,0.25);
uniform float band_lift = 0.0;
void vertex() {
    vec3 world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    float bend = UV.y * UV.y;
    VERTEX.x += (sin(world.x * 0.19 + world.z * 0.13 + TIME * 1.5) + 0.45 * sin(world.z * 0.61 + TIME * 2.3)) * 0.22 * bend;
    VERTEX.z += cos(world.x * 0.22 + world.z * 0.12 + TIME * 1.15) * 0.13 * bend;
    vec2 dc = world.xz-cat_position.xz;
    float distance_to_cat = length(dc);
    float near_cat = step(abs(world.y-cat_position.y),2.0);
    float push = (1.0-smoothstep(0.0,1.5,distance_to_cat))*UV.y*near_cat;
    VERTEX.xz += dc/max(distance_to_cat,0.05)*push*0.9;
    VERTEX.y -= push*0.55 + bend*(1.0-smoothstep(0.6,3.2,distance_to_cat))*near_cat*0.55;
    NORMAL = normalize(mix(NORMAL,vec3(0.0,1.0,0.0),0.7));
    canopy_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL,0.0)).xyz);
    tint = COLOR.rgb;
}
void fragment() {
    if (length(VERTEX)<0.45) { discard; }
    NORMAL = normalize(canopy_normal);
    vec3 base = pow(grass_base,vec3(2.2));
    vec3 mid = pow(grass_mid,vec3(2.2));
    vec3 tip = pow(grass_tip,vec3(2.2));
    ALBEDO = mix(mix(base,mid,smoothstep(0.0,0.55,UV.y)),tip,smoothstep(0.55,1.0,UV.y)) * tint;
    ROUGHNESS = 1.0;
    BACKLIGHT = ALBEDO * 0.10;
}
void light() {
    float raw = dot(NORMAL,LIGHT);
    float band = smoothstep(-0.40,0.15,raw)*0.50 + smoothstep(0.20,0.70,raw)*0.40 + band_lift;
    vec3 tone = mix(vec3(0.66,0.88,1.10),vec3(0.96,0.94,0.80),smoothstep(0.12,0.55,band*ATTENUATION));
    DIFFUSE_LIGHT += band * ATTENUATION * LIGHT_COLOR * tone / PI;
}
