shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shared/surface_noise.gdshaderinc"
uniform sampler2D layout_map : filter_linear, repeat_disable;
varying vec3 world_pos;
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
 float road = 1.0 - smoothstep(3.85, 4.15, distance);
 float wheel_track = 1.0 - smoothstep(0.16, 0.56, abs(abs(distance - 1.95) - 0.69));
 float stone = noise(p * 64.0);
 float grit = noise(p * 22.0 + 9.0);
 float weathering = fbm(p * 0.68);
 vec3 asphalt = mix(vec3(0.235, 0.245, 0.25), vec3(0.365, 0.36, 0.342), weathering);
 asphalt += vec3((grit - 0.5) * 0.105 + (stone - 0.5) * 0.18);
 float fracture = abs(noise(p * 0.72 + vec2(noise(p * 3.1), noise(p * 2.8 + 17.0)) * 0.15) - 0.5);
 float crack = (1.0 - smoothstep(0.002, max(0.012, fwidth(fracture)), fracture))
     * smoothstep(0.5, 0.67, noise(p * 0.53 + 13.0));
 asphalt *= 1.0 - crack * 0.4 - wheel_track * 0.08;
 float wet = smoothstep(0.575, 0.70, weathering + 0.03 * wheel_track + 0.07 * smoothstep(2.9, 3.9, distance));
 float edge = 1.0 - smoothstep(0.055, 0.13, abs(distance - 3.65));
 float center = (1.0 - smoothstep(0.055, 0.12, distance)) * step(0.45, layout.g);
 float paint = clamp(edge + center, 0.0, 1.0) * smoothstep(0.19, 0.57, 0.5 * grit + 0.5 * weathering);
 asphalt = mix(asphalt, vec3(0.79, 0.79, 0.73) * (0.90 + 0.20 * grit), paint);
 ground = mix(ground, asphalt * (1.0 - wet * 0.28), road);
 if(world_pos.y< -2.) ground=mix(ground,vec3(.24,.22,.20)*(.7+.5*patch),smoothstep(2.,8.,-world_pos.y));
 ALBEDO = pow(ground, vec3(2.2));
 float height = road * (grit * 0.0026 + stone * 0.0009 - crack * 0.0028) * (1.0 - wet * 0.84);
 NORMAL = relief_normal(VERTEX, NORMAL, height);
 ROUGHNESS = mix(0.96, mix(0.84, 0.18, wet), road);
 SPECULAR = mix(0.24, 0.35, wet * road);
}
