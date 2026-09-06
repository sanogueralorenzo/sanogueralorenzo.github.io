"""Prepare disposable manual-inspection copies; no tests, bot inputs or assertions."""
from pathlib import Path
import shutil
root=Path('/Users/mario/AndroidStudioProjects/spikeseason-forward-plus/games/spikeseason')
work=Path('/tmp/spikeseason-forward-review')
shutil.copytree(root,work/'candidate',ignore=shutil.ignore_patterns('.godot','evidence','build'),dirs_exist_ok=True)
# Identical measurement instrumentation, only inside disposable projects.
bridge=(root/'scripts/review_bridge.gd').read_text()
bridge=bridge.replace('\t\t"performance":','''\t\t"render":
\t\t\tif r.get("environment",{}).get("sdfgi_enabled",false):
\t\t\t\tfor actor in game.scenery.actors: _disable_gi(actor)
\t\t\t\t_disable_gi(game.scenery.ball_effects)
\t\t\t\tfor marker in [game.scenery.selected_ring,game.scenery.aim_ring,game.scenery.floor_ring,game.scenery.scouting_ring,game.scenery.scouting_outline]: _disable_gi(marker)
\t\t\t\t_disable_wind_gi(game.scenery)
\t\t\tfor key in r.get("environment",{}): game.scenery.environment.set(key,r.environment[key])
\t\t\tfor key in r.get("sun",{}): game.scenery.sun.set(key,r.sun[key])
\t\t\tif r.has("fog_volume"):
\t\t\t\tvar existing=game.scenery.get_node_or_null("ReviewFog")
\t\t\t\tif existing: existing.queue_free()
\t\t\t\tif bool(r.fog_volume):
\t\t\t\t\tvar volume=FogVolume.new()
\t\t\t\t\tvolume.name="ReviewFog"
\t\t\t\t\tvolume.size=Vector3(100,22,75)
\t\t\t\t\tvolume.position=Vector3(0,4,-55)
\t\t\t\t\tvolume.material=FogMaterial.new()
\t\t\t\t\tvolume.material.density=.012
\t\t\t\t\tvolume.material.albedo=Color("c1d3d7")
\t\t\t\t\tvolume.material.edge_fade=.6
\t\t\t\t\tgame.scenery.add_child(volume)
\t\t\tfor key in r.get("viewport",{}): get_viewport().set(key,r.viewport[key])
\t\t"stage":
\t\t\tgame.start_run(int(r.get("season",1))-1)
\t\t\tgame.pause=true
\t\t\t# Warmup captions are not altered; no unlock or outcome overrides.
\t\t\tgame.scenery.inspection_camera=true
\t\t\tgame.scenery.camera.position=Vector3(1.2,3.4,11.7)
\t\t\tgame.scenery.camera.look_at(Vector3(0,1.63,-.2))
\t\t\tgame.ui.visible=bool(r.get("ui",true))
\t\t"performance":''')
bridge=bridge.replace('"performance":performance_snapshot(),','"render_options":{ "taa":get_viewport().use_taa,"msaa":get_viewport().msaa_3d,"sdfgi":game.scenery.environment.sdfgi_enabled,"ssil":game.scenery.environment.ssil_enabled,"ssr":game.scenery.environment.ssr_enabled,"volumetric":game.scenery.environment.volumetric_fog_enabled,"sun_angle":game.scenery.sun.light_angular_distance},"performance":performance_snapshot(),')
bridge += """
func _disable_gi(node:Node) -> void:
\tif node is GeometryInstance3D: node.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
\tfor child in node.get_children(): _disable_gi(child)
func _disable_wind_gi(node:Node) -> void:
\tif node.has_meta("moving_foliage"): _disable_gi(node)
\tfor child in node.get_children(): _disable_wind_gi(child)
"""
for name in ['baseline','candidate']:
 (work/name/'scripts/review_bridge.gd').write_text(bridge)
# Existing legitimately earned progress, copied byte for byte into isolated profiles.
saves=Path.home()/'Library/Application Support/Godot/app_userdata/Spike Season'
for name in ['baseline','candidate']:
 shutil.copyfile(saves/'review-3d-forward.json',saves/('review-forward-'+name+'.json'))
