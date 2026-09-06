// Procedural palettes and mesh colors are authored in sRGB. Forward+ shades in
// linear light. Color textures marked source_color are already decoded by Godot.
vec3 pigment_to_linear(vec3 pigment) {
 vec3 color=max(pigment,vec3(0.0));
 return mix(pow((color+0.055)/1.055,vec3(2.4)),color/12.92,lessThanEqual(color,vec3(0.04045)));
}
