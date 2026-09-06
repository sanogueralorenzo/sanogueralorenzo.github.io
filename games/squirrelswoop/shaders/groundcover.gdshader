shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
#include "res://shaders/pigment.gdshaderinc"
varying vec3 ink;
void vertex(){
 vec3 p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 VERTEX.x+=sin(p.x*.6+p.z*.3+TIME*1.8)*VERTEX.y*.06;
 ink=COLOR.rgb;
}
void fragment(){ALBEDO=pigment_to_linear(ink);ROUGHNESS=1.0;BACKLIGHT=ALBEDO*.08;}
