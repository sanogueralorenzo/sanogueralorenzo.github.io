shader_type spatial;
render_mode cull_disabled, diffuse_lambert;
uniform float clock = 0.0;
uniform int whirlpool_count = 0;
uniform vec4 whirlpools[32];
varying vec3 world;
vec3 linear_color(vec3 c) { return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c)); }
void vertex() { world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
    for (int i = 0; i < whirlpool_count; i++) {
        if (distance(world.xz, whirlpools[i].xy) < whirlpools[i].z) discard;
    }
    // Broad, nearly still color fields keep moving silhouettes and shots readable.
    float swell=sin(world.x*.19+world.z*.13+clock*.018)*sin(world.z*.23-world.x*.08);
    ALBEDO=linear_color(mix(vec3(.025,.39,.47),vec3(.035,.43,.50),swell*.5+.5));
    ROUGHNESS=1.0; SPECULAR=0.0;
}
