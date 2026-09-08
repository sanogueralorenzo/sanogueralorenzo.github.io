shader_type spatial;
render_mode cull_disabled, diffuse_lambert;
uniform float clock=0.0;
instance uniform int creature_kind=0;
instance uniform float creature_scale=1.0;
instance uniform float phase=0.0;
vec3 linear_color(vec3 srgb) { return mix(srgb/12.92,pow((srgb+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),srgb)); }
void vertex() {
    vec3 p=VERTEX/creature_scale;
    float t=clock+phase;
    if(creature_kind==1) {
        float leg=smoothstep(.21,.34,abs(p.x))*(1.0-smoothstep(.20,.26,p.y));
        VERTEX.z+=sin(t*8.0+p.z*27.0+sign(p.x)*1.7)*.022*leg*creature_scale;
        VERTEX.y+=sin(t*8.0+p.z*27.0)*.011*leg*creature_scale;
    } else if(creature_kind==2) {
        VERTEX.z+=sin(t*7.0+p.x*9.0)*smoothstep(.18,.3,abs(p.x))*.024;
    } else if(creature_kind==3) {
        VERTEX.x+=sin(t*3.5+p.z*8.0)*smoothstep(.0,.65,p.z)*.045;
    } else if(creature_kind==4) {
        VERTEX.y+=sin(t*3.8+abs(p.x)*5.0)*smoothstep(.15,.47,abs(p.x))*.055;
    }
}
void fragment() {
    ALBEDO=linear_color(COLOR.rgb);
    ROUGHNESS=1.0; SPECULAR=0.0;
}
