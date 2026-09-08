shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform vec4 tint : source_color=vec4(.8,.8,.7,1.);
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;float free_edge=UV.y*UV.y;VERTEX.z+=free_edge*(sin(TIME*1.7+world.x*1.8)*.11+sin(TIME*2.8+UV.x*9.)*.035);}
void fragment(){float fold=.92+.08*sin(UV.x*37.+sin(UV.y*7.)*.7);ALBEDO=tint.rgb*fold;ROUGHNESS=1.;BACKLIGHT=ALBEDO*.2;}
