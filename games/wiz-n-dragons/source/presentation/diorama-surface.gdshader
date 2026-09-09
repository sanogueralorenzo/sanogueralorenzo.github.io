shader_type spatial;
render_mode cull_disabled, diffuse_lambert;
uniform float clock=0.0;
instance uniform int creature_kind=0;
instance uniform float creature_scale=1.0;
instance uniform float phase=0.0;
instance uniform float movement_rate=1.0;
instance uniform float swelling=0.0;
vec3 linear_color(vec3 srgb) { return mix(srgb/12.92,pow((srgb+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),srgb)); }
void vertex() {
    vec3 p=VERTEX/creature_scale;
    float t=clock*movement_rate+phase;
    if(creature_kind!=0 && creature_kind!=2) {
        float wing=smoothstep(.25,.7,abs(p.x));
        VERTEX.y+=sin(t*7.0)*wing*.18*creature_scale;
    }
}
void fragment() {
    ALBEDO=linear_color(mix(COLOR.rgb,vec3(.94,.25,.14),swelling*.8));
    ROUGHNESS=1.0; SPECULAR=0.0;
}
