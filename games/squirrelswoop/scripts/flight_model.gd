extends RefCounted

# The mountain sets the nominal glide angle. Height above it is a resource:
# ordinary trim leaves a comfortable band alone, while a sustained pull still
# runs out of lift as speed falls. Emergency ground lift is an optional aid.
var speed := 20.0
var vertical_speed := -8.5
var lateral_speed := 0.0
var bank := 0.0
var recovery_intensity := 0.0
var flight_state := "gliding"

func reset() -> void:
 speed=20.0
 vertical_speed=-8.5
 lateral_speed=0.0
 bank=0.0
 recovery_intensity=0.0
 flight_state="gliding"

func step(delta: float, pos: Vector3, steer: float, pitch: float, dive: bool, assistance: bool, mountain) -> Vector3:
 bank=lerpf(bank,clampf(steer,-1.0,1.0),1.0-exp(-delta*6.5))
 pitch=clampf(pitch,-1.0,1.0)
 var acceleration := 7.0-(speed-24.0)*0.22 if dive else (21.5-speed)*(0.38 if speed>21.5 else 0.8)-pitch*4.0-absf(bank)*0.7
 speed=clampf(speed+acceleration*delta,12.5,40.0)
 var side_target := bank*speed*(0.49 if dive else 0.72)
 lateral_speed=lerpf(lateral_speed,side_target,1.0-exp(-delta*(2.8 if dive else 4.0)))

 var distance := -pos.z
 var height := float(mountain.height_at(pos.x,distance))
 var clearance := pos.y-height
 # No correction inside the band: a well-timed flare or dip remains useful.
 # The upper correction prevents the old indefinite full-pull altitude exploit.
 var high_trim := -minf(maxf(clearance-8.5,0.0)*0.24,speed*0.34)
 var lift_authority := clampf((speed-13.0)/10.0,0.15,1.0) if pitch>0.0 else 1.0
 var vertical_target := -speed*0.47+high_trim+pitch*speed*0.30*lift_authority
 var automatic_lift := 0.0
 if dive:
  vertical_target=-speed*(0.91-pitch*0.14)
 elif assistance:
  var preview_time := 0.9
  var ahead_height := float(mountain.height_at(pos.x+lateral_speed*preview_time,distance+speed*preview_time))
  # Account for the downward momentum that takes time to arrest after a tuck.
  var settling_distance := maxf(vertical_target-vertical_speed,0.0)*0.18
  var safe_sink := (ahead_height+3.1+settling_distance-pos.y)/preview_time
  var gentle_lift := maxf(4.5-clearance,0.0)*0.42
  automatic_lift=clampf(maxf(gentle_lift,safe_sink-vertical_target),0.0,speed*0.38)
  vertical_target+=automatic_lift
  # An assisted rescue remains forgiving, but an early manual flare carries
  # more speed into the next opening. There is no free spring off the ground.
  speed=maxf(12.5,speed-minf(automatic_lift*0.24,2.6)*delta)

 vertical_target=minf(-speed*0.09,vertical_target)
 var recovery_target := clampf(automatic_lift/maxf(speed*0.22,1.0),0.0,1.0)
 recovery_intensity=lerpf(recovery_intensity,recovery_target,1.0-exp(-delta*8.0))
 var response := 2.8 if dive else (6.8 if automatic_lift>0.7 else 4.8)
 vertical_speed=lerpf(vertical_speed,vertical_target,1.0-exp(-delta*response))

 if dive: flight_state="tucked"
 elif recovery_intensity>0.15: flight_state="recovering"
 elif pitch>0.2 and speed<18.5: flight_state="low_energy"
 elif pitch>0.2: flight_state="pulling_up"
 elif speed>24.0: flight_state="carrying_speed"
 else: flight_state="gliding"
 return pos+Vector3(lateral_speed,vertical_speed,-speed)*delta
