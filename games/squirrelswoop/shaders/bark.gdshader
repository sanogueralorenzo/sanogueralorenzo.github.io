shader_type spatial;
render_mode diffuse_burley, specular_disabled;
varying vec3 local;
float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float n(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+1.0),f.x),f.y);}
void vertex(){local=VERTEX;}
void fragment(){
 float angle=atan(local.z,local.x);
 vec2 p=vec2(angle*9.0,local.y*0.8);
 p.x+=n(p*vec2(.32,.6))*0.85;
 float plates=n(p*vec2(1.6,.55));
 float cracks=smoothstep(.30,.42,n(p*vec2(2.5,.48)+n(p)*.4));
 float chip=n(p*vec2(7.0,3.0));
 vec3 wood=mix(vec3(.25,.18,.11),vec3(.52,.39,.25),plates);
 wood*=mix(.65,1.0,cracks)*(.87+chip*.22);
 float moss=(1.0-smoothstep(.5,6.0,local.y))*smoothstep(.37,.68,n(local.xz*2.4+local.y*.5));
 wood=mix(wood,mix(vec3(.15,.22,.08),vec3(.32,.36,.13),chip),moss*.85);
 ALBEDO=pow(wood,vec3(2.2));ROUGHNESS=1.0;
}
