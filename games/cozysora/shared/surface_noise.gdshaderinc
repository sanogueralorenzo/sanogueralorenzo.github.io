// Continuous world-space variation and pixel-integrated joints for all crafted surfaces.
float hash(vec2 p) {
 vec3 q=fract(vec3(p.xyx)*vec3(.1031,.1030,.0973));
 q+=dot(q,q.yzx+33.33);
 return fract((q.x+q.y)*q.z);
}
float noise(vec2 p) {
 vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);
 float value=mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
 return mix(value,.5,smoothstep(.45,1.4,max(length(dFdx(p)),length(dFdy(p)))));
}
float joint_integral(float x,float width){return floor(x)*width+min(fract(x),width);}
float seam(float value,float width) {
 float footprint=max(fwidth(value),.0001);
 float x=value+width;
 return clamp((joint_integral(x+footprint*.5,width*2.)-joint_integral(x-footprint*.5,width*2.))/footprint,0.,1.);
}
