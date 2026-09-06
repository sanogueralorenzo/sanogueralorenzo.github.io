shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;
uniform vec4 tint : source_color = vec4(.34,.49,.18,1);
uniform sampler2D leaf_spray : filter_linear_mipmap, repeat_disable;
varying vec3 world;
varying vec3 crown_normal;
void vertex(){
 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 float wind=sin(TIME*.85+world.x*.52+world.z*.34)+sin(TIME*1.8+world.z)*.25;
 VERTEX.x+=wind*.026;VERTEX.z+=cos(TIME*.68+world.x*.4)*.018;
 crown_normal=normalize(MODELVIEW_NORMAL_MATRIX*NORMAL);
}
void fragment(){
 vec4 leaf=texture(leaf_spray,UV);
 ALBEDO=pow(tint.rgb*COLOR.rgb,vec3(1.92))*leaf.rgb;
 ALPHA=leaf.a;ALPHA_SCISSOR_THRESHOLD=.46;
 NORMAL=normalize(crown_normal);
 ROUGHNESS=.98;BACKLIGHT=ALBEDO*.23;
}
