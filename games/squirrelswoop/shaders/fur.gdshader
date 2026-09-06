shader_type spatial;
render_mode diffuse_burley, specular_disabled;
varying vec3 local;
float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float n(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+1.0),f.x),f.y);}
void vertex(){local=VERTEX;}
void fragment(){
 float strands=n(vec2(local.x*155.0+sin(local.z*3.0)*4.0,local.z*9.0));
 vec3 brown=mix(vec3(.32,.135,.048),vec3(.47,.245,.093),strands);
 ALBEDO=pow(brown,vec3(1.8));ROUGHNESS=.95;
}
