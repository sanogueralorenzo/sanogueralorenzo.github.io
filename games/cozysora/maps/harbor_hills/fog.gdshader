shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
uniform float phase=0.;
void fragment(){vec2 q=UV*2.-1.;float edge=pow(max(0.,1.-dot(q,q)),2.);float wisps=.6+.4*sin(UV.x*19.+TIME*.025+phase)*sin(UV.y*13.+TIME*.017);ALBEDO=vec3(.72,.8,.83);ALPHA=edge*wisps*.14;}
