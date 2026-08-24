extends RefCounted


static func run(suite: RefCounted) -> void:
	print("MovementCourseGeometry")
	var course := MovementCourseGeometry.new()
	suite.run_test("authored station heights are continuous", func() -> void:
		for station: float in [12.0, 72.0, 96.0, 142.0, 158.0, 238.0, 286.0, 306.0, 316.0, 324.0, 370.0, 450.0]:
			var before := course.surface_height(0.0, station - 0.001)
			var after := course.surface_height(0.0, station + 0.001)
			suite.assert_near(before, after, 0.01, "Height seam at d=%.1f" % station)
	)
	suite.run_test("planar stations expose their authored grades", func() -> void:
		var samples := {
			20.0: 8.0,
			110.0: 24.0,
			292.0: 14.0,
			340.0: 16.0,
			400.0: 22.0,
			458.0: 6.0,
		}
		for d: float in samples:
			var slope := rad_to_deg(course.surface_normal(0.0, d).angle_to(Vector3.UP))
			suite.assert_near(slope, samples[d], 0.1, "Unexpected grade at d=%.1f" % d)
	)
	suite.run_test("bank ribbon raises opposite edges in both directions", func() -> void:
		suite.assert_true(course.surface_height(5.0, 175.0) > course.surface_height(-5.0, 175.0))
		suite.assert_true(course.surface_height(5.0, 210.0) < course.surface_height(-5.0, 210.0))
		suite.assert_near(course.surface_height(5.0, 158.0), course.surface_height(-5.0, 158.0), 0.001)
	)
	suite.run_test("jump gap and widening are explicit", func() -> void:
		var upper: PackedFloat32Array = course._upper_rows()
		var lower: PackedFloat32Array = course._lower_rows()
		suite.assert_near(upper[upper.size() - 1], 316.0, 0.001)
		suite.assert_near(lower[0], 324.0, 0.001)
		suite.assert_near(course.half_width(300.0), 12.0, 0.001)
		suite.assert_near(course.half_width(330.0), 15.0, 0.001)
	)
	suite.run_test("finish lane is bounded inside the authored runout", func() -> void:
		suite.assert_true(MovementCourseGeometry.FINISH_TRIGGER_D < MovementCourseGeometry.COURSE_END_D)
		suite.assert_true(MovementCourseGeometry.FINISH_MIN_X < MovementCourseGeometry.FINISH_MAX_X)
		suite.assert_true(
			MovementCourseGeometry.FINISH_MIN_X > -course.half_width(
				MovementCourseGeometry.FINISH_TRIGGER_D
			)
		)
		suite.assert_true(
			MovementCourseGeometry.FINISH_MAX_X < course.half_width(
				MovementCourseGeometry.FINISH_TRIGGER_D
			)
		)
	)
	suite.run_test("analytic anchor transform is finite and seated", func() -> void:
		var anchor := course.surface_transform(0.0, 110.0)
		suite.assert_true(anchor.origin.is_finite())
		suite.assert_true(anchor.basis.is_finite())
		suite.assert_near(
			anchor.origin.distance_to(Vector3(0.0, course.surface_height(0.0, 110.0), -110.0)),
			0.86,
			0.001
		)
	)
	course.free()
