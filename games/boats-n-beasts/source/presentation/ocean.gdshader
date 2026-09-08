shader_type canvas_item;
uniform float ocean_time = 0.0;
uniform vec2 projection = vec2(1.0);
uniform vec2 camera = vec2(0.0);
uniform vec2 resolution = vec2(1440.0,900.0);
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) { vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y); }
void fragment() {
    vec2 world=(UV*resolution-resolution*.5)/projection+camera;
    // World-anchored depth fields stay still while the surface moves above them.
    float depth=noise(world*.0013)*.8+noise(world*.003)*.2;
    float bands=floor(depth*9.0)/9.0;
    vec3 color=mix(vec3(.018,.17,.25),vec3(.028,.30,.365),bands);
    float surface=noise(world*vec2(.012,.028)+vec2(ocean_time*.04,-ocean_time*.02));
    color+=vec3(.015,.036,.039)*(surface-.5);
    float crest=smoothstep(.73,.82,noise(world*vec2(.022,.06)+vec2(-ocean_time*.025,ocean_time*.035)));
    color+=vec3(.025,.06,.065)*crest*.22;
    COLOR=vec4(color,1.0);
}
