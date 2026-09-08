shader_type spatial;
render_mode diffuse_burley, specular_disabled;
#include "res://shared/surface_noise.gdshaderinc"
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;}
void fragment(){
 float broad=noise(world.xz*.12);
 float mottled=noise(world.xz*1.7);
 float fine=noise(world.xz*16.0);
 vec3 grass=mix(vec3(.23,.32,.15),vec3(.39,.44,.24),broad);
 grass*=.89+mottled*.19+fine*.07;
 ALBEDO=grass;ROUGHNESS=1.0;
}
