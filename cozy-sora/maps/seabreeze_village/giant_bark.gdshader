shader_type spatial;
render_mode specular_disabled;
uniform sampler2D bark_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 bark_color : source_color = vec4(0.706,0.737,0.722,1.0);
uniform vec3 tree_origin;
varying vec3 world_position;
float hash_b(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise_b(vec2 p) { vec2 a=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash_b(a),hash_b(a+vec2(1,0)),f.x),mix(hash_b(a+vec2(0,1)),hash_b(a+vec2(1,1)),f.x),f.y); }
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 vec3 delta=world_position-tree_origin;
 float angle=atan(delta.z,delta.x);
 float angular_distance=abs(mod(angle+1.065+PI,TAU)-PI);
 float hollow=length(vec2(angular_distance/(0.34*1.6),(delta.y-2.7)/(0.85*1.6)));
 hollow+=(noise_b(vec2(angle*6.0,world_position.y*2.2))-0.5)*0.5;
 float cavity=1.0-smoothstep(0.55,1.0,hollow);
 float lip=(1.0-smoothstep(1.0,1.35,hollow))*(1.0-cavity);
 ALBEDO=texture(bark_texture,UV*vec2(2.0,1.6)).rgb*bark_color.rgb;
 ALBEDO=mix(ALBEDO,vec3(0.12,0.10,0.08),lip*0.6);
 ALBEDO=mix(ALBEDO,vec3(0.0015,0.002,0.003),cavity);
 ROUGHNESS=1.0;
}
void light() { float raw=dot(NORMAL,LIGHT); float band=(smoothstep(-0.4,0.15,raw)*0.5+smoothstep(0.2,0.7,raw)*0.4)*0.9+0.14; DIFFUSE_LIGHT+=band*ATTENUATION*LIGHT_COLOR/PI; }
