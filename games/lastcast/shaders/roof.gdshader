shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform vec4 tile_dark : source_color = vec4(.43,.275,.195,1.0);
uniform vec4 tile_light : source_color = vec4(.58,.36,.25,1.0);
varying vec3 world;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=world.xz*vec2(5.6,4.4);vec2 f=fract(p);
 float seam=smoothstep(.90,.99,f.y);float channel=pow(abs(sin(f.x*3.14159)),.7);
 vec3 tile=mix(tile_dark.rgb,tile_light.rgb,hash(floor(p)));
 ALBEDO=tile*(.88+channel*.15)*(1.0-seam*.13);ROUGHNESS=.96;
}
