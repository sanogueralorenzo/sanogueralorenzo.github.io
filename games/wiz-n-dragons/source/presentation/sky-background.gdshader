shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float clock=0.0;
uniform vec2 camera_offset=vec2(0.0);
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void fragment(){
    vec2 p=(UV-.5)*24.0+camera_offset*.12+vec2(clock*.002,clock*.001);
    float n=noise(p)*.55+noise(p*2.0)*.28+noise(p*4.0)*.12;
    ALBEDO=mix(vec3(.035,.09,.14),vec3(.10,.23,.28),smoothstep(.2,.8,n));
}
