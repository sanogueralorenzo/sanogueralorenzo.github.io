shader_type spatial;
render_mode diffuse_burley, specular_disabled;
#include "res://shared/surface_noise.gdshaderinc"
uniform vec4 tint:source_color=vec4(.65,.65,.55,1.);
uniform int finish=0;
varying vec3 world;
varying vec3 local_normal;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;local_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 vec2 p=abs(local_normal.y)>.6?world.xz:(abs(local_normal.x)>.6?world.zy:world.xy);
 float mark=.97+(noise(p*.55)-.5)*.07+(noise(p*11.)-.5)*.025;
 if(finish==1){vec2 grid=p/1.1;mark*=1.-.10*max(seam(grid.x,.007),seam(grid.y,.007));mark*=.965+hash(floor(grid))*.07;}
 if(finish==2){vec2 tile=p*5.;mark*=1.-.22*max(seam(tile.x,.025),seam(tile.y,.025));mark*=.92+hash(floor(p*5.))*.14;}
 if(finish==3){mark*=.97+.025*sin(p.x*35.+sin(p.y*3.)*.6)*(1.-smoothstep(.4,1.5,fwidth(p.x*35.)));}
 if(finish==4){float groove=sin(p.x*31.+sin(p.y*1.8)*.9);mark*=mix(.93+.07*smoothstep(-.6,.3,groove),.965,smoothstep(.4,1.5,fwidth(p.x*31.)));}
 ALBEDO=tint.rgb*mark;ROUGHNESS=.92;
}
