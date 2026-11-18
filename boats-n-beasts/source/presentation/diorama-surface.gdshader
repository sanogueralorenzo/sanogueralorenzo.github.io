shader_type spatial;
render_mode cull_disabled, diffuse_lambert;
uniform float clock=0.0;
instance uniform int creature_kind=0;
instance uniform float creature_scale=1.0;
instance uniform float phase=0.0;
instance uniform float movement_rate=1.0;
instance uniform float swelling=0.0;
instance uniform bool sail_motion=false;
vec3 linear_color(vec3 srgb) { return mix(srgb/12.92,pow((srgb+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),srgb)); }
float sail_offset(vec2 p) {
    float v=clamp((p.y-.68)/.72,0.0,1.0);
    float width=mix(.60,.72,v)+.16*sin(v*3.14159265);
    float weight=sin(v*3.14159265)*max(0.0,cos(p.x/width*3.14159265));
    return weight*(.018*sin(clock*1.6)+.004*sin(clock*2.7+p.x*12.0-v*3.0));
}
void vertex() {
    if(sail_motion) {
        float motion=sail_offset(VERTEX.xy);
        float dx=(sail_offset(VERTEX.xy+vec2(.001,0))-motion)/.001;
        float dy=(sail_offset(VERTEX.xy+vec2(0,.001))-motion)/.001;
        VERTEX.z+=motion;
        NORMAL=normalize(vec3(NORMAL.x-NORMAL.z*dx,NORMAL.y-NORMAL.z*dy,NORMAL.z));
    }
    vec3 p=VERTEX/creature_scale;
    float t=clock*movement_rate+phase;
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
    vec3 shell=mix(COLOR.rgb,vec3(.94,.25,.14),swelling*.8);
    ALBEDO=linear_color(shell);
    ROUGHNESS=1.0; SPECULAR=0.0;
}
