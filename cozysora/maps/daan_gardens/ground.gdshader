shader_type spatial;
render_mode specular_disabled;
#include "res://shared/surface_noise.gdshaderinc"
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;}
void fragment(){float patch=noise(world.xz*.16)*.65+noise(world.xz*.52)*.35;float grain=noise(world.xz*9.);vec3 grass=mix(vec3(.36,.44,.23),vec3(.46,.50,.28),patch);ALBEDO=pow(grass,vec3(2.2))*(.93+grain*.1);ROUGHNESS=1.;}
