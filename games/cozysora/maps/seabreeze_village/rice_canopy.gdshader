shader_type spatial;
render_mode cull_disabled, specular_disabled;
varying vec2 field_position;
void vertex() {
    field_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz;
}
void fragment() {
    float row=0.5+0.5*sin(field_position.y*9.0+sin(field_position.x*0.9)*1.5);
    float patch=0.5+0.5*sin(field_position.x*0.37+2.0)*sin(field_position.y*0.29);
    vec3 light_green=pow(vec3(0.45,0.59,0.21),vec3(2.2));
    vec3 dark_green=pow(vec3(0.34,0.48,0.16),vec3(2.2));
    ALBEDO=mix(mix(light_green,dark_green,row*0.7),light_green*1.04,patch*0.3);
    ROUGHNESS=1.0;
}
void light() {
    float response=dot(NORMAL,LIGHT);
    float band=smoothstep(-0.4,0.15,response)*0.5+smoothstep(0.2,0.7,response)*0.4;
    DIFFUSE_LIGHT+=(band*0.8+0.22)*ATTENUATION*LIGHT_COLOR/PI;
}
