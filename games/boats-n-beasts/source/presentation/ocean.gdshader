shader_type canvas_item;
uniform float ocean_time = 0.0;
uniform vec2 camera = vec2(0.0);
uniform vec2 resolution = vec2(1440.0,900.0);
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) { vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y); }
void fragment() {
    vec2 world=UV*resolution+camera-resolution*.5;
    float n=noise(world*.002+vec2(ocean_time*.025,0.0));
    float detail=noise(world*.009-vec2(ocean_time*.04,ocean_time*.013));
    vec3 deep=vec3(.018,.16,.48), cobalt=vec3(.025,.24,.64);
    vec3 color=mix(deep,cobalt,.48+n*.38+detail*.10);
    float shimmer=sin(world.x*.019+world.y*.08+ocean_time*.7+detail*9.0);
    color+=vec3(.0,.018,.02)*smoothstep(.9,1.0,shimmer)*smoothstep(.5,.9,detail);
    COLOR=vec4(color,1.0);
}
