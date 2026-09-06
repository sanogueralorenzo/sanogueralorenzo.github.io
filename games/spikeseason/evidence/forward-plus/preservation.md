# Preservation audit

Compared with the fingerprinted newer 3D worktree, September 6, 2026. This is source inspection, not an automated test. The older 2D main edition has different presentation and inherited balance; see FORWARD_PLUS.md baseline disclosure.

## scripts/main.gd

```diff
--- newer 3D baseline
+++ migration
@@ -102,6 +102,16 @@
 var toast_time := 0.0
 
 func _ready() -> void:
+	# Check the active renderer: command-line overrides bypass project defaults.
+	var renderer:=RenderingServer.get_current_rendering_method()
+	var driver:=RenderingServer.get_current_rendering_driver_name()
+	if renderer!="forward_plus" or RenderingServer.get_rendering_device()==null:
+		push_error("Spike Season requires Forward+ with a working Metal, Vulkan, or Direct3D 12 device. Active renderer: "+renderer+"; driver: "+driver)
+		set_process(false)
+		set_process_unhandled_key_input(false)
+		get_tree().quit(1)
+		return
+	print("SPIKE RENDERER method="+renderer+" driver="+driver+" gpu="+RenderingServer.get_video_adapter_name()+" window="+str(DisplayServer.window_get_size()))
 	scenery=Scenery.new()
 	scenery.game=self
 	add_child(scenery)
```

## scripts/interface.gd

Unchanged.

## scripts/sound.gd

Unchanged.

## scripts/leaf_painter.gd

Unchanged.

## scripts/three_d/athlete.gd

```diff
--- newer 3D baseline
+++ migration
@@ -55,7 +55,7 @@
 	team=side
 	skin=ShaderMaterial.new()
 	skin.shader=preload("res://shaders/three_d/skin.gdshader")
-	skin.set_shader_parameter("skin_color",[Color("dfad83"),Color("bf865d"),Color("edbb92")][identity])
+	skin.set_shader_parameter("skin_color",[Color("c17f6b"),Color("9e5846"),Color("d48f78")][identity])
 	skin.next_pass=ink_pass()
 	cloth=ShaderMaterial.new()
 	cloth.shader=preload("res://shaders/three_d/uniform.gdshader")
```

## scripts/three_d/ball_effects.gd

Unchanged.

## scripts/three_d/harbor.gd

Unchanged.

## scripts/three_d/gardens.gd

Unchanged.

## scripts/three_d/geometry.gd

Unchanged.
