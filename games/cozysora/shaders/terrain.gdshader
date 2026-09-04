shader_type spatial;
render_mode diffuse_toon, specular_disabled;
uniform sampler2D layout_map : filter_linear, repeat_disable;
varying vec3 world_pos;
float hash(vec2 p) {return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p) {vec2 f=fract(p);vec2 i=floor(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
float fbm(vec2 p) {return noise(p)*.53+noise(p*2.07)*.27+noise(p*4.28)*.13+noise(p*8.86)*.07;}
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;}
void fragment(){
 vec2 p=world_pos.xz;vec4 layout=texture(layout_map,(p+180.)/360.);
 float distance=layout.r*16.;float kind=layout.b;float coarse=fbm(p*.35);float fine=fbm(p*1.4+11.);
 float patch=smoothstep(.42,.50,coarse)*.6+smoothstep(.45,.55,fine)*.4;
 vec3 ground=mix(vec3(.30,.40,.17),vec3(.40,.50,.20),patch);
 ground=mix(ground,vec3(.22,.31,.14),smoothstep(.55,.62,fbm(p*.6+5.))*.7);
 if(kind>.1 && kind<.3) ground=mix(vec3(.27,.36,.25),vec3(.38,.47,.34),fine);
 if(kind>.3 && kind<.5){ground=mix(vec3(.6,.58,.54),vec3(.52,.50,.47),fine);vec2 tile=abs(fract(p/4.)-.5);ground*=1.-(1.-smoothstep(0.,.012,min(tile.x,tile.y)*4.))*.25;}
 if(kind>.5 && kind<.7) ground=mix(vec3(.48,.42,.32),vec3(.58,.52,.42),fine);
 if(kind>.7) ground=mix(vec3(.4,.38,.35),vec3(.58,.55,.50),smoothstep(.35,.7,noise(p*9.)));
 float zr=p.y-(-.0022*p.x*p.x+.00001*p.x*p.x*p.x);
 float dirt=smoothstep(-10.5,-8.2,p.x)*(1.-smoothstep(-4.4,-1.8,p.x))*(1.-smoothstep(6.,8.5,zr))*smoothstep(-8.9,-8.2,zr);
 vec3 soil=mix(vec3(.24,.21,.18),vec3(.38,.32,.26),smoothstep(.4,.6,fine));
 soil=mix(soil,vec3(.50,.42,.34),smoothstep(.5,.6,fbm(p*.55+21.))*.55);
 soil=mix(soil,vec3(.52,.44,.36),smoothstep(.5,.56,fbm(p*.18+7.))*.7);
 soil*=.94+.12*smoothstep(.35,.65,noise(p*14.));
 soil=mix(vec3(.32,.29,.27),soil,.35);
 ground=mix(ground,soil,dirt);
 float shoulder=(1.-smoothstep(0.,.9,abs(distance-4.)));
 ground=mix(ground,vec3(.44,.39,.32),shoulder*.7);
 vec3 asphalt=mix(vec3(.40,.36,.33),vec3(.48,.43,.39),smoothstep(.45,.6,fbm(p*.5+40.))*.7+noise(p*6.)*.12);
 float edge=1.-smoothstep(.055,.13,abs(distance-3.65));
 float center=(1.-smoothstep(.04,.10,distance))*step(.45,layout.g);
 float wear=smoothstep(.3,.55,fbm(p*2.5+9.));
 asphalt=mix(asphalt,vec3(.80,.79,.74),clamp(edge+center,0.,1.)*wear);
 ground=mix(ground,asphalt,1.-smoothstep(3.85,4.15,distance));
 if(world_pos.y< -2.) ground=mix(ground,vec3(.24,.22,.20)*(.7+.5*patch),smoothstep(2.,8.,-world_pos.y));
 ALBEDO=pow(ground,vec3(2.2));ROUGHNESS=1.;
}
