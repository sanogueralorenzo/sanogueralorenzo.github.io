shader_type spatial;
render_mode diffuse_burley;
varying vec3 world;
uniform float mountain_seed = 0.0;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) { vec2 i=floor(p);vec2 f=fract(p); f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.0),f.x),f.y); }
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float d=-world.z;
 float center=12.0*sin(d*0.006+mountain_seed)+6.0*sin(d*0.017+mountain_seed*2.0);
 float river=abs(world.x-center);
 float woodland=smoothstep(12.0,48.0,world.x-center);
 float n=noise(world.xz*0.18)+0.5*noise(world.xz*0.7)+0.23*noise(world.xz*2.7);
 vec3 meadow=mix(vec3(0.045,0.085,0.021),vec3(0.17,0.21,0.063),n*0.55);
 vec3 forest=mix(vec3(0.027,0.048,0.025),vec3(0.10,0.14,0.035),n*0.61);
 vec3 soil=mix(vec3(0.09,0.105,0.084),vec3(0.23,0.24,0.17),noise(world.xz*0.43));
 vec3 col=mix(meadow,forest,woodland);
 col=mix(col,soil,smoothstep(1.13,1.42,n)*0.6);
 col=mix(soil,col,smoothstep(2.5,8.0,river));
 float litter=noise(world.xz*8.0+7.0);
 float speck=noise(world.xz*31.0);
 col*=0.81+litter*0.25+speck*0.12;
 col=mix(col,vec3(.12,.085,.043),woodland*smoothstep(.58,.75,litter)*.38);
 ALBEDO=col;ROUGHNESS=1.0;
}
