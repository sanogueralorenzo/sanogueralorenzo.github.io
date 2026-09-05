shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform vec4 base_color : source_color = vec4(.19,.34,.25,1.);
uniform bool leaf_cards=false;
uniform sampler2D leaf_texture : filter_linear_mipmap, repeat_disable;
global uniform vec3 cat_position;
varying vec3 world;
varying vec3 tint;
varying vec3 crown_normal;
void vertex(){
 world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
 float weight=leaf_cards?clamp(VERTEX.y+.5,0.,1.):clamp(VERTEX.y*1.6,0.,1.);
 float wind=sin(TIME*1.1+world.x*.22+world.z*.17)+.35*sin(TIME*2.1+world.z*.8);
 VERTEX.x+=wind*.09*weight;VERTEX.z+=cos(TIME*.81+world.x*.16)*.04*weight;
 if(!leaf_cards){vec2 delta=world.xz-cat_position.xz;float d=length(delta);float push=(1.-smoothstep(0.,1.25,d))*weight*step(abs(world.y-cat_position.y),1.5);VERTEX.xz+=delta/max(d,.05)*push*.6;VERTEX.y-=push*.26;}
 tint=COLOR.rgb;crown_normal=normalize((MODELVIEW_MATRIX*vec4(NORMAL,0.)).xyz);
}
void fragment(){
 if(leaf_cards && length(VERTEX)<.8){discard;}
 NORMAL=normalize(crown_normal);
 ALBEDO=base_color.rgb;
 if(leaf_cards){vec4 leaf=texture(leaf_texture,UV);ALBEDO*=leaf.rgb*tint*1.17;ALPHA=leaf.a;ALPHA_SCISSOR_THRESHOLD=.45;}
 else {ALBEDO*=mix(vec3(.62,.77,.68),vec3(1.18,1.12,.83),clamp(UV.y,0.,1.));}
 ROUGHNESS=1.;BACKLIGHT=ALBEDO*.22;
}
void light(){float d=dot(NORMAL,LIGHT);float band=.18+smoothstep(-.4,.18,d)*.48+smoothstep(.18,.75,d)*.37;DIFFUSE_LIGHT+=band*ATTENUATION*LIGHT_COLOR/PI;}
