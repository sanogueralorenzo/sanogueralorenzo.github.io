shader_type spatial;
render_mode diffuse_burley, cull_disabled;
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float ripple=pow(max(0.0,sin(world.z*2.0+world.x*3.5+TIME*4.5)*sin(world.z*0.7-world.x*4.0+TIME*2.0)),8.0);
 ALBEDO=mix(vec3(0.09,0.25,0.26),vec3(0.61,0.73,0.62),ripple*0.75);
 ROUGHNESS=0.26;METALLIC=0.25;
}
