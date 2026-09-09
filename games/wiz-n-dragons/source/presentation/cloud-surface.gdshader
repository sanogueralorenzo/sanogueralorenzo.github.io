shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 shadow_tint : source_color = vec3(.31,.36,.49);
uniform vec3 body_tint : source_color = vec3(.65,.76,.80);
uniform vec3 pearl_tint : source_color = vec3(.95,.89,.76);
uniform float distance_haze = 0.0;
varying vec3 local_normal;
varying vec3 local_position;
void vertex() { local_normal=NORMAL; local_position=VERTEX; }
void fragment() {
    vec3 n=normalize(local_normal);
    float light=dot(n,normalize(vec3(-.45,.8,-.4)))*.5+.5;
    float crown=smoothstep(-.3,1.3,local_position.y);
    vec3 color=mix(shadow_tint,body_tint,smoothstep(.12,.78,light));
    color=mix(color,pearl_tint,smoothstep(.72,.98,light)*(.25+crown*.45));
    // A broad painted curl, deliberately subtle at gameplay scale.
    vec2 q=local_position.xz-vec2(-.55,-.03);
    float r=length(q),angle=atan(q.y,q.x);
    float curl=pow(.5+.5*cos(angle+r*8.0),10.0)*(1.0-smoothstep(.25,.9,r));
    color*=1.0-curl*.035*crown;
    ALBEDO=mix(color,vec3(.065,.13,.18),distance_haze);
}
