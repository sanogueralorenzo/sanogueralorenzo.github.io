shader_type spatial;
varying vec3 world;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){vec2 p=world.xz*vec2(3.8,4.1);vec2 f=fract(p);float seam=smoothstep(.89,.99,f.y);float channel=pow(abs(sin(f.x*3.14159)),.6);float variation=hash(floor(p));vec3 tile=mix(vec3(.46,.20,.115),vec3(.61,.30,.18),variation);ALBEDO=pow(tile,vec3(1.55))*(.80+channel*.23)*(1.0-seam*.17);ROUGHNESS=.94;}
