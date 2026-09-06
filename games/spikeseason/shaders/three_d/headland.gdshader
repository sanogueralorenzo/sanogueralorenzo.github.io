shader_type spatial;
render_mode unshaded, fog_disabled;
uniform vec4 land_color : source_color = vec4(.45,.59,.60,1.0);
varying vec3 world_normal;
void vertex(){world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){ALBEDO=land_color.rgb*(.82+.18*max(dot(normalize(world_normal),normalize(vec3(-.4,.8,.3))),0.));}
