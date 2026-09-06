shader_type spatial;
render_mode diffuse_burley, specular_disabled;
uniform vec4 base_color : source_color = vec4(0.96,0.91,0.77,1.0);
uniform vec4 panel_color : source_color = vec4(0.86,0.66,0.23,1.0);
uniform bool shorts=false;
float crease(float distance,float width){return exp(-distance*distance/(width*width));}
void fragment() {
 float angle=UV.x*6.283185;
 float across=sin(angle);
 float face=pow(abs(cos(angle)),3.);
 float seam=smoothstep(.88,.92,abs(across));
 vec3 cloth=mix(base_color.rgb,panel_color.rgb,seam);
 float shadow=0.; float light_edge=0.;
 if(shorts){
  float fold=UV.y-(.24+.20*across);
  float lower=UV.y-(.64-.14*across);
  shadow=(crease(fold,.048)*.24+crease(lower,.033)*.18)*face;
  light_edge=(crease(fold+.048,.038)+crease(lower+.036,.027))*.08*face;
  cloth=mix(cloth,panel_color.rgb,smoothstep(.91,.94,UV.y));
 }else{
  // Authored tension folds at the tucked waist and shoulders leave the number clear.
  float waist=UV.y-(.13+.085*across);
  float diagonal=UV.y-(.30-.11*across);
  float shoulder=UV.y-(.76+.10*abs(across));
  shadow=(crease(waist,.025)*.23+crease(diagonal,.026)*.16*abs(across)+crease(shoulder,.035)*.12)*face;
  light_edge=(crease(waist+.025,.022)*.08+crease(diagonal+.027,.021)*.07*abs(across))*face;
 }
 ALBEDO=cloth*(1.-shadow+light_edge);
 ROUGHNESS=.96;
}
