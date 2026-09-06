shader_type spatial;
render_mode specular_disabled;
varying vec3 world;
varying vec3 normal_world;
float hash(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
float noise(vec3 p){vec3 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;normal_world=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 float mottling=noise(world*2.1)*.65+noise(world*7.8)*.35;
 float grain=noise(world*39.);
 vec3 stone=pow(COLOR.rgb,vec3(2.15))*(.84+mottling*.26+grain*.055);
 float moss=smoothstep(.35,.82,normal_world.y)*smoothstep(.35,.78,noise(world*1.7))*smoothstep(.2,1.7,world.y);
 float wet=1.-smoothstep(-.10,.40,world.y);
 ALBEDO=mix(stone,stone*vec3(.67,.78,.49),moss*.44)*(1.-wet*.12);
 ROUGHNESS=.97;
}
