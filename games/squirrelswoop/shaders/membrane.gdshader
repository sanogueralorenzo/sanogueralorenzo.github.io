shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
#include "res://shaders/pigment.gdshaderinc"
varying vec3 pigment;
void vertex(){pigment=COLOR.rgb;}
void fragment(){
 // Subtle tension folds follow the limb attachments; geometry supplies the camber.
 float fold=sin(UV.y*22.0+UV.x*9.0)*sin(UV.x*3.14159);
 ALBEDO=pigment_to_linear(pigment*(0.98+fold*0.025));
 ROUGHNESS=0.94;
 BACKLIGHT=ALBEDO*0.18;
}
