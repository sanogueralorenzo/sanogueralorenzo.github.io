shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled, alpha_to_coverage;
uniform vec4 tint : source_color = vec4(.34,.49,.18,1);
uniform sampler2D leaf_spray : source_color, filter_linear_mipmap, repeat_disable;
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
 ALBEDO=tint.rgb*COLOR.rgb*leaf.rgb;
 ALPHA=leaf.a;ALPHA_SCISSOR_THRESHOLD=.46;
 ALPHA_ANTIALIASING_EDGE=.3;ALPHA_TEXTURE_COORDINATE=UV*vec2(textureSize(leaf_spray,0));
 NORMAL=normalize(crown_normal);
 ROUGHNESS=.98;BACKLIGHT=ALBEDO*.23;
}
