shader_type spatial;
render_mode diffuse_burley, cull_disabled;
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float edge=smoothstep(0.20,0.48,abs(UV.x-0.5));
 float current=sin(UV.y*2.9+TIME*4.0+sin(world.x*3.3))*0.5+0.5;
 float ripple=pow(max(0.0,sin(world.z*1.5+world.x*3.1+TIME*3.8)*sin(world.z*0.57-world.x*2.6+TIME*1.8)),12.0);
 float riffle=smoothstep(0.55,0.85,COLOR.r)*pow(current,10.0);
 vec3 deep=vec3(0.026,0.065,0.066);
 vec3 shallows=vec3(0.067,0.086,0.061);
 vec3 water=mix(deep,shallows,edge*0.8);
 ALBEDO=mix(water,vec3(0.30,0.34,0.28),ripple*0.22+riffle*0.22);
 ROUGHNESS=mix(0.39,0.60,edge);METALLIC=0.02;
}
