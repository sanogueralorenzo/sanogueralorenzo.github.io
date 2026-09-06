shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
uniform sampler2D bough_texture : source_color, filter_linear_mipmap, repeat_disable;
varying vec3 ink;
void vertex(){
 vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 float sway=smoothstep(10.0,32.0,VERTEX.y);
 VERTEX.x+=sin(world.z*0.11+world.x*0.13+TIME*1.15)*0.13*sway;
 ink=COLOR.rgb;
}
void fragment(){
 vec4 needles=texture(bough_texture,UV);
 bool core=UV.x<0.0;
 ALBEDO=core?ink:needles.rgb*ink;
 if (!core && needles.a<0.34) { discard; }
 ROUGHNESS=0.96;
 BACKLIGHT=ALBEDO*0.28;
}
