shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 wave_shape[24];
uniform vec3 wave_phase[24];
uniform float water_time=0.;
uniform bool ocean_surface=true;
uniform sampler2D bathymetry : filter_linear, repeat_disable;
uniform vec4 depth_bounds;
uniform vec4 water_bounds;
uniform vec4 deep_color : source_color = vec4(.094,.286,.435,1.);
uniform vec4 scatter_color : source_color = vec4(.16,.46,.49,1.);
uniform sampler2D shore_distance : filter_linear, repeat_disable;
uniform sampler2D surface_field : filter_linear_mipmap, repeat_enable;
uniform float shore_width=2.4;
uniform vec4 shore_color : source_color = vec4(.443,.537,.522,1.);
uniform vec4 fog_color : source_color;
uniform vec4 fog_range=vec4(40.,260.,1.,1.);
uniform vec3 absorption=vec3(.56,.185,.072);
uniform vec3 sun_direction=vec3(-.55,.7,-.38);
uniform float wind=.3;
uniform float ripple_strength=1.;
uniform float roughness=.155;
uniform float optical_depth_min=1.65;
uniform float shore_damping=2.;
uniform float foam_strength=.4;
uniform float wave_height_max=1.;
varying vec3 water_world;
varying vec3 water_normal;
varying float crest;
varying float specular_visibility;
varying vec2 wave_parameter;
varying vec2 mesh_center;

