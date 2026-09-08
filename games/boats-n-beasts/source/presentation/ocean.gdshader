shader_type canvas_item;
uniform float ocean_time = 0.0;
uniform vec2 projection = vec2(1.0);
uniform vec2 camera = vec2(0.0);
uniform vec2 resolution = vec2(1440.0,900.0);
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) { vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y); }
float terrain(vec2 p) {
    return noise(p)*.57+noise(p*2.07+13.4)*.28+noise(p*4.13-7.8)*.15;
}
void fragment() {
    vec2 world=(UV*resolution-resolution*.5)/projection+camera;
    // Broad underwater forms are fixed in world space; only fine ripples travel.
    vec2 warp=vec2(noise(world*.0017),noise(world*.0017+31.0));
    float depth=terrain(world*.00125+warp*.8);
    vec3 color=mix(vec3(.014,.19,.265),vec3(.025,.30,.36),smoothstep(.18,.82,depth));
    vec2 drift=vec2(ocean_time*.035,-ocean_time*.012);
    vec2 surface=world*vec2(.018,.04)+drift;
    float folds=terrain(surface+vec2(noise(surface*.6),noise(surface*.6+9.0))*.6);
    color+=vec3(.018,.043,.047)*(folds-.5);
    // Thin curved ripple ridges avoid a field of isolated round noise patches.
    float ripple=sin(world.y*.35+world.x*.08+folds*15.0-ocean_time*.65);
    float crest=pow(max(ripple,0.0),18.0)*smoothstep(.60,.76,folds);
    color+=vec3(.05,.10,.105)*crest*.12;
    COLOR=vec4(color,1.0);
}
