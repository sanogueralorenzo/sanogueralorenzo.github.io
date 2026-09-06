class_name SwoopFrameMetrics
extends RefCounted

const CAPACITY := 1800
var frames := PackedFloat64Array()
var cursor := 0
var count := 0
var last_tick := 0
var peak_static_bytes := 0

func _init() -> void:
 frames.resize(CAPACITY)

func reset() -> void:
 cursor=0
 count=0
 last_tick=0
 peak_static_bytes=0

func sample() -> void:
 var now := Time.get_ticks_usec()
 if last_tick>0:
  frames[cursor]=float(now-last_tick)/1000.0
  cursor=(cursor+1)%CAPACITY
  count=mini(CAPACITY,count+1)
 last_tick=now
 peak_static_bytes=maxi(peak_static_bytes,int(Performance.get_monitor(Performance.MEMORY_STATIC)))

func snapshot() -> Dictionary:
 var ordered := frames.slice(0,count)
 ordered.sort()
 var p50 := 0.0
 var p95 := 0.0
 var worst := 0.0
 if count>0:
  p50=ordered[int((count-1)*0.50)]
  p95=ordered[int((count-1)*0.95)]
  worst=ordered[count-1]
 return {"samples":count,"frame_ms_p50":p50,"frame_ms_p95":p95,"frame_ms_max":worst,"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,"static_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0,"peak_static_mb":float(peak_static_bytes)/1048576.0,"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"triangles":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
