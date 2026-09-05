shader_type spatial;
render_mode diffuse_burley, specular_disabled;
uniform vec4 tint:source_color=vec4(.65,.65,.55,1.);
uniform int finish=0;
varying vec3 world;
varying vec3 local_normal;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;local_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 vec2 p=abs(local_normal.y)>.6?world.xz:(abs(local_normal.x)>.6?world.zy:world.xy);
 float mark=.96+hash(floor(p*12.))*.08;
 if(finish==1){vec2 tile=fract(p*1.3);mark*=mix(.82,1.,step(.035,min(tile.x,tile.y)));}
 if(finish==2){vec2 tile=fract(p*5.);mark*=mix(.68,1.,step(.055,min(tile.x,tile.y)));mark*=.92+hash(floor(p*5.))*.14;}
 if(finish==3){mark*=.97+.025*sin(p.x*35.+sin(p.y*3.)*.6);}
 if(finish==4){float groove=sin(p.x*31.+sin(p.y*1.8)*.9);mark*=.84+.16*smoothstep(-.6,.3,groove);}
 ALBEDO=tint.rgb*mark;ROUGHNESS=.92;
}
