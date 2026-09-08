shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;
uniform vec4 skin_color : source_color = vec4(.86,.64,.46,1.);
void fragment(){ ALBEDO=skin_color.rgb; ROUGHNESS=1.; }
void light(){
 float facing=dot(NORMAL,LIGHT);
 // Broad painted light planes preserve the sculpted jaw and limb volumes.
 float plane=.28+.43*smoothstep(-.08,.24,facing)+.29*smoothstep(.48,.82,facing);
 vec3 temperature=mix(vec3(.72,.76,.88),vec3(1.08,1.025,.94),smoothstep(.05,.64,facing));
 DIFFUSE_LIGHT+=ALBEDO*temperature*LIGHT_COLOR*ATTENUATION*plane/3.14159265;
}
