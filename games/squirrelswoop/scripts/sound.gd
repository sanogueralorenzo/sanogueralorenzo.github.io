class_name SwoopSound
extends Node

var wind: AudioStreamPlayer
var birds: AudioStreamPlayer
var effect: AudioStreamPlayer
var volume := 0.7
var low_pass := 0.0
var bird_timer := 3.0
var rng := RandomNumberGenerator.new()

func wave(kind: String, seconds: float) -> AudioStreamWAV:
 var result := AudioStreamWAV.new()
 result.format=AudioStreamWAV.FORMAT_16_BITS
 result.mix_rate=22050
 var bytes := PackedByteArray()
 bytes.resize(int(seconds*22050)*2)
 var filter := 0.0
 for i in bytes.size()/2:
  var t := float(i)/22050.0
  var envelope := pow(maxf(0.0,1.0-t/seconds),2.0)*minf(t*45.0,1.0)
  var sample := 0.0
  match kind:
   "wind":
    filter=lerpf(filter,rng.randf_range(-1,1),0.065)
    sample=filter*0.65+sin(t*TAU*73.0)*0.007
   "pass": sample=(sin(t*TAU*(740.0+t*480.0))*0.15+sin(t*TAU*1110.0)*0.10)*envelope
   "crash":
    filter=lerpf(filter,rng.randf_range(-1,1),0.18)
    sample=(filter*0.9+sin(t*TAU*(65.0-t*20.0))*0.28)*envelope
   "bird": sample=sin(t*TAU*(1800.0+sin(t*38.0)*240.0))*0.09*envelope*pow(sin(t*19.0),2.0)
   _: sample=(sin(t*TAU*523.25)+sin(t*TAU*784.0)*0.45)*0.12*envelope
  bytes.encode_s16(i*2,int(clampf(sample,-1,1)*32760.0))
 result.data=bytes
 if kind=="wind":
  result.loop_mode=AudioStreamWAV.LOOP_FORWARD
  result.loop_end=bytes.size()/2
 return result

func _ready() -> void:
 rng.seed=8754
 wind=AudioStreamPlayer.new()
 add_child(wind)
 wind.stream=wave("wind",3.0)
 wind.volume_db=-18
 wind.play()
 birds=AudioStreamPlayer.new()
 add_child(birds)
 birds.stream=wave("bird",0.7)
 effect=AudioStreamPlayer.new()
 add_child(effect)

func update(delta: float, speed: float, diving: bool, active: bool) -> void:
 var target := linear_to_db(maxf(volume,0.0001))-14.0+speed*0.18
 if not active: target-=11.0
 wind.volume_db=lerpf(wind.volume_db,target,delta*3.0)
 wind.pitch_scale=lerpf(wind.pitch_scale,0.7+speed/48.0+(0.12 if diving else 0.0),delta*2.0)
 bird_timer-=delta
 if bird_timer<0:
  bird_timer=rng.randf_range(5.0,12.0)
  birds.volume_db=linear_to_db(maxf(volume,0.0001))-4.0
  birds.pitch_scale=rng.randf_range(0.8,1.2)
  birds.play()

func cue(kind: String) -> void:
 effect.stream=wave(kind,0.65 if kind=="crash" else 0.38)
 effect.volume_db=linear_to_db(maxf(volume,0.0001))
 effect.play()
