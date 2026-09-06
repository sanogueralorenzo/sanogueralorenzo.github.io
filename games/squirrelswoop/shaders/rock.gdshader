shader_type spatial;
render_mode diffuse_burley, specular_disabled;
varying vec3 local;
varying vec3 normal_world;
float h(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
float n(vec3 p){vec3 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(mix(h(i),h(i+vec3(1,0,0)),f.x),mix(h(i+vec3(0,1,0)),h(i+vec3(1,1,0)),f.x),f.y),mix(mix(h(i+vec3(0,0,1)),h(i+vec3(1,0,1)),f.x),mix(h(i+vec3(0,1,1)),h(i+vec3(1,1,1)),f.x),f.y),f.z);}
void vertex(){local=VERTEX;normal_world=MODEL_NORMAL_MATRIX*NORMAL;}
void fragment(){
 float mineral=n(local*5.0)*.5+n(local*17.0)*.32+n(local*56.0)*.18;
 vec3 stone=mix(vec3(.22,.24,.22),vec3(.49,.49,.42),mineral);
 float fissure=smoothstep(.035,.10,abs(n(local*6.0+3.0)-.48));
 stone*=.68+.32*fissure;
 float patch=smoothstep(.32,.63,n(local*4.0)+normal_world.y*.24+local.y*.10);
 vec3 moss=mix(vec3(.11,.18,.045),vec3(.36,.41,.14),n(local*23.0));
 ALBEDO=pow(mix(stone,moss,patch*.90),vec3(2.2));ROUGHNESS=1.0;
}
