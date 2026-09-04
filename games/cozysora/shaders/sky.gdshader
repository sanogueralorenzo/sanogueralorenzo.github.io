shader_type sky;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 q=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(q),hash(q+vec2(1,0)),f.x),mix(hash(q+vec2(0,1)),hash(q+vec2(1,1)),f.x),f.y);}
float fbm(vec2 p){return noise(p)*.5+noise(p*2.)*.25+noise(p*4.)*.125+noise(p*8.)*.0625;}
float billow(vec2 p){float n=abs(2.*noise(p)-1.);return n*n*(3.-2.*n);}
float cloud(vec2 q,float cover,float curl){float mass=fbm(q*.5);float lobes=billow(q*3.2+vec2(0,4))*.5+billow(q*6.4+vec2(0,8))*.275;float detail=billow(q*8.+vec2(0,11))*.5+billow(q*16.+vec2(0,22))*.275;return cover+(mass-cover)*2.2+smoothstep(-.02,.08,mass-cover)*((lobes-.5)*.22+(detail-.5)*curl);}
void sky(){
 vec3 d=normalize(EYEDIR);float h=d.y;
 vec3 horizon=vec3(.76,.81,.86);
 vec3 col=mix(horizon,vec3(.46,.64,.8),smoothstep(0.,.22,h));
 col=mix(col,vec3(.22,.46,.71),smoothstep(.2,.75,h));
 vec3 sun=normalize(vec3(-.55,.7,-.38));
 float sunlight=max(dot(d,sun),0.);
 col+=vec3(.2,.17,.12)*pow(sunlight,24.)+vec3(1.,.95,.85)*pow(sunlight,400.)*.8;
 if(h>-.02){
 float inland=smoothstep(-.4,.6,d.z)*.55+smoothstep(0.,.8,d.x)*.45;
 float top=.32+.46*inland;
 vec2 q=vec2((atan(d.x,d.z)/6.283185+.5)*16.+TIME*.006,asin(clamp(h,-1.,1.))/6.283185*16.);
 q+=(vec2(fbm(q*.5+vec2(0,3)),fbm(q*.5+vec2(0,9)))-.5)*.8;
 float cover=.29+.30*pow(max(h,0.)/top,2.)+.34*(1.-inland);
 float field=cloud(q,cover,.10);float mass=fbm(q*.5);
 float mask=smoothstep(cover-.004,cover+.004,field)*smoothstep(cover-.04,cover-.015,mass)*smoothstep(-.01,.04,h);
 float dx=cloud(q+vec2(.025,0),cover,0.)-cloud(q-vec2(.025,0),cover,0.);
 float dy=cloud(q+vec2(0,.025),cover,0.)-cloud(q-vec2(0,.025),cover,0.);
 vec3 normal=normalize(vec3(-dx/.05,-dy/.05,1.6));
 float side=clamp(sin(atan(sun.x,sun.z)-atan(d.x,d.z))*2.,-1.,1.);
 float lit=dot(normal,normalize(vec3(side*.55,.8,.45)));
 float bulk=clamp((fbm((q+vec2(side*.18,.30))*.5)-mass)*3.,0.,1.);
 float shade=(1.-smoothstep(.1,.5,lit))*.65+bulk*.35*smoothstep(cover,cover+.2,field)+smoothstep(cover,cover+.2,field)*(1.-smoothstep(.02,.55*top,h))*.4;
 shade=mix(shade,floor(shade*4.+.5)/4.,.3);
 vec3 cc=mix(vec3(1.,.98,.94),vec3(.58,.65,.77),smoothstep(.15,.45,shade));
 cc=mix(cc,vec3(.50,.58,.70),smoothstep(.50,.85,shade));
 col=mix(col,cc,mask);
 }
 COLOR=pow(col,vec3(2.2));
}
