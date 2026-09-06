shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float brush_radius=0.9;
void fragment(){
 vec3 center=texture(screen_texture,SCREEN_UV).rgb;
 // A small edge-preserving brush replaces the original64-fetch filter. Geometry,
 // light and material detail provide the scene; this only calms subpixel texture.
 vec3 sum=center*2.0;
 float total=2.0;
 for(int y=-1;y<=1;y++){
  for(int x=-1;x<=1;x++){
   vec3 sample_color=texture(screen_texture,SCREEN_UV+vec2(float(x),float(y))*SCREEN_PIXEL_SIZE*brush_radius).rgb;
   vec3 difference=sample_color-center;
   float weight=1.0/(1.0+dot(difference,difference)*90.0);
   sum+=sample_color*weight;total+=weight;
  }
 }
 vec3 color=mix(center,sum/total,0.28);
 float light=dot(color,vec3(.299,.587,.114));
 color+=pow(1.-light,2.)*vec3(.006,.011,.019);
 vec2 q=SCREEN_UV-.5;color*=1.-dot(q,q)*.10;
 COLOR=vec4(color,1.);
}
