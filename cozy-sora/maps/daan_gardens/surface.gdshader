shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shared/surface_noise.gdshaderinc"
uniform vec4 tint:source_color=vec4(.65,.65,.55,1.);
uniform int finish=0;
varying vec3 world;
varying vec3 local_normal;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;local_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 vec2 p=abs(local_normal.y)>.6?world.xz:(abs(local_normal.x)>.6?world.zy:world.xy);
 float mark=.97+(noise(p*.55)-.5)*.07+(noise(p*11.)-.5)*.025;
 float relief = noise(p * 82.0) * 0.0012;
 if (finish == 1) {
     vec2 grid = p / 1.1;
     float grout = max(seam(grid.x, .007), seam(grid.y, .007));
     float slab = hash(floor(grid));
     float patina = noise(p * 2.1 + slab * 8.0);
     mark *= (1.0 - 0.2 * grout) * (0.84 + 0.13 * slab + 0.08 * patina);
     relief -= grout * 0.003;
 }
 if (finish == 2) {
     vec2 tile = p * 5.0;
     float joints = max(seam(tile.x, .025), seam(tile.y, .025));
     mark *= (1.0 - 0.22 * joints) * (0.92 + hash(floor(tile)) * 0.14);
     relief -= joints * 0.002;
 }
 if (finish == 3) {
     mark *= 0.97 + 0.025 * sin(p.x * 35.0 + sin(p.y * 3.0) * 0.6) * (1.0 - smoothstep(0.4, 1.5, fwidth(p.x * 35.0)));
 }
 vec3 ground_color = tint.rgb;
 if (finish == 4) {
     vec2 bark = vec2(atan(local_normal.x, local_normal.z) * 3.4, world.y);
     float drift = noise(bark * vec2(.56, .85));
     float ridges = noise(vec2(bark.x * 2.9 + drift * 2.5, bark.y * 2.1));
     float fissures = smoothstep(.28, .63, ridges);
     float moss = smoothstep(.55, .77, noise(p * 3.7)) * (1.0 - smoothstep(1.0, 3.0, world.y));
     ground_color = mix(ground_color * (0.55 + 0.65 * fissures), vec3(.068, .10, .037), moss * .56);
     relief += fissures * 0.009;
 }
 NORMAL = relief_normal(VERTEX, NORMAL, relief);
 ALBEDO = ground_color * mark;
 ROUGHNESS = .92;
 SPECULAR = .24;
}
