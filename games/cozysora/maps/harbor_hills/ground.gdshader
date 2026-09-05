shader_type spatial;
render_mode diffuse_burley, specular_disabled;
varying vec3 world;
varying vec3 slope;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;slope=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 vec2 p=world.xz;
 float n=noise(p*.18)*.55+noise(p*.64+17.)*.3+noise(p*2.1)*.15;
 vec3 color=mix(vec3(.28,.37,.17),vec3(.48,.51,.26),smoothstep(.25,.74,n));
 color=mix(color,vec3(.36,.40,.20),smoothstep(.45,.62,noise(p*.95))*.45);
 float bare=smoothstep(.59,.78,noise(p*.37+32.));
 color=mix(color,vec3(.49,.44,.32),bare*.55);
 color*=.94+noise(p*8.)*.09;
 // Exposed steep cuts reveal fitted retaining stone, not stretched turf.
 float steep=1.-smoothstep(.48,.72,abs(slope.y));
 vec2 wall=vec2(world.x+world.z,world.y);float row=floor(wall.y*3.);
 vec2 joint=fract(vec2(wall.x*1.8+mod(row,2.)*.5,wall.y*3.));
 float mortar=max(1.-smoothstep(.035,.07,joint.x),1.-smoothstep(.035,.07,joint.y));
 vec3 stone=mix(vec3(.43,.46,.38),vec3(.58,.57,.46),noise(floor(wall*vec2(1.8,3.))));stone*=1.-mortar*.17;
 color=mix(color,stone,steep);
 ALBEDO=pow(color,vec3(2.2));ROUGHNESS=1.;
}
