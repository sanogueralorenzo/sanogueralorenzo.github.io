shader_type spatial;
render_mode specular_disabled;
uniform vec4 gold : source_color = vec4(.91,.66,.19,1.);
uniform vec4 cream : source_color = vec4(.96,.92,.79,1.);
uniform vec4 teal : source_color = vec4(.10,.24,.30,1.);
uniform vec4 stitching : source_color = vec4(.12,.18,.19,1.);
void fragment(){
 float panel=fract(UV.x*6.+sin(UV.y*3.14159)*.65);
 float band=mod(floor(UV.x*6.+sin(UV.y*3.14159)*.65),3.);
 vec3 col=band<.5?gold.rgb:(band<1.5?cream.rgb:teal.rgb);
 float seam=1.-smoothstep(.008,.025,min(panel,1.-panel));
 ALBEDO=mix(col,stitching.rgb,seam*.75);
 ROUGHNESS=.85;
}
