shader_type canvas_item;
uniform float radius=150.0;
uniform float phase=0.0;
varying vec2 ground;
void vertex(){ground=VERTEX/radius;}
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void fragment(){
    vec2 p=vec2(ground.x,ground.y/.83);
    float angle=atan(p.y,p.x);
    float beach=.9+.1*cos(angle*3.0+phase)+.04*sin(angle*5.0-phase);
    float width=.56+.17*sin(angle*2.0+phase)+.10*cos(angle*5.0-phase);
    float texture=noise(ground*9.0+phase)*.65+noise(ground*23.0-phase)*.35;
    float depth=(length(p)-beach)/width+(texture-.5)*.19;
    float terrace=floor(max(depth,0.0)*5.0)/5.0;
    float shade=mix(max(depth,0.0),terrace,.38);
    vec3 color=mix(vec3(.075,.43,.425),vec3(.018,.23,.30),clamp(shade,0.0,1.0));
    color+=vec3(.012,.025,.024)*(texture-.5);
    float alpha=(1.0-smoothstep(.65,1.0,depth))*.85*(1.0-clamp(depth,0.0,1.0)*.5);
    COLOR=vec4(color,alpha);
}
