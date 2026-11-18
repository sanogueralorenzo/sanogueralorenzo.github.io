shader_type spatial;
render_mode cull_disabled, diffuse_lambert;
uniform float clock=0.0;
instance uniform int creature_kind=0;
instance uniform float creature_scale=1.0;
instance uniform float phase=0.0;
instance uniform float movement_rate=1.0;
instance uniform float swelling=0.0;
instance uniform float strike_flash=0.0;
instance uniform bool sail_motion=false;
instance uniform int sail_crest=0;
instance uniform vec4 sail_ink=vec4(0.0,0.0,0.0,1.0);
varying vec2 sail_point;
vec3 linear_color(vec3 srgb) { return mix(srgb/12.92,pow((srgb+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),srgb)); }
float sail_offset(vec2 p) {
    float v=clamp((p.y-.68)/.72,0.0,1.0);
    float width=mix(.60,.72,v)+.16*sin(v*3.14159265);
    float weight=sin(v*3.14159265)*max(0.0,cos(p.x/width*3.14159265));
    return weight*(.018*sin(clock*1.6)+.004*sin(clock*2.7+p.x*12.0-v*3.0));
}
float sail_stroke(vec2 point, vec2 from, vec2 to, float width) {
    vec2 direction=to-from;
    vec2 nearest=from+direction*clamp(dot(point-from,direction)/dot(direction,direction),0.0,1.0);
    return distance(point,nearest)-width;
}
float sail_band(float position, float low, float high) { return max(low-position,position-high); }
float sail_emblem(vec2 p) {
    float x=abs(p.x);
    if(sail_crest==1) {
        float diamond=x+abs(p.y)*1.20;
        return min(abs(diamond-.139)-.016,diamond-.057);
    }
    if(sail_crest==2) {
        float tower=max(x-mix(.080,.048,clamp((p.y+.118)/.146,0.0,1.0)),sail_band(p.y,-.118,.028));
        float balcony=max(x-.084,sail_band(p.y,.041,.058));
        float roof=max(x-max(0.0,(.128-p.y)*.96),sail_band(p.y,.074,.128));
        float beam=sail_stroke(vec2(x,p.y),vec2(.094,.066),vec2(.156,.100),.009);
        return min(min(tower,balcony),min(roof,beam));
    }
    if(sail_crest==4) {
        float crown=sail_stroke(p,vec2(.061,.151),vec2(-.066,.002),.025);
        float fork=sail_stroke(p,vec2(-.066,.002),vec2(.064,.021),.024);
        float point=sail_stroke(p,vec2(.064,.021),vec2(-.058,-.145),.018);
        return min(min(crown,fork),point);
    }
    float upper=max(max(-.085+.56*p.y-p.x,p.x-(.028+.23*p.y)),sail_band(p.y,-.015,.133));
    float middle=max(max(-.093-p.x,p.x-.081),sail_band(p.y,-.035,.013));
    float lower=max(max(-.013+.17*p.y-p.x,p.x-(.092+.96*p.y)),sail_band(p.y,-.126,-.020));
    float wreath=sail_stroke(vec2(x,p.y),vec2(.149,-.048),vec2(.127,-.090),.010);
    wreath=min(wreath,sail_stroke(vec2(x,p.y),vec2(.127,-.090),vec2(.077,-.127),.010));
    return min(min(upper,middle),min(lower,wreath));
}
void vertex() {
    sail_point=VERTEX.xy-vec2(0.0,1.11);
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
    vec3 pigment=COLOR.rgb;
    if(sail_crest!=0) {
        float emblem=sail_emblem(sail_point);
        pigment=mix(pigment,sail_ink.rgb,1.0-smoothstep(-.008,.008,emblem));
    }
    vec3 shell=mix(pigment,vec3(.94,.25,.14),swelling*.8);
    ALBEDO=linear_color(mix(shell, vec3(1.0, .87, .62), strike_flash * .48));
    ROUGHNESS=1.0; SPECULAR=0.0;
}
