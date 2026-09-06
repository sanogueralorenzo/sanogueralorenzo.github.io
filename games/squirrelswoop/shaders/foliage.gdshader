shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
uniform sampler2D bough_texture : source_color, filter_linear_mipmap, repeat_disable;
varying vec3 ink;
varying vec3 world_position;
global uniform vec3 swoop_player;
void vertex(){
 vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 world_position=world;
 float sway=smoothstep(10.0,32.0,VERTEX.y);
 VERTEX.x+=sin(world.z*0.11+world.x*0.13+TIME*1.15)*0.13*sway;
 ink=COLOR.rgb;
}
void fragment(){
 // Only soft foliage clears the short camera-to-character sightline. Solid wood
 // always remains visible, so a close canopy never hides the next collision.
 vec3 ray=swoop_player-CAMERA_POSITION_WORLD;
 float ray_length=max(dot(ray,ray),0.01);
 float t=clamp(dot(world_position-CAMERA_POSITION_WORLD,ray)/ray_length,0.0,1.0);
 float side=length(world_position-CAMERA_POSITION_WORLD-ray*t);
 float between=1.0-smoothstep(0.82,1.0,t);
 float reveal=(1.0-smoothstep(0.9,2.0,side))*between;
 float near_camera=smoothstep(1.6,3.8,length(world_position-CAMERA_POSITION_WORLD));
 float visibility=min(1.0-reveal*0.96,near_camera);
 float pattern=fract(dot(FRAGCOORD.xy,vec2(0.75487766,0.56984029)));
 if(pattern>visibility){discard;}
 vec4 needles=texture(bough_texture,UV);
 bool core=UV.x<0.0;
 ALBEDO=core?ink:needles.rgb*ink;
 if (!core && needles.a<0.34) { discard; }
 ROUGHNESS=0.96;
 BACKLIGHT=ALBEDO*0.28;
}
