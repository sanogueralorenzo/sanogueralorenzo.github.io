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
    // UV.x is distance behind the protected beach; UV.y scales diffusion with
    // island size. Only push grass inland, preserving the clear strip of sand.
    float broad=noise(ground*1.25);
    float detail=noise(ground*5.0);
    float distance=max(0.0,UV.x-UV.y*(broad*.22+detail*.06));
    float blend=smoothstep(0.0,UV.y*(.85+broad*.55),distance);
    vec3 sand=vec3(.929,.808,.561);
    vec3 dry_grass=vec3(.68,.70,.40);
    vec3 grass=vec3(.459,.576,.290);
    vec3 color=mix(sand,dry_grass,smoothstep(0.0,.70,blend));
    color=mix(color,grass,smoothstep(.20,1.0,blend));
    // Restrained mottling through the transition, without a speckled outline.
    color+=(detail-.5)*.025*4.0*blend*(1.0-blend);
    ALBEDO=linear_color(color);
    ROUGHNESS=1.0;
    SPECULAR=0.0;
}
