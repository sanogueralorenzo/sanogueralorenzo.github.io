shader_type spatial;
render_mode cull_disabled, specular_disabled;
varying float blade_height;
void vertex() {
    blade_height=VERTEX.y;
    vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    float bend=VERTEX.y*VERTEX.y;
    VERTEX.x+=sin(TIME*1.4+world.x*.5+world.z*.3)*bend*.16;
}
void fragment() {
    float dither=fract(sin(dot(FRAGCOORD.xy,vec2(12.9898,78.233)))*43758.5453);
    if(length(VERTEX)>6.5+5.0*dither) { discard; }
    NORMAL=normalize(mix(NORMAL,(VIEW_MATRIX*vec4(0,1,0,0)).xyz,.3));
    vec3 base=pow(vec3(.46,.62,.21),vec3(2.2));
    vec3 tip=pow(vec3(.69,.83,.36),vec3(2.2));
    ALBEDO=mix(base,tip,smoothstep(.1,1.0,blade_height));
    ROUGHNESS=.9;
}
void light() {
    float response=dot(NORMAL,LIGHT);
    float band=smoothstep(-.4,.15,response)*.5+smoothstep(.2,.7,response)*.4;
    DIFFUSE_LIGHT+=(band+.22)*ATTENUATION*LIGHT_COLOR/PI;
}
