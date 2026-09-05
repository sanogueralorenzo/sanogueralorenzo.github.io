shader_type spatial;
render_mode specular_disabled;
varying vec3 world;
float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+vec2(1,1)),f.x),f.y);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;}
void fragment(){float patch=noise(world.xz*.16)*.65+noise(world.xz*.52)*.35;float grain=h(floor(world.xz*9.));vec3 grass=mix(vec3(.36,.44,.23),vec3(.46,.50,.28),patch);ALBEDO=pow(grass,vec3(2.2))*(.93+grain*.1);ROUGHNESS=1.;}
