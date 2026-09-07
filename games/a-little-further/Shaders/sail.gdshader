shader_type spatial;
render_mode cull_disabled;
varying vec3 cloth;
void vertex(){cloth=VERTEX;VERTEX.z+=sin(TIME*1.6+VERTEX.y*1.3+VERTEX.x*2.)*abs(VERTEX.x)*.075;}
void fragment(){float seam=abs(sin(cloth.y*5.5));ALBEDO=vec3(.78,.65,.40)*mix(.93,1.,smoothstep(0.,.08,seam));ROUGHNESS=1.;}
