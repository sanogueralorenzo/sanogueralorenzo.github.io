shader_type spatial;
render_mode diffuse_burley;
#include "res://shaders/pigment.gdshaderinc"
varying vec3 world;
uniform float mountain_seed = 0.0;
float hash(vec2 p) { vec3 q=fract(vec3(p.xyx)*0.1031);q+=dot(q,q.yzx+33.33);return fract((q.x+q.y)*q.z); }
float noise(vec2 p) { vec2 i=floor(p);vec2 f=fract(p); f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.0),f.x),f.y); }
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float d=-world.z;
 float center=12.0*sin(d*0.006+mountain_seed)+6.0*sin(d*0.017+mountain_seed*2.0);
 float river=abs(world.x-center);
 float woodland=smoothstep(12.0,48.0,world.x-center);
 float n=noise(world.xz*0.18)+0.5*noise(world.xz*0.7)+0.23*noise(world.xz*2.7);
 vec3 meadow=mix(vec3(0.16,0.22,0.085),vec3(0.34,0.39,0.18),n*0.55);
 vec3 forest=mix(vec3(0.15,0.19,0.105),vec3(0.29,0.32,0.16),n*0.61);
 vec3 soil=mix(vec3(0.25,0.26,0.20),vec3(0.39,0.39,0.29),noise(world.xz*0.43));
 vec3 col=mix(meadow,forest,woodland);
 col=mix(col,soil,smoothstep(1.13,1.42,n)*0.6);
 col=mix(soil,col,smoothstep(2.5,8.0,river));
 float litter=noise(world.xz*2.5+7.0);
 col*=0.90+litter*0.18;
 col=mix(col,vec3(.25,.20,.12),woodland*smoothstep(.58,.75,litter)*.38);
 ALBEDO=pigment_to_linear(col);ROUGHNESS=1.0;
}
