shader_type spatial;
render_mode cull_disabled;
uniform float clock = 0.0;
uniform vec4 deep_color : source_color = vec4(.027,.16,.22,1.0);
uniform vec4 light_color : source_color = vec4(.039,.22,.27,1.0);
varying vec3 world;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
    vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
float swell(vec2 p) {
    vec2 drift=vec2(clock*.023,-clock*.015);
    float n=noise(p*1.6+drift);
    return noise(p*vec2(5.,9.)+vec2(n*2.0)+drift*3.)*.56+noise(p*vec2(14.,23.)-drift*4.)*.23+noise(p*2.2+drift)*.21;
}
void vertex() { world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
    vec2 p=world.xz;
    float broad=noise(p*.24+vec2(noise(p*.43),noise(p*.37+13.)));
    float ripple=swell(p);
    vec3 deep=mix(deep_color.rgb,light_color.rgb,broad*.72);
    ALBEDO=deep*(.89+ripple*.25);
    ROUGHNESS=.48; SPECULAR=.065; METALLIC=.0;
    float dx=swell(p+vec2(.012,0))-ripple;
    float dz=swell(p+vec2(0,.012))-ripple;
    NORMAL_MAP=normalize(vec3(-dx*1.8,-dz*1.8,1.0))*.5+.5;
    NORMAL_MAP_DEPTH=.8;
}
