shader_type canvas_item;
render_mode unshaded;
// The world is already tone mapped to display space. UI is drawn afterward.
// Retain a restrained print palette without blurring faces, net or ball.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
void fragment() {
 vec3 color=texture(screen_texture,SCREEN_UV).rgb;
 float light=dot(color,vec3(.2126,.7152,.0722));
 color=mix(vec3(light),color,.98);
 color+=vec3(.004,.003,-.002)*light;
 vec2 q=SCREEN_UV-.5;
 COLOR=vec4(color*(1.-dot(q,q)*.045),1.);
}
