shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled;
uniform float clock = 0.0;
uniform int whirlpool_count = 0;
uniform vec4 whirlpools[32];
varying vec3 world;
vec3 linear_color(vec3 c) { return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c)); }
float hash(vec2 cell) { return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453); }

float field(vec2 point) {
    vec2 cell = floor(point);
    vec2 f = fract(point);
    f = f*f*(3.0-2.0*f);
    float row_a = mix(hash(cell), hash(cell + vec2(1.0,0.0)), f.x);
    float row_b = mix(hash(cell + vec2(0.0,1.0)), hash(cell + vec2(1.0,1.0)), f.x);
    return mix(row_a, row_b, f.y);
}

float stroke(vec2 p, float span, float width, float bend, float aa) {
    float u = p.x / span;
    float ridge = bend * (1.0 - abs(u + .28) * 1.47) + u * bend * .27;
    float edge = max(abs(p.y - ridge) - width * (1.0 - abs(u)), abs(p.x) - span);
    return 1.0 - smoothstep(-aa, aa, edge);
}

void vertex() { world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
    for (int i = 0; i < whirlpool_count; i++) {
        if (distance(world.xz, whirlpools[i].xy) < whirlpools[i].z) discard;
    }
    vec2 water = world.xz + vec2(.035,-.021)*clock;
    float broad = field(water*.107);
    float pockets = field(vec2(water.x*.14 - water.y*.11, water.x*.11 + water.y*.14) + 17.3);
    float tone = smoothstep(.14,.86,mix(broad,pockets,.27));
    vec3 color = mix(vec3(.012,.425,.493), vec3(.021,.510,.557), tone);
    vec2 axis = vec2(.97,-.24);
    vec2 tile = vec2(dot(world.xz, axis), dot(world.xz, vec2(-axis.y, axis.x))) / vec2(2.9, 2.4);
    float aa = max(fwidth(tile.y) * 1.44, .006);
    vec2 cell = floor(tile);
    float seed = hash(cell);
    float length_seed = hash(cell + 23.7);
    float span = mix(.16,.65,length_seed*length_seed);
    float margin = (span + .17) / 2.9;
    vec2 center = vec2(mix(margin,1.0-margin,hash(cell + 8.4)), mix(.15,.85,hash(cell + 17.3)));
    vec2 p = (fract(tile) - center) * vec2(2.9, 2.4);
    p.x -= .12 * sin(clock*.35 + seed*6.283);
    p.y += .055 * sin(clock*.61 + seed*6.283) + p.x * (hash(cell + 40.2)-.5)*.33;
    float width = mix(.018,.050,hash(cell + 9.7));
    float glint = stroke(p, span, width, mix(-.065,.10,seed), aa);
    vec2 companion = vec2(-span*.44,mix(.095,.14,seed));
    glint = max(glint, stroke(p - companion, span*.50, width*.52, -.04, aa) * step(.93,seed));
    float threshold = mix(.50,.23,tone);
    float presence = smoothstep(threshold-.07,threshold+.07,seed);
    float ivory = smoothstep(.47,.80,hash(cell + 31.6));
    vec3 reflection = mix(vec3(.28,.67,.67),vec3(.97,.96,.88),ivory);
    float shimmer = mix(.76,1.0,.5+.5*sin(clock*.52+seed*9.0));
    ALBEDO = linear_color(mix(color, reflection, glint * presence * shimmer * mix(.62,1.0,ivory)));
}

void light() {
    DIFFUSE_LIGHT += mix(vec3(.82,.82,.91), vec3(1.0), ATTENUATION);
}
