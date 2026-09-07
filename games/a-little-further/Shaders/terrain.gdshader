shader_type spatial;
render_mode cull_disabled;
uniform sampler2D grass_texture:source_color,repeat_enable,filter_linear_mipmap;
varying vec3 local_position;
void vertex(){local_position=VERTEX;}
void fragment(){
 vec3 sample_color=texture(grass_texture,local_position.xz*.045).rgb;
 float grain=dot(sample_color,vec3(.3,.59,.11));
 float detail=mix(1.,.79+grain*.63,smoothstep(1.8,3.3,local_position.y));
 ALBEDO=pow(COLOR.rgb,vec3(2.2))*detail;
 ROUGHNESS=.95;
}
