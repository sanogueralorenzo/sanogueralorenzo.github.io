shader_type spatial;
render_mode diffuse_burley, cull_disabled;
#include "res://shaders/pigment.gdshaderinc"
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 // Opaque shallow current: the stream is a terrain-fitted 7.5 cm sheet, not a
 // deep pool. No fabricated depth absorption, screen copy or sorting pass.
 float edge=smoothstep(0.20,0.48,abs(UV.x-0.5));
 float phase_a=world.z*1.5+world.x*3.1+TIME*3.8;
 float phase_b=world.z*0.57-world.x*2.6+TIME*1.8;
 float current=sin(UV.y*2.9+TIME*4.0+sin(world.x*3.3))*0.5+0.5;
 float riffle=smoothstep(0.55,0.85,COLOR.r)*pow(current,10.0);
 vec3 pigment=mix(vec3(0.10,0.19,0.18),vec3(0.20,0.24,0.17),edge);
 ALBEDO=pigment_to_linear(mix(pigment,vec3(0.38,0.41,0.33),riffle*0.12));
 // Perturb in world space, then transform to view space. The engine supplies
 // Fresnel, sky radiance, and sun highlights rather than painted glints.
 vec3 ripple_world=vec3(cos(phase_a)*0.065+cos(phase_b)*0.035,0.0,sin(phase_b)*0.05);
 NORMAL=normalize(NORMAL+(VIEW_MATRIX*vec4(ripple_world,0.0)).xyz*(1.0-edge*0.6));
 ROUGHNESS=mix(0.28,0.52,edge);METALLIC=0.0;SPECULAR=0.4;
}
