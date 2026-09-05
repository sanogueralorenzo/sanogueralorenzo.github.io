shader_type spatial;
render_mode diffuse_burley, specular_disabled;
uniform vec4 base_color : source_color = vec4(.7,.6,.5,1.);
uniform float grain=.12;
uniform int pattern=0;
varying vec3 world;
varying vec3 face;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
float seam(float value,float width){float d=abs(fract(value+.5)-.5);return 1.-smoothstep(width,width+max(fwidth(value),.001),d);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;face=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 vec2 plane=abs(face.y)>.6?world.xz:vec2(abs(face.x)>.6?world.z:world.x,world.y);
 float coarse=noise(plane*.43)+noise(plane*1.3+19.)*.45;
 float fine=noise(plane*13.);
 float finish=.94+(coarse-.7)*grain+(fine-.5)*grain*.18;
 if(pattern==1){finish*=1.-.15*seam(world.y*5.,.027);finish+=noise(vec2(plane.x*.75,world.y*35.))*.035;}
 if(pattern==2){float row=floor(world.y*5.);float mortar=max(seam(world.y*5.,.032),seam(plane.x*2.4+mod(row,2.)*.5,.023));finish*=1.-mortar*.19;finish+=(hash(vec2(floor(plane.x*2.4+mod(row,2.)*.5),row))-.5)*.13;}
 if(pattern==3){finish*=1.-.12*seam(plane.x*4.,.035);}
 if(pattern==4){finish=.85+noise(plane*.32)*.21+noise(plane*1.7)*.09;finish*=1.-.12*smoothstep(.56,.72,noise(plane*.7+21.));}
 if(pattern==5){finish=.89+noise(plane*.45)*.17;finish*=1.-.12*max(seam(plane.x/1.6,.004),seam(plane.y/1.6,.004));}
 ALBEDO=base_color.rgb*finish;ROUGHNESS=.95;
}