float depth_at(vec2 p) {
 vec2 uv=(p-depth_bounds.xy)/depth_bounds.zw;
 if(any(lessThan(uv,vec2(0.))) || any(greaterThan(uv,vec2(1.)))) return ocean_surface?48.:-1.;
 float depth=texture(bathymetry,(uv*256.+.5)/257.).r;
 // Fade to open-sea depth before the generated field ends, including its corners.
 float edge=min(min(uv.x,uv.y),min(1.-uv.x,1.-uv.y));
 return ocean_surface?mix(48.,depth,smoothstep(0.,.18,edge)):depth;
}
float shore_at(vec2 p) {
 vec2 uv=(p-depth_bounds.xy)/depth_bounds.zw;
 float distance_to_shore=32.;
 if(all(greaterThanEqual(uv,vec2(0.))) && all(lessThanEqual(uv,vec2(1.)))) {
  distance_to_shore=texture(shore_distance,(uv*256.+.5)/257.).r;
  float edge=min(min(uv.x,uv.y),min(1.-uv.x,1.-uv.y));
  if(ocean_surface) distance_to_shore=mix(32.,distance_to_shore,smoothstep(0.,.18,edge));
 }
 if(!ocean_surface) distance_to_shore=min(distance_to_shore,min(min(p.x-water_bounds.x,p.y-water_bounds.y),min(water_bounds.z-p.x,water_bounds.w-p.y)));
 return max(0.,distance_to_shore);
}
float spectral_spacing(float distance_to_center) {
 float s=mix(1.125,4.9,smoothstep(108.,210.,distance_to_center));
 s=mix(s,14.6,smoothstep(210.,520.,distance_to_center));
 s=mix(s,37.,smoothstep(520.,1150.,distance_to_center));
 return mix(s,105.,smoothstep(1150.,2920.,distance_to_center));
}
void sample_waves(vec2 p,float radius,out float height,out vec2 slope,out vec2 displacement) {
 float far_blend=ocean_surface?smoothstep(116.,232.,radius):0.;
 float spacing=spectral_spacing(radius);
 height=0.; slope=vec2(0.); displacement=vec2(0.);
 for(int i=0;i<24;i++) {
  vec4 w=wave_shape[i]; vec3 ph=wave_phase[i];
  float visible=mix(1.,max(.035,smoothstep(spacing*1.12,spacing*3.05,6.2831853/ph.x)),far_blend);
  float phase=dot(w.xy,p)*ph.x-water_time*ph.y+ph.z;
  float amplitude=w.z*visible;
  height+=amplitude*sin(phase);
  slope+=amplitude*ph.x*w.xy*cos(phase);
  displacement+=w.w*amplitude*w.xy*cos(phase);
 }
}
void vertex() {
 vec3 base=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
 float radius=max(abs(VERTEX.x),abs(VERTEX.z));
 float damping=smoothstep(0.,shore_damping,max(0.,depth_at(base.xz)));
 vec2 texel=depth_bounds.zw/256.;
 vec2 damp_gradient=vec2(
   smoothstep(0.,shore_damping,max(0.,depth_at(base.xz+vec2(texel.x,0.))))-smoothstep(0.,shore_damping,max(0.,depth_at(base.xz-vec2(texel.x,0.)))),
   smoothstep(0.,shore_damping,max(0.,depth_at(base.xz+vec2(0.,texel.y))))-smoothstep(0.,shore_damping,max(0.,depth_at(base.xz-vec2(0.,texel.y)))))/(2.*texel);
 float height; vec2 slope,displacement;
 sample_waves(base.xz,radius,height,slope,displacement);
 wave_parameter=base.xz;
 mesh_center=MODEL_MATRIX[3].xz;
 VERTEX.xz+=displacement*damping;
 VERTEX.y+=height*damping;
 water_world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
 water_normal=normalize(vec3(-(slope*damping+height*damp_gradient).x,1.,-(slope*damping+height*damp_gradient).y));
 crest=height/max(wave_height_max,.001);
}
void fragment() {
 vec2 p=water_world.xz;
 float footprint=max(length(dFdx(p)),length(dFdy(p)));
 float depth=depth_at(p);
 if(p.x<water_bounds.x || p.y<water_bounds.y || p.x>water_bounds.z || p.y>water_bounds.w || depth<=.002) discard;
 // Slow world-space wind patches leave resting water between fine ripples.
 float gust=texture(surface_field,p/96.+water_time*vec2(-.00048,.00019)).r;
 float breeze=mix(.38,1.08,smoothstep(.25,.73,gust));
 float shore_distance_m=shore_at(p);
 float shoreline_noise=texture(surface_field,p/14.).g;
 float shore=1.-smoothstep(0.,shore_width*mix(.72,1.24,shoreline_noise),shore_distance_m);
 vec2 slope=vec2(0.);
 for(int octave=0;octave<6;octave++) {
  float band=float(octave),angle=.42+band*2.3999632;
  vec2 direction=vec2(cos(angle),sin(angle));
  float wavelength=2.7*exp2(-band*.87), k=6.2831853/wavelength;
  float frequency=sqrt(9.80665*k+.000074*k*k*k);
  // Advect capillary crests across the flow as well as along it. Analytic
  // phase gradients bend the reflected highlights into short crossing arcs.
  vec2 cross_direction=vec2(-direction.y,direction.x);
  float cross_phase=dot(p,cross_direction)*k*.28+water_time*.17+band*1.7;
  float along_phase=dot(p,direction)*k*.19-water_time*.13+band*.9;
  float phase=dot(p,direction)*k-frequency*water_time*(.62+wind*.23)+band*1.732
    +1.35*sin(cross_phase)+.65*sin(along_phase);
  vec2 phase_gradient=direction*(1.+.1235*cos(along_phase))+cross_direction*.378*cos(cross_phase);
  float resolved=1.-smoothstep(wavelength*.2,wavelength*.92,footprint);
  slope+=phase_gradient*cos(phase)*(.73+.27*sin(phase))*(.055+wind*.024)*exp2(-band*.29)*resolved;
 }
 vec3 macro_normal=water_normal;
 float macro_crest=crest;
 if(ocean_surface) {
  vec2 from_center=wave_parameter-mesh_center;
  float radius=max(abs(from_center.x),abs(from_center.y));
  float analytic_blend=smoothstep(100.,164.,radius);
  if(analytic_blend>0.) {
   // Aerial views expose coarse ring triangles. Evaluate their filtered
   // shading field per fragment so normals/crest color remain continuous.
   float height; vec2 gradient,displacement;
   sample_waves(wave_parameter,radius,height,gradient,displacement);
   float damping=smoothstep(0.,shore_damping,max(0.,depth_at(wave_parameter)));
   macro_normal=normalize(mix(water_normal,normalize(vec3(-gradient.x*damping,1.,-gradient.y*damping)),analytic_blend));
   macro_crest=mix(crest,height/max(wave_height_max,.001),analytic_blend);
  }
 }
 vec3 normal=normalize(macro_normal+vec3(-slope.x,0.,-slope.y)*.86*ripple_strength*breeze*mix(1.,.65,shore));
 vec3 view=normalize(CAMERA_POSITION_WORLD-water_world);
 float facing=clamp(dot(normal,view),0.,1.);
 float crest_light=smoothstep(-.48,.7,macro_crest);
 float optical_depth=min(max(optical_depth_min,depth),mix(7.1,1.65,crest_light))/max(facing+.23,.3);
 vec3 transmission=exp(-absorption*optical_depth);
 vec3 body=deep_color.rgb+scatter_color.rgb*transmission*(.22+crest_light*.28);
 float warp=sin(dot(p,vec2(.39,.71))-water_time*(.71+wind*.28));
 float satin=.5+.5*sin(dot(p+vec2(warp*.29,-warp*.18),vec2(2.08,1.34))-water_time*1.72);
 float capillary=.5+.5*sin(dot(p+vec2(-warp*.13,warp*.21),vec2(-3.57,4.22))+water_time*2.43);
 float detail_grain=satin*.66+capillary*.34;
 body*=mix(.985,1.015,mix(.5,detail_grain,1.-smoothstep(.12,.32,footprint)));
 specular_visibility=1.-smoothstep(.20,.86,footprint);
 float backscatter=pow(max(dot(view,-sun_direction),0.),4.)*smoothstep(.4,.92,crest_light)*smoothstep(.06,.38,length(macro_normal.xz));
 body+=scatter_color.rgb*backscatter*.34;
 // A bank-local optical transition also works for a pond with a flat floor.
 body=mix(body,shore_color.rgb,shore*.32);
 float wash=.5+.5*sin(shore_distance_m*2.7-water_time*.72+shoreline_noise*5.);
 float breakup=texture(surface_field,p/9.+water_time*vec2(.002,-.001)).g;
 float foam=shore*smoothstep(.57,.76,breakup)*smoothstep(.65,.92,wash)*foam_strength;
 body=mix(body,vec3(.64,.67,.59),foam);
 NORMAL=normalize((VIEW_MATRIX*vec4(normal,0.)).xyz);
 ALBEDO=body;
 // Godot's dielectric F0 = .16 * SPECULAR²; sqrt(.02037/.16).
 SPECULAR=.3568095;
 METALLIC=0.;
 // Unresolved normal variance widens the sky lobe rather than sparkling.
 float normal_variance=max(dot(dFdx(normal),dFdx(normal)),dot(dFdy(normal),dFdy(normal)));
 ROUGHNESS=clamp(sqrt(pow(roughness+wind*.11+(1.-breeze)*.045+foam*.2,2.)+normal_variance*2.),.14,.43);
 EMISSION=body*.12;
 // Same depth-fog curve/color as the map. An authored upper bound retains
 // faint water identity from Seabreeze's elevated, foggy coastal road.
 float fog_amount=pow(smoothstep(fog_range.x,fog_range.y,length(water_world-CAMERA_POSITION_WORLD)),fog_range.z);
 float aerial=smoothstep(50.,100.,CAMERA_POSITION_WORLD.y-MODEL_MATRIX[3].y);
 float fog_limit=mix(mix(fog_range.w,1.,aerial),1.,smoothstep(fog_range.y*1.15,fog_range.y*4.,length(water_world-CAMERA_POSITION_WORLD)));
 FOG=vec4(fog_color.rgb,fog_limit*(1.-pow(1.-fog_amount,1./max(fog_limit,.01))));
}

