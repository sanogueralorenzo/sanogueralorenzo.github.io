shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float brush_radius=4.0;
float luma(vec3 c){return dot(c,vec3(.299,.587,.114));}
void fragment(){
 vec2 px=SCREEN_PIXEL_SIZE; vec3 center=texture(screen_texture,SCREEN_UV).rgb;
 // Four overlapping brush regions; retain the region with the calmest colour variance.
 vec3 best=center;float variance=100.;
 for(int region=0;region<4;region++){
  vec2 direction=vec2(region%2==0?-1.:1.,region<2?-1.:1.);
  vec3 mean=vec3(0),square=vec3(0);
  for(int y=0;y<4;y++){for(int x=0;x<4;x++){
   vec3 c=texture(screen_texture,SCREEN_UV+vec2(float(x),float(y))*direction*px*brush_radius/3.).rgb;
   mean+=c;square+=c*c;
  }}
  mean/=16.;float v=dot(abs(square/16.-mean*mean),vec3(1));
  if(v<variance){variance=v;best=mean;}
 }
 vec3 color=mix(center,best,.72);float light=luma(color);
 float green=clamp((color.g-max(color.r,color.b))*5.,0.,1.);
 color=mix(vec3(light),color,.86-.22*green);
 color+=pow(1.-light,2.)*vec3(-.015,.025,.085)+light*light*vec3(.025,.015,-.016);
 color=mix(color,color*color*(3.-2.*color),.35);
 vec2 q=SCREEN_UV-.5;color*=1.-dot(q,q)*.2;
 COLOR=vec4(color,1.);
}
