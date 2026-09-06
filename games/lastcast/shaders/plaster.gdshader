shader_type spatial;
uniform vec4 tint : source_color = vec4(.9,.7,.5,1);
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){float grain=fract(sin(dot(floor(world*30.0),vec3(12.98,78.23,37.71)))*43758.5);float stain=sin(world.x*2.1+sin(world.y*3.2))*sin(world.z*1.4+world.y);ALBEDO=tint.rgb*(.96+grain*.06+stain*.025);ROUGHNESS=.88;}
