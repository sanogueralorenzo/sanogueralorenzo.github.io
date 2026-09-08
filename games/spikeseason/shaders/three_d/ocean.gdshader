shader_type spatial;
render_mode unshaded, fog_disabled;
uniform float warmth=0.;
varying vec3 world_pos;
#include "res://shaders/three_d/surface_noise.gdshaderinc"
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;}
void fragment(){
 vec2 p=world_pos.xz;
 float dist=length(world_pos-CAMERA_POSITION_WORLD);
 float waves=noise(p*vec2(.17,.65)+vec2(TIME*.13,-TIME*.10))*.6+noise(p*vec2(.41,1.4)+vec2(-TIME*.12,TIME*.07))*.4;
 vec3 shallow=vec3(.22,.65,.69);
 vec3 deep=vec3(.19,.47,.64);
 vec3 color=mix(shallow,deep,smoothstep(12.,95.,dist));
 color+=vec3(.035,.055,.058)*(waves-.5)*1.8;
 float crest=pow(noise(p*vec2(.7,3.2)+vec2(TIME*.25,-TIME*.23)),11.);
 float flicker=noise(p*.6+vec2(TIME*.03,0.));
 color=mix(color,vec3(.81,.91,.86),clamp(crest*3.*smoothstep(.42,.7,flicker),0.,.7)*(1.-smoothstep(60.,180.,dist)));
 color=mix(color,vec3(.57,.72,.77),smoothstep(200.,800.,dist));
 color=mix(color,color*vec3(1.22,.93,.91),warmth);
 ALBEDO=pow(color,vec3(2.2));
}
