shader_type spatial;
render_mode diffuse_burley, specular_disabled;
#include "res://shaders/pigment.gdshaderinc"
varying vec3 local;
float h(vec2 p){vec3 q=fract(vec3(p.xyx)*0.1031);q+=dot(q,q.yzx+33.33);return fract((q.x+q.y)*q.z);}
float n(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+1.0),f.x),f.y);}
void vertex(){local=VERTEX;}
void fragment(){
 // UV grain follows each bent limb and log, with broad overlapping bark plates.
 vec2 p=UV*vec2(8.0,0.95);
 p.x+=n(p*vec2(.20,.7))*1.1;
 float ridges=n(p*vec2(1.0,.35));
 float fissure=smoothstep(.24,.39,ridges);
 float plate=n(p*vec2(2.0,1.1));
 float chips=n(p*vec2(5.0,3.5));
 vec3 wood=mix(vec3(.31,.245,.17),vec3(.62,.48,.31),plate*.62+ridges*.38);
 wood*=mix(.48,1.0,fissure)*(.88+chips*.20);
 float moss=(1.0-smoothstep(.5,5.0,local.y))*smoothstep(.39,.67,n(local.xz*1.6+local.y*.4));
 wood=mix(wood,mix(vec3(.20,.26,.12),vec3(.39,.43,.21),chips),moss*.74);
 ALBEDO=pigment_to_linear(wood);ROUGHNESS=1.0;
}
