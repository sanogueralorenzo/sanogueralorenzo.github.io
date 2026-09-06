shader_type spatial;
render_mode diffuse_burley, fog_disabled;
// Opaque deep coastal water: no invented screen-depth shoreline or sorted alpha.
// Sky reflections remain valid when the bank leaves the camera view.
uniform vec4 water_color : source_color = vec4(.08,.43,.59,1.);
uniform vec4 crest_color : source_color = vec4(.69,.83,.80,1.);
uniform float warmth=0.;
varying vec3 world_pos;
#include "res://shaders/three_d/surface_noise.gdshaderinc"
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;}
void fragment(){
 vec2 p=world_pos.xz;
 float distance_to_camera=length(world_pos-CAMERA_POSITION_WORLD);
 float wave_a=p.x*.65+p.y*.38+TIME*.65;
 float wave_b=p.y*1.6-p.x*.3-TIME*.48;
 float detail=1.-smoothstep(50.,180.,distance_to_camera);
 vec3 normal=normalize(vec3((cos(wave_a)*.035-cos(wave_b)*.012)*detail,1.,(cos(wave_a)*.021+cos(wave_b)*.06)*detail));
 NORMAL=normalize((VIEW_MATRIX*vec4(normal,0.)).xyz);
 float waves=noise(p*vec2(.17,.65)+vec2(TIME*.13,-TIME*.10));
 float crest=pow(noise(p*vec2(.7,3.2)+vec2(TIME*.25,-TIME*.23)),11.);
 vec3 color=water_color.rgb*(.92+.16*waves);
 color=mix(color,crest_color.rgb,clamp(crest*1.4,0.,.25)*detail);
 ALBEDO=color*mix(vec3(1.),vec3(1.10,.97,.94),warmth);
 ROUGHNESS=mix(.32,.58,smoothstep(40.,240.,distance_to_camera));
 SPECULAR=.24;
}
