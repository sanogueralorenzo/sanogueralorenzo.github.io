shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;
uniform vec4 tint : source_color = vec4(.34,.49,.18,1);
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;VERTEX.x+=sin(TIME*1.1+world.x*.8+world.z*.5)*.035;}
void fragment(){float fleck=sin(world.x*17.0+sin(world.y*12.0))*sin(world.z*18.0+world.y*9.0);ALBEDO=pow(tint.rgb*COLOR.rgb,vec3(2.2))*(.95+fleck*.07);ROUGHNESS=.9;EMISSION=ALBEDO*.09;BACKLIGHT=vec3(.13,.16,.035);}
