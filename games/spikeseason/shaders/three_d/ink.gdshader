shader_type spatial;
render_mode cull_front, unshaded;
uniform float width=0.006;
void vertex(){VERTEX+=NORMAL*width;}
void fragment(){ALBEDO=vec3(.085,.075,.057);}