// The reference bounds the sun lobe and filters subpixel highlights separately
// from sky reflection. Keep those controls while using Godot's lights/shadows.
void light() {
 float nv=max(dot(NORMAL,VIEW),.035), nl=max(dot(NORMAL,LIGHT),0.);
 vec3 half_direction=normalize(VIEW+LIGHT);
 float nh=clamp(dot(NORMAL,half_direction),0.,1.), vh=clamp(dot(VIEW,half_direction),0.,1.);
 float alpha=max(ROUGHNESS*ROUGHNESS,.0075), a2=alpha*alpha;
 float denominator=nh*nh*(a2-1.)+1.;
 float distribution=a2/max(3.14159265*denominator*denominator,.00001);
 float k=pow(ROUGHNESS+1.,2.)*.125;
 float geometry=(nv/(nv*(1.-k)+k))*(nl/max(nl*(1.-k)+k,.001));
 float fresnel=.02037+.97963*pow(1.-vh,5.);
 float specular=min(distribution*geometry*fresnel/max(4.*nv*max(nl,.018),.025)*nl,.18);
 DIFFUSE_LIGHT+=nl*ATTENUATION*LIGHT_COLOR/3.14159265;
 SPECULAR_LIGHT+=specular*specular_visibility*ATTENUATION*LIGHT_COLOR/3.14159265;
}
