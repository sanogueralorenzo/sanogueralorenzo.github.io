shader_type spatial;
render_mode diffuse_burley;
uniform vec4 base_color : source_color = vec4(.7,.6,.5,1.);
uniform float grain=.12;
uniform int pattern=0;
varying vec3 world;
float hash(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;}
void fragment(){
 float n=hash(floor(world*37.))*.5+hash(floor(world*5.))*.3+hash(floor(world*.8))*.2;
 float line=1.;
 if(pattern==1){line=1.-.17*step(.94,fract(world.y*5.));}
 if(pattern==2){float row=floor(world.y*5.);line=1.-.18*max(step(.9,fract(world.y*5.)),step(.94,fract((world.x+world.z)*2.4+mod(row,2.)*.5)));}
 if(pattern==3){line=1.-.12*step(.88,fract((world.x+world.z)*4.));}
 ALBEDO=base_color.rgb*(.86+(n-.5)*grain)*line;ROUGHNESS=.86;
}
