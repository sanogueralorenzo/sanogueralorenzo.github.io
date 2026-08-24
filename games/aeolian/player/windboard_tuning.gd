class_name WindboardTuning
extends Resource

@export_category("Input response")
@export_range(1.0, 30.0, 0.5, "suffix:1/s") var keyboard_steer_attack_per_second := 7.0
@export_range(1.0, 30.0, 0.5, "suffix:1/s") var keyboard_steer_release_per_second := 10.0
@export_range(0.5, 2.0, 0.05) var analog_steer_curve_power := 1.15

@export_category("Gravity and speed")
@export_range(1.0, 30.0, 0.1, "suffix:m/s²") var gravity_mps2 := 9.8
@export_range(0.1, 3.0, 0.05) var gravity_scale := 1.1
@export_range(5.0, 80.0, 0.5, "suffix:m/s") var max_ground_speed_mps := 42.0
@export_range(5.0, 90.0, 0.5, "suffix:m/s") var max_air_speed_mps := 48.0

@export_category("Ground steering")
@export_range(5.0, 150.0, 1.0, "suffix:°/s") var low_speed_turn_rate_deg := 76.0
@export_range(5.0, 100.0, 1.0, "suffix:°/s") var high_speed_turn_rate_deg := 34.0
@export_range(5.0, 60.0, 0.5, "suffix:m/s") var turn_rate_reference_speed_mps := 32.0
@export_range(0.1, 1.0, 0.01) var tuck_turn_multiplier := 0.62
@export_range(0.0, 50.0, 0.5, "suffix:m/s²") var lateral_grip_acceleration_mps2 := 15.0
@export_range(1.0, 3.0, 0.05) var brake_grip_multiplier := 1.4

@export_category("Ground drag")
@export_range(0.0, 10.0, 0.05, "suffix:m/s²") var rolling_drag_mps2 := 0.22
@export_range(0.0, 1.0, 0.01) var tuck_drag_multiplier := 0.28
@export_range(0.0, 20.0, 0.1, "suffix:m/s²") var carve_drag_mps2 := 3.2
@export_range(0.0, 30.0, 0.1, "suffix:m/s²") var brake_drag_mps2 := 11.0

@export_category("Jump and air")
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var jump_speed_mps := 7.0
@export_range(0.0, 120.0, 1.0, "suffix:°/s") var air_turn_rate_deg := 28.0
@export_range(0.0, 20.0, 0.1, "suffix:m/s²") var air_control_acceleration_mps2 := 5.5
@export_range(0.0, 180.0, 1.0, "suffix:°/s") var air_recover_alignment_rate_deg := 70.0
@export_range(0.0, 1.0, 0.01, "suffix:s") var coyote_time_seconds := 0.12
@export_range(0.0, 1.0, 0.01, "suffix:s") var jump_recontact_grace_seconds := 0.14

@export_category("Contact")
@export_range(15.0, 80.0, 1.0, "suffix:°") var maximum_floor_angle_deg := 58.0
@export_range(0.05, 2.0, 0.01, "suffix:m") var floor_snap_length_m := 0.28
@export_range(0.1, 3.0, 0.05, "suffix:m") var ground_probe_length_m := 0.45
@export_range(0.001, 0.2, 0.001, "suffix:m") var collision_safe_margin_m := 0.02
@export_range(1.0, 30.0, 0.5, "suffix:1/s") var normal_smoothing_rate := 14.0
@export_range(0.05, 1.0, 0.01, "suffix:m") var probe_shape_radius_m := 0.18
@export_range(0.1, 2.0, 0.05) var look_ahead_time_multiplier := 1.25
@export_range(0.1, 2.0, 0.05, "suffix:m") var look_ahead_down_distance_m := 0.55
@export_range(0.25, 3.0, 0.05, "suffix:m") var minimum_look_ahead_distance_m := 1.0

@export_category("Stability and crashes")
@export_range(0.0, 3.0, 0.05, "suffix:1/s") var stability_recovery_per_second := 0.34
@export_range(1.0, 4.0, 0.05) var held_recover_stability_multiplier := 1.75
@export_range(0.0, 1.0, 0.01) var grounded_recover_threshold := 0.75
@export_range(0.0, 1.0, 0.01) var stable_slip_ratio := 0.28
@export_range(0.0, 5.0, 0.05, "suffix:1/s") var slip_stability_drain_per_second := 1.1
@export_range(0.0, 1440.0, 10.0, "suffix:°/s") \
	var terrain_normal_stress_start_deg_per_second := 300.0
@export_range(0.0, 0.1, 0.001, "suffix:stability/°") \
	var terrain_normal_stability_damage_per_excess_degree := 0.025
@export_range(0.05, 1.0, 0.01, "suffix:s") var terrain_stress_feedback_cooldown_seconds := 0.20
@export_range(0.05, 1.0, 0.01, "suffix:s") var zero_stability_crash_delay_seconds := 0.35
@export_range(0.0, 30.0, 0.1, "suffix:m/s") var clean_landing_impact_mps := 7.5
@export_range(1.0, 40.0, 0.1, "suffix:m/s") var crash_landing_impact_mps := 16.0
@export_range(0.0, 1.0, 0.01) var clean_landing_alignment := 0.65
@export_range(0.0, 1.0, 0.01) var crash_landing_alignment := 0.2
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var minimum_alignment_crash_impact_mps := 6.0
@export_range(1.0, 40.0, 0.1, "suffix:m/s") var wall_crash_impact_mps := 14.0
@export_range(0.1, 1.0, 0.01) var recoverable_landing_min_speed_retention := 0.72
