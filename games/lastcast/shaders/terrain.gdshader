shader_type spatial;
render_mode cull_disabled, specular_disabled;
varying vec3 world;
varying vec3 face;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;face=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 float patch=noise(world.xz*.36)*.7+noise(world.xz*1.3)*.3;
 float rock=1.-smoothstep(.48,.88,abs(face.y));
 vec3 turf=mix(vec3(.145,.177,.090),vec3(.235,.246,.139),patch);
 ALBEDO=mix(turf,vec3(.32,.315,.247),rock*.8)*(0.96+noise(world.xz*19.)*.07);
 ROUGHNESS=1.;
}
