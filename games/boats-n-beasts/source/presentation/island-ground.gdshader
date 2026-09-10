shader_type spatial;
render_mode cull_disabled, diffuse_lambert;
varying vec2 ground;

vec3 linear_color(vec3 c) { return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c)); }
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
    vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { ground=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz; }
void fragment() {
    // UV.x begins behind the protected beach. Warped broad patches let sand
    // reach inland between grass tongues while retaining a clear coastal strip.
    vec2 warp=vec2(noise(ground*.55),noise(ground.yx*.55+13.0))-.5;
    float broad=noise(ground*(.70/(.50+UV.y))+warp*1.2);
    float detail=noise(ground*3.5);
    float inset=max(0.0,.16+(broad-.5)*1.65+(detail-.5)*.16);
    float distance=max(0.0,UV.x-UV.y*inset);
    float blend=smoothstep(0.0,UV.y*(.75+broad*.45),distance);
    vec3 sand=vec3(.929,.808,.561);
    vec3 dry_grass=vec3(.68,.70,.40);
    vec3 grass=mix(vec3(.43,.55,.28),vec3(.49,.59,.31),noise(ground*.72+warp));
    vec3 color=mix(sand,dry_grass,blend);
    color=mix(color,grass,blend*blend);
    color+=(detail-.5)*.018*blend;
    ALBEDO=linear_color(color);
    ROUGHNESS=1.0;
    SPECULAR=0.0;
}
