shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shared/surface_noise.gdshaderinc"
uniform vec4 base_color : source_color = vec4(.7,.6,.5,1.);
uniform float grain=.12;
uniform int pattern=0;
varying vec3 world;
varying vec3 face;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;face=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 vec2 plane=abs(face.y)>.6?world.xz:vec2(abs(face.x)>.6?world.z:world.x,world.y);
 float coarse=noise(plane*.43)+noise(plane*1.3+19.)*.45;
 float fine=noise(plane*13.);
 float finish=.94+(coarse-.7)*grain+(fine-.5)*grain*.18;
 if(pattern==1){finish*=1.-.15*seam(world.y*5.,.027);finish+=noise(vec2(plane.x*.75,world.y*35.))*.035;}
 if(pattern==2){float row=floor(world.y*5.);float mortar=max(seam(world.y*5.,.032),seam(plane.x*2.4+mod(row,2.)*.5,.023));finish*=1.-mortar*.19;finish+=(hash(vec2(floor(plane.x*2.4+mod(row,2.)*.5),row))-.5)*.13;}
 if(pattern==3){finish*=1.-.12*seam(plane.x*4.,.035);}
 if (pattern == 4) {
     float stone = noise(plane * 56.);
     float grit = noise(plane * 19. + 7.);
     finish = .75 + noise(plane * .32) * .22 + noise(plane * 1.7) * .09 + (stone - .5) * .21 + (grit - .5) * .14;
     finish *= 1. - .12 * smoothstep(.56, .72, noise(plane * .7 + 21.));
     NORMAL = relief_normal(VERTEX, NORMAL, stone * .001 + grit * .0016);
 }
 if(pattern==5){finish=.89+noise(plane*.45)*.17;finish*=1.-.12*max(seam(plane.x/1.6,.004),seam(plane.y/1.6,.004));}
 float sheen = .94;
 if (pattern == 6) {
     float grain_line = noise(UV * vec2(29., 2.3) + vec2(noise(UV * 3.) * 1.7, 0.));
     finish *= mix(.68, 1.17, grain_line);
     sheen = mix(.36, .58, grain_line);
 }
 if (pattern == 7) {
     finish *= .80 + .25 * noise(UV * 30.);
     sheen = .52;
     METALLIC = .64;
 }
 ALBEDO = base_color.rgb * finish;
 ROUGHNESS = sheen;
 SPECULAR = .25;
}
