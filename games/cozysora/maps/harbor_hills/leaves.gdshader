shader_type spatial;
render_mode cull_disabled;
uniform vec4 base_color : source_color = vec4(.19,.34,.25,1.);
uniform bool leaf_cards=false;
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;VERTEX.x+=sin(TIME*.85+world.x*.22+world.z*.17)*.045*max(0.,VERTEX.y+.5);VERTEX.z+=cos(TIME*.61+world.x*.16)*.025;}
void fragment(){float mottled=sin(world.x*16.+sin(world.z*19.))*sin(world.y*17.+world.z*7.);ALBEDO=base_color.rgb*(1.+mottled*.16);ROUGHNESS=1.;if(leaf_cards){vec2 q=UV*2.-1.;ALBEDO*=COLOR.rgb;ALPHA=1.-smoothstep(.7,1.,dot(q,q));ALPHA_SCISSOR_THRESHOLD=.5;}}
