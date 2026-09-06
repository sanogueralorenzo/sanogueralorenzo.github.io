shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
varying vec3 local_position;
varying vec3 pigment;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.0),f.x),f.y);}
void vertex(){local_position=VERTEX;pigment=COLOR.rgb;}
void fragment(){
 vec2 grain_uv=vec2(local_position.x*90.0+sin(local_position.z*8.0)*0.8,local_position.z*13.0);
 float footprint=max(length(dFdx(grain_uv)),length(dFdy(grain_uv)));
 float strand=mix(noise(grain_uv),0.5,smoothstep(0.5,1.5,footprint));
 float clump=noise(local_position.xz*vec2(18.0,7.0));
 // Compatibility converts ALBEDO to linear after this shader. Keep pigment in sRGB.
 ALBEDO=pigment*(0.88+strand*0.14+clump*0.12);
 ROUGHNESS=0.93;
}
