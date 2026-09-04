shader_type spatial;
render_mode unshaded, fog_disabled;
varying vec3 world_pos;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 f=fract(p),i=floor(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;}
void fragment(){vec2 p=world_pos.xz;float dist=length(world_pos-CAMERA_POSITION_WORLD);
float streak=noise(vec2(p.x*.02,p.y*.16)+vec2(TIME*.03,0))*.67+noise(vec2(p.x*.05,p.y*.4)+vec2(-TIME*.05,TIME*.01))*.33;
vec3 color=mix(vec3(.22,.42,.62),vec3(.30,.50,.68),smoothstep(.48,.56,streak));
color=mix(color,vec3(.36,.53,.68),smoothstep(30.,600.,dist));
vec3 normal=normalize(vec3((noise(p*.8+TIME*.4)-.5)*.35,1.,(noise(p*.8-TIME*.3+3.)-.5)*.35));
vec3 reflected=reflect(normalize(world_pos-CAMERA_POSITION_WORLD),normal);
float specular=pow(max(dot(reflected,normalize(vec3(-.55,.7,-.38))),0.),220.);
float glint=step(.5,specular*(.6+noise(p*3.+TIME)));color+=vec3(1.,.97,.9)*glint*.8*(1.-smoothstep(30.,600.,dist)*.7);
color=mix(color,vec3(.78,.80,.81),smoothstep(250.,1700.,dist));ALBEDO=pow(color,vec3(2.2));}
