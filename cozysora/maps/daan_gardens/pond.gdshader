shader_type spatial;
render_mode cull_disabled;
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;}
void fragment(){
 float drift=.5+.5*sin(world.x*.13+world.z*.16);
 ALBEDO=mix(vec3(.025,.066,.046),vec3(.055,.105,.070),drift);
 ROUGHNESS=.36;METALLIC=.05;SPECULAR=.35;
 float a=sin(world.x*.7+sin(world.z*.38)*2.+TIME*.3);
 float b=sin(world.z*.8+sin(world.x*.31)*1.7-TIME*.22);
 NORMAL=normalize(NORMAL+vec3(a*.006,0.,b*.006));
}
