shader_type canvas_item;
uniform float ocean_time = 0.0;
uniform vec2 projection = vec2(1.0);
uniform vec2 camera = vec2(0.0);
uniform vec2 resolution = vec2(1440.0,900.0);
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) { vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y); }
void fragment() {
    vec2 world=(UV*resolution-resolution*.5)/projection+camera;
    float broad=noise(world*.002+vec2(ocean_time*.008,0.0));
    float current=noise(world*.005-vec2(ocean_time*.012,ocean_time*.004));
    vec3 deep=vec3(.025,.19,.265), shallow=vec3(.04,.28,.35);
    vec3 color=mix(deep,shallow,.22+broad*.52+current*.12);
    COLOR=vec4(color,1.0);
}
