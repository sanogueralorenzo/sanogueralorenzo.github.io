shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled, alpha_to_coverage;
#include "res://shaders/pigment.gdshaderinc"
uniform sampler2D bough_texture : source_color, filter_linear_mipmap, repeat_disable;
varying vec3 ink;
varying vec3 world_position;
global uniform vec3 swoop_player;
void vertex(){
 vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 float sway=smoothstep(10.0,32.0,VERTEX.y);
 VERTEX.x+=sin(world.z*0.11+world.x*0.13+TIME*1.15)*0.13*sway;
 world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 ink=pigment_to_linear(COLOR.rgb);
}
void fragment(){
 // Only soft foliage clears the short camera-to-character sightline. Solid wood
 // always remains visible, so a close canopy never hides the next collision.
 float visibility=1.0;
 // Reveal is camera visibility, not a moving hole in the forest's shadow.
 if (!IN_SHADOW_PASS) {
 vec3 ray=swoop_player-CAMERA_POSITION_WORLD;
 float ray_length=max(dot(ray,ray),0.01);
 float t=clamp(dot(world_position-CAMERA_POSITION_WORLD,ray)/ray_length,0.0,1.0);
 float side=length(world_position-CAMERA_POSITION_WORLD-ray*t);
 float between=1.0-smoothstep(0.82,1.0,t);
 float reveal=(1.0-smoothstep(0.9,2.0,side))*between;
 float near_camera=smoothstep(1.6,3.8,length(world_position-CAMERA_POSITION_WORLD));
 visibility=min(1.0-reveal*0.96,near_camera);
 }
 vec4 needles=texture(bough_texture,UV);
 ALBEDO=needles.rgb*ink;
 // Native MSAA coverage keeps fine needles and the reveal stable in motion.
 ALPHA=needles.a*visibility;
 ALPHA_SCISSOR_THRESHOLD=0.20;
 ALPHA_ANTIALIASING_EDGE=0.14;
 ALPHA_TEXTURE_COORDINATE=UV*vec2(textureSize(bough_texture,0));
 ROUGHNESS=0.96;
 BACKLIGHT=ALBEDO*0.28;
}
