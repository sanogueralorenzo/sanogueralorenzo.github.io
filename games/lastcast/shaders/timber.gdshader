shader_type spatial;
render_mode specular_disabled;
varying vec3 world;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;}
void fragment(){
 float grain=sin(world.z*63.+sin(world.x*2.1)*2.6+sin(world.z*14.)*.4);
 float fine=hash(floor(world.xz*150.));
 float weather=sin(world.x*.71+world.z*.39)*.028;
 ALBEDO=pow(vec3(.52,.43,.31),vec3(2.0))*(.98+grain*.065+fine*.045+weather);
 ROUGHNESS=.96;
}
