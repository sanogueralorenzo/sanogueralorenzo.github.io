extends RefCounted

const CAMERA_RESPONSE := preload("res://camera/camera_response.gd")


static func run(suite: RefCounted) -> void:
	print("DownhillCameraRig")
	suite.run_test("speed FOV is smooth monotonic and bounded", func() -> void:
		var at_zero := CAMERA_RESPONSE.speed_fov(0.0, 72.0, 82.0, 36.0)
		var at_half := CAMERA_RESPONSE.speed_fov(18.0, 72.0, 82.0, 36.0)
		var at_full := CAMERA_RESPONSE.speed_fov(36.0, 72.0, 82.0, 36.0)
		var above_full := CAMERA_RESPONSE.speed_fov(90.0, 72.0, 82.0, 36.0)
		suite.assert_near(at_zero, 72.0, 0.001)
		suite.assert_near(at_half, 77.0, 0.001)
		suite.assert_near(at_full, 82.0, 0.001)
		suite.assert_near(above_full, 82.0, 0.001)
	)
	suite.run_test("invalid reference speed remains finite", func() -> void:
		suite.assert_true(is_finite(CAMERA_RESPONSE.speed_fov(12.0, 72.0, 82.0, 0.0)))
	)
