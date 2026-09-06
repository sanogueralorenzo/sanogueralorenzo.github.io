shader_type sky;
uniform vec3 sky_top : source_color = vec3(.22,.46,.66);
uniform vec3 sky_horizon : source_color = vec3(.60,.76,.80);
uniform vec3 cloud_shadow : source_color = vec3(.77,.83,.85);
uniform vec3 cloud_light : source_color = vec3(.99,.98,.95);
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void sky(){float h=max(EYEDIR.y,0.0);vec3 col=mix(sky_horizon,sky_top,pow(h,.5));vec2 p=vec2(atan(EYEDIR.x,EYEDIR.z)*8.0,h*12.0);float n=noise(p)+noise(p*2.1)*.34+noise(p*4.3)*.19+noise(p*8.1)*.085+noise(p*16.0)*.035;float cloud=smoothstep(1.02,1.17,n)*smoothstep(.055,.20,h);vec3 cloudcolor=mix(cloud_shadow,cloud_light,smoothstep(.85,1.21,n));col=mix(col,cloudcolor,cloud*.94);COLOR=col;}
