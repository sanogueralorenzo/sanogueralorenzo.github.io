shader_type spatial;
render_mode specular_disabled;
void fragment(){
 vec3 n=normalize(VERTEX);
 float panel=fract(UV.x*6.+sin(UV.y*3.14159)*.65);
 float band=mod(floor(UV.x*6.+sin(UV.y*3.14159)*.65),3.);
 vec3 col=band<.5?vec3(.91,.66,.19):(band<1.5?vec3(.96,.92,.79):vec3(.10,.24,.30));
 float seam=1.-smoothstep(.008,.025,min(panel,1.-panel));
 ALBEDO=mix(col,vec3(.12,.18,.19),seam*.75);
 ROUGHNESS=.85;
}
