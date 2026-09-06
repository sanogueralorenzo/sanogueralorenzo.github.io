class_name SwoopSound
extends Node

var wind: AudioStreamPlayer
var rush: AudioStreamPlayer
var birds: AudioStreamPlayer
var effect: AudioStreamPlayer
var volume := 0.7
var bird_timer := 3.0
var rng := RandomNumberGenerator.new()
var clips: Dictionary={}
var voices: Array[AudioStreamPlayer]=[]
var voice_strengths: Array[float]=[]
var next_voice := 0
var was_diving := false
var was_active := false
var pass_cooldown := 0.0
var recovery_cooldown := 0.0

func wave(kind: String, seconds: float, pan := 0.0) -> AudioStreamWAV:
 var result := AudioStreamWAV.new()
 result.format=AudioStreamWAV.FORMAT_16_BITS
 result.mix_rate=22050
 result.stereo=true
 var count := int(seconds*22050)
 var bytes := PackedByteArray()
 bytes.resize(count*4)
 var filter := 0.0
 var left_gain := sqrt((1.0-pan)*0.5)
 var right_gain := sqrt((1.0+pan)*0.5)
 for i in count:
  var t := float(i)/22050.0
  var progress := t/seconds
  var envelope := pow(maxf(0.0,1.0-progress),2.0)*minf(t*55.0,1.0)
  var sample := 0.0
  var noise := rng.randf_range(-1.0,1.0)
  match kind:
   "wind":
    filter=lerpf(filter,noise,0.045)
    sample=filter*0.78+sin(t*TAU*73.0)*0.003
   "rush":
    filter=lerpf(filter,noise,0.15)
    sample=(noise-filter)*0.085
   "pass":
    filter=lerpf(filter,noise,0.07+sin(progress*PI)*0.27)
    sample=filter*0.90*pow(sin(progress*PI),2.0)
   "tuck":
    filter=lerpf(filter,noise,0.10)
    sample=(filter*0.75+sin(t*TAU*(145.0-t*120.0))*0.045)*envelope
   "spread":
    filter=lerpf(filter,noise,0.075)
    sample=(filter*0.90+sin(t*TAU*(115.0-t*80.0))*0.10)*envelope
   "strain":
    filter=lerpf(filter,noise,0.06)
    sample=(filter*0.70+sin(t*TAU*89.0)*0.045)*envelope
   "crash":
    filter=lerpf(filter,noise,0.18)
    sample=(filter*0.9+sin(t*TAU*(65.0-t*20.0))*0.28)*envelope
   "bird": sample=sin(t*TAU*(1800.0+sin(t*38.0)*240.0))*0.09*envelope*pow(sin(t*19.0),2.0)
   _: sample=(sin(t*TAU*523.25)+sin(t*TAU*784.0)*0.45)*0.10*envelope
  # The continuous beds meet at silence to avoid a click at their loop seam.
  if kind=="wind" or kind=="rush": sample*=smoothstep(0.0,0.025,t)*smoothstep(0.0,0.025,seconds-t)
  bytes.encode_s16(i*4,int(clampf(sample*left_gain,-1.0,1.0)*32760.0))
  bytes.encode_s16(i*4+2,int(clampf(sample*right_gain,-1.0,1.0)*32760.0))
 result.data=bytes
 if kind=="wind" or kind=="rush":
  result.loop_mode=AudioStreamWAV.LOOP_FORWARD
  result.loop_end=count
 return result

func _ready() -> void:
 rng.seed=8754
 # Generate once. Close passes and flight transitions never allocate a WAV in play.
 clips.wind=wave("wind",4.0)
 clips.rush=wave("rush",3.7)
 for kind in ["pass","tuck","spread","strain","crash","bird","start"]:
  var duration := 0.65 if kind=="crash" else (0.7 if kind=="bird" else 0.32)
  clips[kind]=wave(kind,duration)
 clips.pass_left=wave("pass",0.32,-0.75)
 clips.pass_right=wave("pass",0.32,0.75)
 wind=AudioStreamPlayer.new()
 add_child(wind)
 wind.stream=clips.wind
 wind.volume_db=-30.0
 wind.play()
 rush=AudioStreamPlayer.new()
 add_child(rush)
 rush.stream=clips.rush
 rush.volume_db=-40.0
 rush.play()
 birds=AudioStreamPlayer.new()
 add_child(birds)
 birds.stream=clips.bird
 for i in 4:
  var voice := AudioStreamPlayer.new()
  add_child(voice)
  voices.append(voice)
  voice_strengths.append(1.0)
 effect=voices[0]

func update(delta: float, speed: float, diving: bool, active: bool, bank := 0.0, recovery_intensity := 0.0, clearance := 6.0) -> void:
 var master_db := linear_to_db(maxf(clampf(volume,0.0,1.0),0.0001))
 var blend := 1.0-exp(-delta*4.0)
 var load_amount := clampf(absf(bank)*0.45+recovery_intensity*0.75,0.0,1.0)
 var skimming := clampf((5.0-clearance)/4.0,0.0,1.0)
 var wind_target := master_db-15.0+speed*0.13+load_amount*2.2
 var rush_target := master_db-26.0+maxf(speed-17.0,0.0)*0.48+skimming*3.0
 if not active:
  wind_target-=12.0
  rush_target-=20.0
 wind.volume_db=lerpf(wind.volume_db,wind_target,blend)
 rush.volume_db=lerpf(rush.volume_db,rush_target,blend)
 wind.pitch_scale=lerpf(wind.pitch_scale,0.74+speed/55.0+(0.08 if diving else 0.0),blend)
 rush.pitch_scale=lerpf(rush.pitch_scale,0.80+speed/64.0,blend)
 birds.volume_db=master_db-7.0-(5.0 if active and speed>25.0 else 0.0)
 for i in voices.size(): voices[i].volume_db=master_db+linear_to_db(maxf(voice_strengths[i],0.0001))
 pass_cooldown=maxf(0.0,pass_cooldown-delta)
 recovery_cooldown=maxf(0.0,recovery_cooldown-delta)
 if active and was_active and diving!=was_diving:
  cue("tuck" if diving else "spread",0.0,0.55+clampf((speed-18.0)/22.0,0.0,1.0)*0.35)
 if active and not diving and recovery_intensity>0.35 and recovery_cooldown<=0.0:
  cue("strain",0.0,0.45*recovery_intensity)
  recovery_cooldown=1.4
 was_diving=diving
 was_active=active
 bird_timer-=delta
 if bird_timer<0.0:
  bird_timer=rng.randf_range(6.0,13.0)
  if not active or (speed<26.0 and recovery_intensity<0.2):
   birds.pitch_scale=rng.randf_range(0.85,1.15)
   birds.play()

func cue(kind: String, side := 0.0, strength := 1.0) -> void:
 if voices.is_empty(): return
 var clip_name := kind
 if kind=="pass":
  # Several capsules can belong to one tree: keep its whoosh a single gesture.
  if pass_cooldown>0.0: return
  pass_cooldown=0.12
  if side< -0.15: clip_name="pass_left"
  elif side>0.15: clip_name="pass_right"
 if not clips.has(clip_name): clip_name="start"
 var voice := voices[next_voice]
 voice_strengths[next_voice]=clampf(strength,0.0,1.0)
 voice.stream=clips[clip_name]
 voice.volume_db=linear_to_db(maxf(clampf(volume,0.0,1.0)*voice_strengths[next_voice],0.0001))
 voice.play()
 next_voice=(next_voice+1)%voices.size()
