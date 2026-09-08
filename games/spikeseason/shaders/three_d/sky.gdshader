shader_type sky;
uniform vec4 horizon_color=vec4(.70,.84,.88,1);
uniform vec4 zenith_color=vec4(.28,.59,.79,1);
uniform vec4 cloud_color=vec4(1.,.98,.91,1);
uniform float overcast=0.;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 q=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(q),hash(q+vec2(1,0)),f.x),mix(hash(q+vec2(0,1)),hash(q+vec2(1,1)),f.x),f.y);}
float lobe(vec2 p,vec2 at,vec2 radius){return 1.-length((p-at)/radius);}
void sky(){
 vec3 d=normalize(EYEDIR);
 vec3 col=mix(horizon_color.rgb,zenith_color.rgb,smoothstep(-.04,.22,d.y));
 col=mix(col,zenith_color.rgb*.87,smoothstep(.4,.9,d.y));
 vec2 q=vec2(atan(d.x,-d.z),atan(d.y,length(d.xz)));
 float field=-10.; float shade=0.;
 for(int i=-4;i<5;i++){
  float id=float(i);
  vec2 center=vec2(id*.77+.12*sin(id*3.7)+TIME*.0009,.12+.16*hash(vec2(id,3.)));
  vec2 p=q-center;
  float f=lobe(p,vec2(-.10,0),vec2(.23,.055));
  f=max(f,lobe(p,vec2(-.23,.025),vec2(.082,.064)));
  f=max(f,lobe(p,vec2(-.15,.077),vec2(.11,.108)));
  f=max(f,lobe(p,vec2(-.02,.12),vec2(.125,.148)));
  f=max(f,lobe(p,vec2(.095,.075),vec2(.105,.11)));
  f=max(f,lobe(p,vec2(.17,.022),vec2(.09,.071)));
  f+=(noise(q*90.)-.5)*.06+(noise(q*25.)-.5)*.08;
  if(f>field){field=f;shade=(1.-smoothstep(-.03,.15,p.y))*.32+(noise(q*23.)-.5)*.08;}
 }
 float mask=smoothstep(-.012,.012,field)*smoothstep(-.015,.015,d.y);
 vec3 cloud=mix(cloud_color.rgb,cloud_color.rgb*vec3(.68,.75,.87),clamp(shade,0.,.55));
 col=mix(col,cloud,max(mask,overcast));
 COLOR=pow(col,vec3(2.2));
}
