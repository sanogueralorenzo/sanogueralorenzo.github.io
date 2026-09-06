shader_type spatial;
render_mode cull_front, unshaded;
uniform vec4 ink_color : source_color = vec4(.30,.28,.24,1.);
uniform float width=0.006;
void vertex(){VERTEX+=NORMAL*width;}
void fragment(){ALBEDO=ink_color.rgb;}
