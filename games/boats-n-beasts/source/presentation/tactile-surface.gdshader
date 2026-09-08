shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform float clock=0.0;
instance uniform int creature_kind=0;
instance uniform float creature_scale=1.0;
instance uniform float phase=0.0;
varying vec3 local;
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise(vec3 p) {
    vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
vec3 linear_color(vec3 srgb) { return mix(srgb/12.92,pow((srgb+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),srgb)); }
void vertex() {
    local=VERTEX;
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
    float grain=noise(local*48.0)*.035+noise(local*12.0)*.065+noise(local*3.6)*.055;
    ALBEDO=linear_color(COLOR.rgb)*(.922+grain);
    ROUGHNESS=.87; SPECULAR=.18;
}
